// Fixed diagnostic code, never linked into Cascade. Provider parks inside init.
#include "StartupConfig.h"
#include "StartupProvider.h"
#include <errno.h>
#include <math.h>
#include <mach/mach.h>
#include <servers/bootstrap.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <uuid/uuid.h>

typedef struct {
    mach_msg_header_t header;
    uint32_t magic, sequence;
    int32_t pid;
    char instance[37];
    double guardDeadline;
    unsigned char challenge[32];
} Message;
typedef struct { Message message; mach_msg_max_trailer_t trailer; } Received;

static void fail(const char *stage, int status) {
    fprintf(stderr, "startup probe failure: %s status=%d errno=%d\n", stage, status, errno);
    printf("{\"event\":\"observer-error\",\"stage\":\"%s\",\"status\":%d,\"errno\":%d}\n", stage, status, errno);
    fflush(stdout); _exit(90);
}
static void check(const char *stage, kern_return_t result) { if (result) fail(stage, result); }
#ifndef STARTUP_PROVIDER
static double now(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t)) fail("clock", errno);
    return t.tv_sec + t.tv_nsec / 1e9;
}
#endif
static mach_port_t receive_port(void) {
    mach_port_t port = MACH_PORT_NULL;
    check("port-allocate", mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &port));
    return port;
}
static void send_frame(mach_port_t destination, mach_port_t reply, Message frame) {
    memset(&frame.header, 0, sizeof(frame.header));
    frame.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, reply ? MACH_MSG_TYPE_MAKE_SEND : 0);
    frame.header.msgh_remote_port = destination; frame.header.msgh_local_port = reply;
    frame.header.msgh_size = sizeof(frame); frame.header.msgh_id = 0x43535431;
    check("send", mach_msg(&frame.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT,
        sizeof(frame), 0, MACH_PORT_NULL, 500, MACH_PORT_NULL));
}
static Received receive_frame(mach_port_t port) {
    Received result = {0};
    check("receive", mach_msg(&result.message.header,
        MACH_RCV_MSG | MACH_RCV_TIMEOUT | MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0)
        | MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT),
        0, sizeof(result), port, 28000, MACH_PORT_NULL));
    if (result.message.header.msgh_size != sizeof(Message)
        || result.message.header.msgh_id != 0x43535431
        || result.message.header.msgh_bits & MACH_MSGH_BITS_COMPLEX) fail("message", 0);
    return result;
}
static Message first_frame(const char *instance, double guardDeadline) {
    Message frame = {0}; frame.magic = 0x43535431; frame.pid = getpid();
    if (strlen(instance) != 36) fail("instance", 0);
    memcpy(frame.instance, instance, 37); frame.guardDeadline = guardDeadline;
    return frame;
}
static mach_port_t lookup(void) {
    mach_port_t service = MACH_PORT_NULL;
    check("lookup", bootstrap_look_up(bootstrap_port, STARTUP_MACH_SERVICE, &service));
    return service;
}

#ifdef STARTUP_PROVIDER
void startup_probe_park(const char *instance, double guardDeadline) {
    mach_port_t service = lookup(), reply = receive_port();
    Message frame = first_frame(instance, guardDeadline);
    send_frame(service, reply, frame);
    Received challenge = receive_frame(reply);
    if (challenge.message.sequence != 10) fail("challenge", 0);
    frame.sequence = 1; frame.pid = getpid();
    memcpy(frame.challenge, challenge.message.challenge, sizeof(frame.challenge));
    send_frame(service, MACH_PORT_NULL, frame);
    Received release = receive_frame(reply);
    if (release.message.sequence != 11) fail("release", 0);
    check("reply-destroy", mach_port_destroy(mach_task_self(), reply));
    check("service-deallocate", mach_port_deallocate(mach_task_self(), service));
}
#else
#include <Security/Security.h>
#include <bsm/libbsm.h>

static audit_token_t identity(Received *received, SecRequirementRef requirement) {
    size_t offset = round_msg(received->message.header.msgh_size);
    if (offset + sizeof(mach_msg_audit_trailer_t) > sizeof(*received)) fail("trailer-offset", 0);
    mach_msg_audit_trailer_t *trailer = (void *)((char *)received + offset);
    if (trailer->msgh_trailer_type != MACH_MSG_TRAILER_FORMAT_0
        || trailer->msgh_trailer_size < sizeof(*trailer)
        || offset + trailer->msgh_trailer_size > sizeof(*received)) fail("trailer", 0);
    audit_token_t token = trailer->msgh_audit;
    CFDataRef data = CFDataCreate(NULL, (const UInt8 *)&token, sizeof(token));
    const void *keys[] = {kSecGuestAttributeAudit}, *values[] = {data};
    CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    SecCodeRef code = NULL; CFURLRef path = NULL;
    OSStatus status = SecCodeCopyGuestWithAttributes(NULL, attributes, kSecCSDefaultFlags, &code);
    if (!status) status = SecCodeCheckValidity(code, kSecCSDefaultFlags, requirement);
    if (!status) status = SecCodeCopyPath(code, kSecCSDefaultFlags, &path);
    char actual[4096], resolved[4096], expected[4096];
    int pathOK = !status && path && CFURLGetFileSystemRepresentation(path, true, (UInt8 *)actual, sizeof(actual))
        && realpath(actual, resolved) && realpath(STARTUP_PROVIDER_BUNDLE, expected) && !strcmp(resolved, expected);
    if (path) CFRelease(path);
    if (code) CFRelease(code);
    CFRelease(attributes); CFRelease(data);
    if (status || !pathOK) {
        fprintf(stderr, "authentication status=%d pathMatch=%d\n", (int)status, pathOK);
        puts("{\"event\":\"authentication-error\"}"); fflush(stdout); _exit(91);
    }
    return token;
}
static void validate(Message *frame, audit_token_t token) {
    uuid_t parsed;
    if (frame->magic != 0x43535431 || frame->instance[36] != 0 || uuid_parse(frame->instance, parsed)
        || frame->pid != audit_token_to_pid(token) || !isfinite(frame->guardDeadline)
        || frame->guardDeadline <= now()) fail("frame", 0);
}
static void emit(const char *event, Message frame, audit_token_t token) {
    printf("{\"event\":\"%s\",\"authenticated\":true,\"pathVerified\":true,\"pid\":%d,"
           "\"instance\":\"%s\",\"guardDeadline\":%.9f,\"sequence\":%u,\"time\":%.9f,\"auditVersion\":%u,"
           "\"audit\":[%u,%u,%u,%u,%u,%u,%u,%u]}\n", event, audit_token_to_pid(token),
           frame.instance, frame.guardDeadline, frame.sequence, now(), audit_token_to_pidversion(token),
           token.val[0],token.val[1],token.val[2],token.val[3],token.val[4],token.val[5],token.val[6],token.val[7]);
}
int main(int argc, char **argv) {
    setbuf(stdout, NULL);
    struct sigaction action = {0}; action.sa_handler = SIG_DFL;
    sigset_t mask; sigemptyset(&action.sa_mask); sigemptyset(&mask); sigaddset(&mask, SIGALRM);
    if (sigaction(SIGALRM, &action, NULL) || sigprocmask(SIG_UNBLOCK, &mask, NULL)) fail("guard", errno);
    alarm(40); double guardDeadline = now() + 40;
    if (argc == 2 && !strcmp(argv[1], "--lookup-only")) {
        mach_port_t port = MACH_PORT_NULL;
        kern_return_t status = bootstrap_look_up(bootstrap_port, STARTUP_MACH_SERVICE, &port);
        printf("{\"event\":\"lookup-result\",\"status\":%d,\"absent\":%s}\n", status,
            status == BOOTSTRAP_UNKNOWN_SERVICE ? "true" : "false");
        if (port) mach_port_deallocate(mach_task_self(), port);
        return status == BOOTSTRAP_UNKNOWN_SERVICE ? 0 : 1;
    }
    if (argc == 2 && !strcmp(argv[1], "--negative-client")) {
        uuid_t uuid; char instance[37]; uuid_generate(uuid); uuid_unparse(uuid, instance);
        mach_port_t service = lookup(), reply = receive_port();
        send_frame(service, reply, first_frame(instance, guardDeadline));
        // Retained child remains alive while the observer rejects its wrong identity.
        while (getchar() != EOF) {}
        mach_port_destroy(mach_task_self(), reply); mach_port_deallocate(mach_task_self(), service);
        return 0;
    }
    if (argc != 1) return 64;
    SecRequirementRef requirement = NULL;
    CFStringRef text = CFSTR(STARTUP_PROVIDER_REQUIREMENT);
    check("requirement", SecRequirementCreateWithString(text, kSecCSDefaultFlags, &requirement));
    mach_port_t service = receive_port();
    check("insert-send", mach_port_insert_right(mach_task_self(), service, service, MACH_MSG_TYPE_MAKE_SEND));
    // Public but deprecated; diagnostic only. Unique name, never replace active binding.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    check("register", bootstrap_register(bootstrap_port, STARTUP_MACH_SERVICE, service));
#pragma clang diagnostic pop
    printf("{\"event\":\"observer-ready\",\"pid\":%d,\"guardDeadline\":%.9f}\n", getpid(), guardDeadline);
    Received initial = receive_frame(service);
    audit_token_t token = identity(&initial, requirement);
    Message first = initial.message; validate(&first, token);
    mach_port_t peer = first.header.msgh_remote_port;
    if (first.sequence != 0 || peer == MACH_PORT_NULL
        || MACH_MSGH_BITS_REMOTE(first.header.msgh_bits) != MACH_MSG_TYPE_PORT_SEND) fail("first-sequence-port", 0);
    emit("initializer-observed", first, token);
    char command[32]; int confirmed = 0, released = 0;
    while (fgets(command, sizeof(command), stdin)) {
        command[strcspn(command, "\n")] = 0;
        if (!strcmp(command, "confirm") && !confirmed) {
            Message challenge = {0}; challenge.sequence = 10;
            arc4random_buf(challenge.challenge, sizeof(challenge.challenge));
            send_frame(peer, MACH_PORT_NULL, challenge);
            Received received = receive_frame(service);
            audit_token_t again = identity(&received, requirement);
            Message second = received.message; validate(&second, again);
            if (memcmp(&token, &again, sizeof(token)) || second.sequence != 1
                || second.header.msgh_remote_port != MACH_PORT_NULL
                || strcmp(first.instance, second.instance) || first.guardDeadline != second.guardDeadline
                || memcmp(challenge.challenge, second.challenge, sizeof(challenge.challenge))) fail("confirmation", 0);
            confirmed = 1; emit("initializer-confirmed", second, again);
        } else if (!strcmp(command, "release") && confirmed && !released) {
            Message release = {0}; release.sequence = 11; send_frame(peer, MACH_PORT_NULL, release);
            released = 1; puts("{\"event\":\"initializer-released\"}");
        } else if (!strcmp(command, "ping")) {
            printf("{\"event\":\"observer-ping\",\"pid\":%d}\n", getpid());
        } else if (!strcmp(command, "quit")) break;
        else fail("command", 0);
    }
    mach_port_deallocate(mach_task_self(), peer); mach_port_destroy(mach_task_self(), service);
    CFRelease(requirement);
    return 0;
}
#endif
