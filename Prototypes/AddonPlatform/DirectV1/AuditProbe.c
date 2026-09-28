// Focused public Mach message audit-trailer proof. No PID/path authentication.
#include <Security/Security.h>
#include <bsm/libbsm.h>
#include <errno.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <servers/bootstrap.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct { mach_msg_header_t header; int operation; int accepted; } Message;
typedef struct { Message message; mach_msg_max_trailer_t trailer; } Received;
static const char *boolstr(int value) { return value ? "true" : "false"; }
static OSStatus authenticate(audit_token_t token, SecRequirementRef requirement) {
    CFDataRef data = CFDataCreate(NULL, (const UInt8 *)&token, sizeof token);
    const void *keys[] = { kSecGuestAttributeAudit }, *values[] = { data };
    CFDictionaryRef attrs = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    SecCodeRef code = NULL;
    OSStatus status = SecCodeCopyGuestWithAttributes(NULL, attrs, kSecCSDefaultFlags, &code);
    if (!status) status = SecCodeCheckValidity(code, kSecCSDefaultFlags, requirement);
    if (code) CFRelease(code);
    CFRelease(attrs); CFRelease(data);
    return status;
}
static kern_return_t request(mach_port_t service, mach_port_t reply, int operation) {
    Message m = {0};
    m.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, MACH_MSG_TYPE_MAKE_SEND_ONCE);
    m.header.msgh_size = sizeof m; m.header.msgh_remote_port = service;
    m.header.msgh_local_port = reply; m.operation = operation;
    return mach_msg(&m.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT, sizeof m, 0, MACH_PORT_NULL, 500, MACH_PORT_NULL);
}
static int response(mach_port_t reply) {
    Received r = {0};
    kern_return_t result = mach_msg(&r.message.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof r, reply, 700, MACH_PORT_NULL);
    return result == KERN_SUCCESS ? r.message.accepted : -1;
}
int main(int argc, char **argv) {
    if (argc != 5) return 64;
    alarm(3); setbuf(stdout, NULL);
    if (!strcmp(argv[1], "server")) {
        mach_port_t service = MACH_PORT_NULL;
        kern_return_t checkin = bootstrap_check_in(bootstrap_port, argv[2], &service);
        printf("{\"event\":\"checkin\",\"status\":%d}\n", checkin);
        if (checkin) return 65;
        CFStringRef text = CFStringCreateWithCString(NULL, argv[3], kCFStringEncodingUTF8);
        SecRequirementRef requirement = NULL;
        OSStatus setup = SecRequirementCreateWithString(text, kSecCSDefaultFlags, &requirement);
        CFRelease(text); if (setup) return 66;
        audit_token_t session = {{0}}; int session_active = 0;
        for (int i = 0; i < 3; i++) {
            Received r = {0};
            kern_return_t received = mach_msg(&r.message.header,
                MACH_RCV_MSG | MACH_RCV_TIMEOUT | MACH_RCV_TRAILER_TYPE(MACH_MSG_TRAILER_FORMAT_0) | MACH_RCV_TRAILER_ELEMENTS(MACH_RCV_TRAILER_AUDIT),
                0, sizeof r, service, 1800, MACH_PORT_NULL);
            if (received) { printf("{\"event\":\"receive-error\",\"status\":%d}\n", received); return 67; }
            if (r.message.header.msgh_size != sizeof(Message)) return 68;
            mach_msg_audit_trailer_t *trailer = (void *)((char *)&r + round_msg(r.message.header.msgh_size));
            if (trailer->msgh_trailer_type != MACH_MSG_TRAILER_FORMAT_0 || trailer->msgh_trailer_size < sizeof(*trailer)) return 69;
            audit_token_t token = trailer->msgh_audit;
            // The original message is already queued; authenticate only after replacement exec.
            if (r.message.operation == 2) usleep(350000);
            OSStatus auth = authenticate(token, requirement);
            int same = !memcmp(&token, &session, sizeof token);
            int accepted = auth == errSecSuccess && (r.message.operation == 1 || (session_active && same));
            if (r.message.operation == 1 && accepted) { session = token; session_active = 1; }
            if (session_active && (auth != errSecSuccess || !same) && r.message.operation != 1) session_active = 0;
            printf("{\"event\":\"authenticated-message\",\"operation\":%d,\"authStatus\":%d,\"accepted\":%s,\"sessionActive\":%s,\"sameAuditToken\":%s,\"auditPID\":%d,\"auditVersion\":%u}\n",
                r.message.operation, (int)auth, boolstr(accepted), boolstr(session_active), boolstr(same), audit_token_to_pid(token), token.val[7]);
            Message reply = {0}; reply.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_MOVE_SEND_ONCE, 0);
            reply.header.msgh_remote_port = r.message.header.msgh_remote_port; reply.header.msgh_size = sizeof reply;
            reply.accepted = accepted;
            kern_return_t sent = mach_msg(&reply.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT, sizeof reply, 0, MACH_PORT_NULL, 100, MACH_PORT_NULL);
            printf("{\"event\":\"reply\",\"operation\":%d,\"status\":%d}\n", r.message.operation, sent);
        }
        CFRelease(requirement);
        return 0;
    }
    // The inherited replacement cannot remove the original App Sandbox restrictions.
    errno = 0; int fd = open(argv[4], O_RDONLY); int denied = fd < 0 && errno == EPERM;
    if (fd >= 0) close(fd);
    printf("{\"event\":\"client\",\"mode\":\"%s\",\"pid\":%d,\"foreignFileDenied\":%s}\n", argv[1], getpid(), boolstr(denied));
    mach_port_t service = MACH_PORT_NULL, reply = MACH_PORT_NULL;
    kern_return_t lookup = bootstrap_look_up(bootstrap_port, argv[2], &service);
    if (lookup || mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &reply)) return 70;
    if (!strcmp(argv[1], "original")) {
        if (request(service, reply, 1) || response(reply) != 1) return 71;
        if (request(service, reply, 2)) return 72;
        execl(argv[3], argv[3], "replacement", argv[2], argv[3], argv[4], NULL);
        printf("{\"event\":\"exec-error\",\"errno\":%d}\n", errno); return 73;
    }
    // Replacement replays the same logical session, but the kernel token changed.
    if (request(service, reply, 3)) return 74;
    int accepted = response(reply);
    printf("{\"event\":\"replacement-reply\",\"accepted\":%d}\n", accepted);
    return accepted == 0 ? 0 : 75;
}
