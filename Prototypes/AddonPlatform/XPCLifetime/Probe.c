// Throwaway, fixed-code XPC lifecycle probe. Never linked into Cascade.
#include <Security/Security.h>
#include <dispatch/dispatch.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <uuid/uuid.h>
#include <xpc/xpc.h>

#define HOST_ID "hylo.Cascade.XPCLifetimeProbe"
#define SERVICE_ID HOST_ID ".Service"
#ifndef PROBE_SIGNER_HASH
#error PROBE_SIGNER_HASH must identify the actual fixture signer
#endif

static double now(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value)) _exit(76);
    return value.tv_sec + value.tv_nsec / 1e9;
}

#ifdef PROBE_SERVICE
static void guard(void) {
    struct sigaction action = {0};
    action.sa_handler = SIG_DFL;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGALRM, &action, NULL)) _exit(77);
    sigset_t signals;
    sigemptyset(&signals);
    sigaddset(&signals, SIGALRM);
    if (sigprocmask(SIG_UNBLOCK, &signals, NULL)) _exit(78);
    alarm(8);
}
#endif

static const char *requirement(const char *identifier) {
    static char buffer[512];
    snprintf(buffer, sizeof(buffer),
        "anchor apple generic and identifier \"%s\" and certificate leaf = H\"%s\"",
        identifier, PROBE_SIGNER_HASH);
    return buffer;
}

#ifdef PROBE_SERVICE
static char instance[37];
static double guardDeadline;

static void serve(xpc_connection_t peer) {
    if (xpc_connection_set_peer_code_signing_requirement(peer, requirement(HOST_ID))) _exit(79);
    xpc_connection_set_event_handler(peer, ^(xpc_object_t request) {
        if (xpc_get_type(request) != XPC_TYPE_DICTIONARY) return;
        const char *operation = xpc_dictionary_get_string(request, "operation");
        if (!operation || (strcmp(operation, "hello") && strcmp(operation, "hold") &&
                           strcmp(operation, "cooperate"))) _exit(80);
        xpc_object_t reply = xpc_dictionary_create_reply(request);
        if (!reply) _exit(81);
        xpc_dictionary_set_string(reply, "operation", operation);
        xpc_dictionary_set_string(reply, "instance", instance);
        xpc_dictionary_set_int64(reply, "pid", getpid());
        xpc_dictionary_set_double(reply, "guardDeadline", guardDeadline);
        xpc_connection_send_message(peer, reply);
        xpc_release(reply);
        if (!strcmp(operation, "hold")) {
            // Fixed noncooperative work: sleep in the callback; no CPU flood or allocation.
            for (;;) pause();
        }
        if (!strcmp(operation, "cooperate")) {
            xpc_connection_send_barrier(peer, ^{ _exit(0); });
        }
    });
    xpc_connection_resume(peer);
}

int main(void) {
    guardDeadline = now() + 8;
    guard();
    uuid_t identifier;
    uuid_generate_random(identifier);
    uuid_unparse_lower(identifier, instance);
    xpc_main(serve);
}
#else
static SecRequirementRef expected;

static void received(xpc_object_t reply) {
    if (xpc_get_type(reply) != XPC_TYPE_DICTIONARY) {
        if (reply == XPC_ERROR_CONNECTION_INVALID) puts("{\"event\":\"connection-invalid\"}");
        else if (reply == XPC_ERROR_CONNECTION_INTERRUPTED) puts("{\"event\":\"connection-interrupted\"}");
        else puts("{\"event\":\"connection-error\"}");
        return;
    }
    SecCodeRef code = NULL;
    OSStatus status = SecCodeCreateWithXPCMessage(reply, kSecCSDefaultFlags, &code);
    if (!status) status = SecCodeCheckValidity(code, kSecCSDefaultFlags, expected);
    if (code) CFRelease(code);
    const char *operation = xpc_dictionary_get_string(reply, "operation");
    const char *instance = xpc_dictionary_get_string(reply, "instance");
    uuid_t parsed;
    if (status || !operation || !instance || uuid_parse(instance, parsed) ||
        (strcmp(operation, "hello") && strcmp(operation, "hold") && strcmp(operation, "cooperate"))) {
        printf("{\"event\":\"authentication-error\",\"status\":%d}\n", (int)status);
        return;
    }
    printf("{\"event\":\"%s\",\"authenticated\":true,\"instance\":\"%s\","
           "\"pid\":%lld,\"guardDeadline\":%.9f,\"time\":%.9f}\n", operation, instance,
           (long long)xpc_dictionary_get_int64(reply, "pid"),
           xpc_dictionary_get_double(reply, "guardDeadline"), now());
}

int main(void) {
    setbuf(stdout, NULL);
    // Independent host bound; the external runner also retains its direct child.
    signal(SIGALRM, SIG_DFL);
    alarm(11);
    const char *text = requirement(SERVICE_ID);
    CFStringRef string = CFStringCreateWithCString(NULL, text, kCFStringEncodingUTF8);
    OSStatus setup = SecRequirementCreateWithString(string, kSecCSDefaultFlags, &expected);
    CFRelease(string);
    if (setup) return 82;
    xpc_connection_t connection = xpc_connection_create(SERVICE_ID,
        dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0));
    if (!connection || xpc_connection_set_peer_code_signing_requirement(connection, text)) return 83;
    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) { received(event); });
    xpc_connection_resume(connection);
    puts("{\"event\":\"client-ready\"}");
    char command[32];
    while (fgets(command, sizeof(command), stdin)) {
        command[strcspn(command, "\n")] = '\0';
        if (!strcmp(command, "quit")) {
            printf("{\"event\":\"quitting\",\"time\":%.9f}\n", now());
            _exit(0);
        }
        if (!strcmp(command, "crash")) {
            printf("{\"event\":\"crashing\",\"time\":%.9f}\n", now());
            raise(SIGKILL); _exit(84);
        }
        if (!strcmp(command, "cancel")) {
            xpc_connection_cancel(connection);
            printf("{\"event\":\"cancelled\",\"time\":%.9f}\n", now());
            continue;
        }
        if (strcmp(command, "hello") && strcmp(command, "hold") && strcmp(command, "cooperate")) return 85;
        xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
        xpc_dictionary_set_string(message, "operation", command);
        xpc_connection_send_message_with_reply(connection, message,
            dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(xpc_object_t reply) { received(reply); });
        if (!strcmp(command, "cooperate")) {
            printf("{\"event\":\"cooperate-sent\",\"time\":%.9f}\n", now());
        }
        xpc_release(message);
    }
    return 0;
}
#endif
