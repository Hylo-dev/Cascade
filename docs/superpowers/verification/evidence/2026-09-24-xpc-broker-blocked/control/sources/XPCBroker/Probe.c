// Throwaway fixed-code two-level XPC experiment. Never linked into Cascade.
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

#define ROOT_ID "hylo.Cascade.XPCBrokerProbe"
#ifndef CHAIN
#define CHAIN "A"
#endif
#define BROKER_ID ROOT_ID ".Broker" CHAIN
#define WORKER_ID ROOT_ID ".Worker" CHAIN

static double now(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value)) _exit(76);
    return value.tv_sec + value.tv_nsec / 1e9;
}

static void requirement(char *buffer, size_t length, const char *identifier) {
    snprintf(buffer, length, "anchor apple generic and identifier \"%s\" and certificate leaf = H\"%s\"",
             identifier, PROBE_SIGNER_HASH);
}

static void constrain(xpc_connection_t connection, const char *identifier) {
    char text[512]; requirement(text, sizeof(text), identifier);
    if (!connection || xpc_connection_set_peer_code_signing_requirement(connection, text)) _exit(79);
}

#if ROLE != 2
static _Noreturn void crash_self(void) {
    if (raise(SIGKILL)) _exit(84);
    // On a dispatch thread raise may return before the process receives SIGKILL.
    // Do not race it with _exit; the independent alarm bounds a failed delivery.
    for (;;) pause();
}

static int authenticate(xpc_object_t message, const char *identifier) {
    if (xpc_get_type(message) != XPC_TYPE_DICTIONARY) return 0;
    char text[512]; requirement(text, sizeof(text), identifier);
    CFStringRef string = CFStringCreateWithCString(NULL, text, kCFStringEncodingUTF8);
    SecRequirementRef expected = NULL;
    OSStatus status = SecRequirementCreateWithString(string, kSecCSDefaultFlags, &expected);
    CFRelease(string);
    SecCodeRef code = NULL;
    if (!status) status = SecCodeCreateWithXPCMessage(message, kSecCSDefaultFlags, &code);
    if (!status) status = SecCodeCheckValidity(code, kSecCSDefaultFlags, expected);
    if (code) CFRelease(code);
    if (expected) CFRelease(expected);
    return status == 0;
}
#endif

#if ROLE != 0
static char instance[37];
static double guardDeadline;

static void identity(xpc_object_t reply) {
    xpc_dictionary_set_int64(reply, "pid", getpid());
    xpc_dictionary_set_string(reply, "instance", instance);
    xpc_dictionary_set_double(reply, "guardDeadline", guardDeadline);
}

#if ROLE == 1
static xpc_connection_t worker;
#endif

static void serve(xpc_connection_t peer) {
    constrain(peer, ROLE == 1 ? ROOT_ID : BROKER_ID);
    xpc_connection_set_event_handler(peer, ^(xpc_object_t request) {
        if (xpc_get_type(request) != XPC_TYPE_DICTIONARY) return;
        const char *op = xpc_dictionary_get_string(request, "operation");
        if (!op) _exit(80);
#if ROLE == 1
        if (!strcmp(op, "exit")) _exit(0);
        if (!strcmp(op, "crash")) crash_self();
        if (!strcmp(op,"identity")) {
            xpc_object_t reply=xpc_dictionary_create_reply(request);
            if (!reply) _exit(81);
            identity(reply);
            xpc_dictionary_set_string(reply,"operation","identity");
            xpc_connection_send_message(peer,reply); xpc_release(reply);
            return;
        }
#endif
        if (strcmp(op, "hello") && strcmp(op, "hold") && strcmp(op, "ping") &&
            (ROLE != 1 || strcmp(op, "hold-both"))) _exit(80);
        xpc_object_t reply = xpc_dictionary_create_reply(request);
        if (!reply) _exit(81);
        identity(reply);
        xpc_dictionary_set_string(reply, "operation", op);
#if ROLE == 1
        xpc_retain(peer);
        xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
        xpc_dictionary_set_string(message, "operation", !strcmp(op,"hold-both") ? "hold" : op);
        xpc_connection_send_message_with_reply(worker, message,
            dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(xpc_object_t result) {
                // Only this trusted fixture vouches for the worker's authenticated reply.
                int valid = authenticate(result, WORKER_ID);
                xpc_dictionary_set_bool(reply, "workerAuthenticated", valid);
                if (valid) xpc_dictionary_set_value(reply, "worker", result);
                xpc_connection_send_message(peer, reply);
                xpc_release(reply);
                xpc_release(peer);
            });
        xpc_release(message);
        // Block the serial control callback; worker reply runs on a different queue.
        if (!strcmp(op,"hold-both")) for (;;) pause();
#else
        xpc_connection_send_message(peer, reply);
        xpc_release(reply);
        if (!strcmp(op, "hold")) for (;;) pause();
#endif
    });
    xpc_connection_resume(peer);
}

int main(void) {
    guardDeadline = now() + 12;
    struct sigaction action = {0};
    action.sa_handler = SIG_DFL; sigemptyset(&action.sa_mask);
    if (sigaction(SIGALRM, &action, NULL)) return 77;
    sigset_t signals; sigemptyset(&signals); sigaddset(&signals, SIGALRM);
    if (sigprocmask(SIG_UNBLOCK, &signals, NULL)) return 78;
    alarm(12);
    uuid_t id; uuid_generate_random(id); uuid_unparse_lower(id, instance);
#if ROLE == 1
    worker = xpc_connection_create(WORKER_ID, dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0));
    constrain(worker, WORKER_ID);
    xpc_connection_set_event_handler(worker, ^(xpc_object_t event) { (void)event; });
    xpc_connection_resume(worker);
#endif
    xpc_main(serve);
}
#else
static void received(xpc_object_t reply, char chain, const char *expected) {
    if (xpc_get_type(reply) != XPC_TYPE_DICTIONARY) {
        if (reply == XPC_ERROR_CONNECTION_INVALID || reply == XPC_ERROR_CONNECTION_INTERRUPTED)
            printf("{\"event\":\"connection-invalid\",\"chain\":\"%c\"}\n", chain);
        else puts("{\"event\":\"connection-error\"}");
        return;
    }
    if (!authenticate(reply, expected)) { puts("{\"event\":\"authentication-error\"}"); return; }
    const char *replyOp=xpc_dictionary_get_string(reply,"operation");
    if (replyOp && !strcmp(replyOp,"identity")) {
        const char *id=xpc_dictionary_get_string(reply,"instance"); uuid_t parsed;
        if (!id || uuid_parse(id,parsed)) { puts("{\"event\":\"protocol-error\"}"); return; }
        printf("{\"event\":\"%c-control\",\"authenticated\":true,"
               "\"broker\":{\"pid\":%lld,\"instance\":\"%s\",\"guardDeadline\":%.9f}}\n",
               chain,(long long)xpc_dictionary_get_int64(reply,"pid"),id,
               xpc_dictionary_get_double(reply,"guardDeadline"));
        return;
    }
    xpc_object_t worker = xpc_dictionary_get_value(reply, "worker");
    if (!xpc_dictionary_get_bool(reply, "workerAuthenticated") || !worker ||
        xpc_get_type(worker) != XPC_TYPE_DICTIONARY) {
        puts("{\"event\":\"worker-discovery-error\"}"); return;
    }
    const char *op = xpc_dictionary_get_string(reply, "operation");
    const char *workerOp = xpc_dictionary_get_string(worker, "operation");
    const char *brokerID = xpc_dictionary_get_string(reply, "instance");
    const char *workerID = xpc_dictionary_get_string(worker, "instance");
    uuid_t parsed;
    if (!op || !workerOp || strcmp(!strcmp(op,"hold-both") ? "hold" : op,workerOp) ||
        (strcmp(op,"hello") && strcmp(op,"hold") && strcmp(op,"ping") && strcmp(op,"hold-both")) ||
        !brokerID || !workerID || uuid_parse(brokerID,parsed) || uuid_parse(workerID,parsed)) {
        puts("{\"event\":\"protocol-error\"}"); return;
    }
    printf("{\"event\":\"%c-%s\",\"authenticated\":true,\"workerAuthenticated\":true,"
           "\"broker\":{\"pid\":%lld,\"instance\":\"%s\",\"guardDeadline\":%.9f},"
           "\"worker\":{\"pid\":%lld,\"instance\":\"%s\",\"guardDeadline\":%.9f},\"time\":%.9f}\n",
           chain, op, (long long)xpc_dictionary_get_int64(reply,"pid"), brokerID,
           xpc_dictionary_get_double(reply,"guardDeadline"),
           (long long)xpc_dictionary_get_int64(worker,"pid"), workerID,
           xpc_dictionary_get_double(worker,"guardDeadline"), now());
}

int main(void) {
    setbuf(stdout, NULL); signal(SIGALRM, SIG_DFL); alarm(18);
    const char *identifiers[] = {ROOT_ID ".BrokerA", ROOT_ID ".BrokerB"};
    xpc_connection_t connections[2];
    xpc_connection_t controls[2]={NULL,NULL};
    for (int i=0; i<2; i++) {
        const char *identifier = identifiers[i]; char chain = 'A'+i;
        connections[i] = xpc_connection_create(identifier, dispatch_get_global_queue(QOS_CLASS_DEFAULT,0));
        constrain(connections[i], identifier);
        xpc_connection_set_event_handler(connections[i], ^(xpc_object_t event) { received(event,chain,identifier); });
        xpc_connection_resume(connections[i]);
    }
    puts("{\"event\":\"client-ready\"}");
    char command[64];
    while (fgets(command,sizeof(command),stdin)) {
        command[strcspn(command,"\n")]='\0';
        if (!strcmp(command,"quit") || !strcmp(command,"crash")) {
            printf("{\"event\":\"%s\",\"time\":%.9f}\n",command,now());
            if (!strcmp(command,"crash")) crash_self();
            _exit(0);
        }
        char chain = command[0]; const char *op = command+2;
        if ((chain!='A' && chain!='B') || command[1]!=' ' ||
            (strcmp(op,"hello") && strcmp(op,"hold") && strcmp(op,"ping") && strcmp(op,"hold-both") &&
             strcmp(op,"exit") && strcmp(op,"crash") && strcmp(op,"cancel") &&
             strcmp(op,"control") && strcmp(op,"control-exit"))) return 85;
        xpc_connection_t connection = connections[chain-'A'];
        if (!strcmp(op,"control")) {
            if (controls[chain-'A']) return 85;
            const char *identifier=identifiers[chain-'A'];
            connection=xpc_connection_create(identifier,dispatch_get_global_queue(QOS_CLASS_DEFAULT,0));
            constrain(connection,identifier);
            xpc_connection_set_event_handler(connection,^(xpc_object_t event) { received(event,chain,identifier); });
            xpc_connection_resume(connection);
            controls[chain-'A']=connection;
            op="identity";
        } else if (!strcmp(op,"control-exit")) {
            connection=controls[chain-'A'];
            if (!connection) return 85;
            op="exit";
        }
        if (!strcmp(op,"cancel")) {
            xpc_connection_cancel(connection);
            printf("{\"event\":\"action-sent\",\"time\":%.9f}\n",now());
            continue;
        }
        xpc_object_t message = xpc_dictionary_create(NULL,NULL,0);
        xpc_dictionary_set_string(message,"operation",op);
        if (!strcmp(op,"exit") || !strcmp(op,"crash")) {
            xpc_connection_send_message(connection,message);
            printf("{\"event\":\"action-sent\",\"time\":%.9f}\n",now());
        } else {
            const char *identifier = identifiers[chain-'A'];
            xpc_connection_send_message_with_reply(connection,message,
                dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),
                ^(xpc_object_t reply) { received(reply,chain,identifier); });
        }
        xpc_release(message);
    }
    return 0;
}
#endif
