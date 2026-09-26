// Diagnostic only: no attach, no message to the target, no signal or task mutation.
#include <Security/Security.h>
#include <bsm/libbsm.h>
#include <mach/mach.h>
#include <sys/event.h>
#include <errno.h>
#include <limits.h>
#include <math.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

static void fail(const char *stage, int status) {
    printf("{\"event\":\"identity-error\",\"stage\":\"%s\",\"status\":%d}\n",stage,status);
    fflush(stdout); exit(90);
}
static double now(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC,&ts)) fail("clock",errno);
    return ts.tv_sec + ts.tv_nsec / 1e9;
}
static audit_token_t token(mach_port_t task) {
    audit_token_t value = {{0}}; mach_msg_type_number_t count = TASK_AUDIT_TOKEN_COUNT;
    kern_return_t status = task_info(task,TASK_AUDIT_TOKEN,(task_info_t)&value,&count);
    if (status || count != TASK_AUDIT_TOKEN_COUNT) fail("audit-token",status);
    return value;
}
static void authenticate(audit_token_t audit, SecRequirementRef requirement, const char *bundle) {
    CFDataRef data = CFDataCreate(NULL,(const UInt8 *)&audit,sizeof(audit));
    const void *keys[] = {kSecGuestAttributeAudit}, *values[] = {data};
    CFDictionaryRef attrs = CFDictionaryCreate(NULL,keys,values,1,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    SecCodeRef code = NULL; CFURLRef path = NULL;
    OSStatus status = SecCodeCopyGuestWithAttributes(NULL,attrs,kSecCSDefaultFlags,&code);
    if (!status) status = SecCodeCheckValidity(code,kSecCSDefaultFlags,requirement);
    if (!status) status = SecCodeCopyPath(code,kSecCSDefaultFlags,&path);
    char actual[PATH_MAX], resolved[PATH_MAX], expected[PATH_MAX];
    int pathOK = !status && path && CFURLGetFileSystemRepresentation(path,true,(UInt8 *)actual,sizeof(actual))
        && realpath(actual,resolved) && realpath(bundle,expected) && !strcmp(resolved,expected);
    if (path) CFRelease(path);
    if (code) CFRelease(code);
    CFRelease(attrs); CFRelease(data);
    if (status || !pathOK) fail("signature-or-path",status);
}
static void emit(const char *event, audit_token_t audit, mach_port_t task, double deadline) {
    mach_task_basic_info_data_t basic = {0}; mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    kern_return_t result = task_info(task,MACH_TASK_BASIC_INFO,(task_info_t)&basic,&count);
    printf("{\"event\":\"%s\",\"time\":%.9f,\"guardDeadline\":%.9f,\"authenticated\":true,\"pid\":%d,"
        "\"basicInfoStatus\":%d,\"suspendCount\":%d,\"audit\":[%u,%u,%u,%u,%u,%u,%u,%u]}\n",
        event,now(),deadline,audit_token_to_pid(audit),result,!result ? basic.suspend_count : -1,
        audit.val[0],audit.val[1],audit.val[2],audit.val[3],audit.val[4],audit.val[5],audit.val[6],audit.val[7]);
}
int main(int argc,char **argv) {
    setbuf(stdout,NULL);
    if (argc != 4) return 64;
    char *end; long candidate = strtol(argv[1],&end,10);
    if (!*argv[1] || *end || candidate <= 1 || candidate > INT_MAX) return 64;
    struct sigaction action = {0}; action.sa_handler = SIG_DFL; sigemptyset(&action.sa_mask);
    sigset_t mask; sigemptyset(&mask); sigaddset(&mask,SIGALRM);
    if (sigaction(SIGALRM,&action,NULL) || sigprocmask(SIG_UNBLOCK,&mask,NULL)) fail("guard",errno);
    double deadline = now()+35; alarm(35);
    CFStringRef text = CFStringCreateWithCString(NULL,argv[2],kCFStringEncodingUTF8);
    SecRequirementRef requirement = NULL;
    OSStatus result = SecRequirementCreateWithString(text,kSecCSDefaultFlags,&requirement);
    CFRelease(text); if (result) fail("requirement",result);
    mach_port_t name = MACH_PORT_NULL;
    kern_return_t kr = task_name_for_pid(mach_task_self(),(pid_t)candidate,&name);
    if (kr) fail("task-name-for-pid",kr);
    audit_token_t first = token(name);
    if (audit_token_to_pid(first) != candidate) fail("audit-pid",0);
    authenticate(first,requirement,argv[3]); emit("external-identity",first,name,deadline);
    int queue = kqueue(); if (queue < 0) fail("kqueue",errno);
    struct kevent change, receipt;
    EV_SET(&change,candidate,EVFILT_PROC,EV_ADD|EV_ENABLE|EV_RECEIPT,NOTE_EXIT|NOTE_EXEC|NOTE_EXITSTATUS,0,NULL);
    struct timespec zero = {0};
    int received = kevent(queue,&change,1,&receipt,1,&zero);
    if (received != 1 || receipt.ident != (uintptr_t)candidate || receipt.filter != EVFILT_PROC
        || !(receipt.flags & EV_ERROR) || receipt.data) fail("registration",received == 1 ? (int)receipt.data : errno);
    printf("{\"event\":\"registered\",\"time\":%.9f,\"pid\":%ld,\"flags\":%u,\"fflags\":%u,\"data\":%lld}\n",
        now(),candidate,receipt.flags,receipt.fflags,(long long)receipt.data);
    audit_token_t second = token(name);
    if (memcmp(&first,&second,sizeof(first))) fail("changed-audit",0);
    authenticate(second,requirement,argv[3]); emit("external-confirmed",second,name,deadline);
    char command[32];
    while (fgets(command,sizeof(command),stdin)) {
        command[strcspn(command,"\n")] = 0;
        if (!strcmp(command,"confirm")) {
            struct kevent pending;
            int n = kevent(queue,NULL,0,&pending,1,&zero);
            if (n != 0) fail("event-before-confirm",n < 0 ? errno : 0);
            audit_token_t again = token(name);
            if (memcmp(&first,&again,sizeof(first))) fail("changed-audit",0);
            authenticate(again,requirement,argv[3]); emit("external-reconfirmed",again,name,deadline);
        } else if (!strcmp(command,"watch")) {
            struct kevent event; struct timespec timeout = {.tv_sec=8};
            int n = kevent(queue,NULL,0,&event,1,&timeout);
            if (!n) { puts("{\"event\":\"no-exit\"}"); continue; }
            if (n != 1 || event.ident != (uintptr_t)candidate || event.filter != EVFILT_PROC
                || event.flags & EV_ERROR || event.fflags & NOTE_EXEC || !(event.fflags & NOTE_EXIT)) fail("kernel-event",n < 0 ? errno : 0);
            printf("{\"event\":\"kernel-exit\",\"pid\":%ld,\"time\":%.9f,\"flags\":%u,\"fflags\":%u,\"status\":%lld}\n",
                candidate,now(),event.flags,event.fflags,event.fflags & NOTE_EXITSTATUS ? (long long)event.data : -1LL);
        } else if (!strcmp(command,"control-check")) {
            // Read-only feasibility check; no attach, task mutation, or entitlement change.
            mach_port_t control = MACH_PORT_NULL;
            kern_return_t status = task_for_pid(mach_task_self(),(pid_t)candidate,&control);
            int same = 0;
            if (!status) {
                audit_token_t audit = token(control); same = !memcmp(&first,&audit,sizeof(audit));
                mach_port_deallocate(mach_task_self(),control);
            }
            printf("{\"event\":\"control-check\",\"status\":%d,\"sameAudit\":%s}\n",status,same ? "true" : "false");
        } else if (!strcmp(command,"ping")) {
            printf("{\"event\":\"observer-ping\",\"pid\":%d}\n",getpid());
        } else if (!strcmp(command,"quit")) break;
        else fail("command",0);
    }
    close(queue); mach_port_deallocate(mach_task_self(),name); CFRelease(requirement);
    return 0;
}
