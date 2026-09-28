// Fixed diagnostic code, never linked into Cascade. Socket is created in provider init.
#include "SocketConfig.h"
#include <errno.h>
#include <math.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>
#include <uuid/uuid.h>

typedef struct {
    uint32_t magic, sequence;
    int32_t pid;
    char instance[37];
    double guardDeadline;
    unsigned char challenge[32];
} Frame;

static void fail(const char *stage) {
    fprintf(stderr, "startup probe failure: %s errno=%d\n", stage, errno);
    printf("{\"event\":\"observer-error\",\"stage\":\"%s\",\"errno\":%d}\n", stage, errno);
    fflush(stdout); _exit(90);
}

static void transfer(int fd, void *bytes, size_t count, int sending) {
    unsigned char *p = bytes;
    while (count) {
        ssize_t n = sending ? write(fd, p, count) : read(fd, p, count);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) fail(sending ? "write" : "read");
        count -= (size_t)n; p += n;
    }
}

static struct sockaddr_un address(void) {
    struct sockaddr_un value = {0};
    if (strlen(STARTUP_SOCKET_PATH) >= sizeof(value.sun_path)) fail("socket-path-length");
    value.sun_family = AF_UNIX; value.sun_len = sizeof(value);
    strcpy(value.sun_path, STARTUP_SOCKET_PATH);
    return value;
}

#ifdef STARTUP_PROVIDER
void startup_probe_park(const char *instance, double guardDeadline) {
    // No fork, exec, descriptor inheritance/transfer or background worker in this fixture.
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) fail("provider-socket");
    struct sockaddr_un target = address();
    if (connect(fd, (struct sockaddr *)&target, sizeof(target))) fail("provider-connect");
    Frame frame = {0}; frame.magic = 0x43535431; frame.pid = getpid();
    if (strlen(instance) != 36) fail("instance");
    memcpy(frame.instance, instance, 37); frame.guardDeadline = guardDeadline;
    transfer(fd, &frame, sizeof(frame), 1);
    unsigned char challenge[32]; transfer(fd, challenge, sizeof(challenge), 0);
    frame.sequence = 1; frame.pid = getpid(); memcpy(frame.challenge, challenge, sizeof(challenge));
    transfer(fd, &frame, sizeof(frame), 1);
    char release = 0; transfer(fd, &release, 1, 0);
    if (release != 'R') fail("release");
    close(fd);
}
#else
#include <Security/Security.h>
#include <bsm/libbsm.h>

static double now(void) {
    struct timespec t;
    if (clock_gettime(CLOCK_MONOTONIC, &t)) fail("clock");
    return t.tv_sec + t.tv_nsec / 1e9;
}

static audit_token_t identity(int fd, SecRequirementRef requirement) {
    audit_token_t token = {0}; socklen_t length = sizeof(token);
    if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) || length != sizeof(token)) fail("peer-token");
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

static void validate(Frame *frame, audit_token_t token) {
    uuid_t parsed;
    if (frame->magic != 0x43535431 || frame->instance[36] != 0 || uuid_parse(frame->instance, parsed)
        || frame->pid != audit_token_to_pid(token) || !isfinite(frame->guardDeadline)
        || frame->guardDeadline <= now()) fail("frame");
}

static void emit(const char *event, Frame frame, audit_token_t token) {
    printf("{\"event\":\"%s\",\"authenticated\":true,\"pathVerified\":true,\"pid\":%d,"
           "\"instance\":\"%s\",\"guardDeadline\":%.9f,\"sequence\":%u,\"time\":%.9f,"
           "\"audit\":[%u,%u,%u,%u,%u,%u,%u,%u]}\n", event, audit_token_to_pid(token),
           frame.instance, frame.guardDeadline, frame.sequence, now(),
           token.val[0],token.val[1],token.val[2],token.val[3],token.val[4],token.val[5],token.val[6],token.val[7]);
}

int main(void) {
    setbuf(stdout, NULL);
    struct sigaction action = {0}; action.sa_handler = SIG_DFL;
    sigset_t mask; sigemptyset(&action.sa_mask); sigemptyset(&mask); sigaddset(&mask, SIGALRM);
    if (sigaction(SIGALRM, &action, NULL) || sigprocmask(SIG_UNBLOCK, &mask, NULL)) fail("guard");
    alarm(40); double guardDeadline = now() + 40;
    signal(SIGPIPE, SIG_IGN);
    SecRequirementRef requirement = NULL;
    CFStringRef text = CFSTR("anchor apple generic and identifier \"hylo.Cascade.AddonProbeContainer.Provider\" and certificate leaf = H\"4A857D842A5406C2D3071776FDE7B27B3098FE63\"");
    if (SecRequirementCreateWithString(text, kSecCSDefaultFlags, &requirement)) fail("requirement");
    int listener = socket(AF_UNIX, SOCK_STREAM, 0);
    if (listener < 0) fail("listener");
    umask(077);
    struct sockaddr_un local = address();
    // Refuse an existing name. The runner removes only this socket's recorded inode.
    if (bind(listener, (struct sockaddr *)&local, sizeof(local)) || listen(listener, 1)) fail("bind-listen");
    struct stat socketStat;
    if (lstat(STARTUP_SOCKET_PATH, &socketStat)) fail("socket-stat");
    printf("{\"event\":\"observer-ready\",\"pid\":%d,\"guardDeadline\":%.9f,\"device\":%llu,\"inode\":%llu}\n",
           getpid(), guardDeadline, (unsigned long long)socketStat.st_dev, (unsigned long long)socketStat.st_ino);
    int peer = accept(listener, NULL, NULL);
    if (peer < 0) fail("accept");
    close(listener);
    audit_token_t token = identity(peer, requirement);
    Frame first = {0}; transfer(peer, &first, sizeof(first), 0); validate(&first, token);
    if (first.sequence != 0) fail("first-sequence");
    emit("initializer-observed", first, token);
    char command[32]; int confirmed = 0;
    while (fgets(command, sizeof(command), stdin)) {
        command[strcspn(command, "\n")] = 0;
        if (!strcmp(command, "confirm") && !confirmed) {
            unsigned char challenge[32]; arc4random_buf(challenge, sizeof(challenge));
            transfer(peer, challenge, sizeof(challenge), 1);
            Frame second = {0}; transfer(peer, &second, sizeof(second), 0);
            audit_token_t again = identity(peer, requirement); validate(&second, again);
            if (memcmp(&token, &again, sizeof(token)) || second.sequence != 1
                || strcmp(first.instance, second.instance) || first.guardDeadline != second.guardDeadline
                || memcmp(challenge, second.challenge, sizeof(challenge))) fail("confirmation");
            confirmed = 1; emit("initializer-confirmed", second, again);
        } else if (!strcmp(command, "release") && confirmed) {
            char release = 'R'; transfer(peer, &release, 1, 1);
            puts("{\"event\":\"initializer-released\"}");
        } else if (!strcmp(command, "ping")) {
            printf("{\"event\":\"observer-ping\",\"pid\":%d}\n", getpid());
        } else if (!strcmp(command, "quit")) break;
        else fail("command");
    }
    close(peer); CFRelease(requirement);
    return 0;
}
#endif
