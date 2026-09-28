//
// TraceProbe.c
// Cascade
//
#include <Security/Security.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <sys/ptrace.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#ifndef PROBE_ROLE
#error PROBE_ROLE required
#endif
#ifndef SIGNER_HASH
#error SIGNER_HASH required
#endif
#if defined(OWNER_FIXTURE) && defined(DEATH_FIXTURE)
#error mutually exclusive fixtures
#endif
#ifdef DEATH_FIXTURE
#include "DeathFixtureConfig.h"
static const char *fixtureOwner = "A";
static const char *fixtureIdentity(const char *role) {
    if (!strcmp(role, "Supervisor")) return DEATH_SUPERVISOR_ID;
    return !strcmp(role, "Stub") ? DEATH_A_STUB_ID : DEATH_A_WORKER_ID;
}
#endif
#ifdef OWNER_FIXTURE
#include "OwnerFixtureConfig.h"
static const char *fixtureOwner;
static const char *ownSpecimen;
static const char *crossSpecimen;
extern bool ownerStorage(const char *, const char *, const char *, const char *, const char *, bool);

/// ownerRecord exposes only the bounded existing record transport to the storage helper.
void ownerRecord(const char *payload);

/// fixtureIdentity selects only compiled identities; owner is fixed by O1–O4.
static const char *fixtureIdentity(const char *role) {
    if (!strcmp(role, "Supervisor")) return OWNER_SUPERVISOR_ID;
    if (!strcmp(role, "Stub")) return !strcmp(fixtureOwner, "A") ? OWNER_A_STUB_ID : OWNER_B_STUB_ID;
    return !strcmp(fixtureOwner, "A") ? OWNER_A_WORKER_ID : OWNER_B_WORKER_ID;
}
#endif
extern char **environ;
static const char *nonce;
static const char *phase;
static unsigned sequence;
static pid_t ownedChild = -1;
static bool childReaped;
static int childStatus;
static double guardLowerBound;
static double phaseDeadline;
static const char *expectedBaseline;
static bool unexpectedStop;

/// tracedExecPhase keeps the owner experiment separate from historical phase spelling.
static bool tracedExecPhase(void) {
#ifdef DEATH_FIXTURE
    return !strcmp(phase, "D1") || !strcmp(phase, "D2") || !strcmp(phase, "D3");
#elif defined(OWNER_FIXTURE)
    return !strcmp(phase, "O4");
#else
    return !strcmp(phase, "C");
#endif
}

/// untracedExecPhase admits only the fixed first three owner cases in this build.
static bool untracedExecPhase(void) {
#ifdef DEATH_FIXTURE
    return !strcmp(phase, "D0");
#elif defined(OWNER_FIXTURE)
    return !strcmp(phase, "O1") || !strcmp(phase, "O2") || !strcmp(phase, "O3");
#else
    return !strcmp(phase, "U");
#endif
}

/// monotonicSeconds provides timestamps without inferring any exit from a deadline.
static double monotonicSeconds(void) {
    struct timespec instant;
    if (clock_gettime(CLOCK_MONOTONIC, &instant) != 0) _exit(90);
    return instant.tv_sec + instant.tv_nsec / 1e9;
}

/// record writes one bounded atomic line; fixture data never carries arbitrary text.
static void record(const char *format, ...) {
    char payload[3072], line[4096];
    va_list arguments;
    va_start(arguments, format);
    int count = vsnprintf(payload, sizeof(payload), format, arguments);
    va_end(arguments);
    if (count < 0 || (size_t)count >= sizeof(payload)) _exit(91);
#if defined(OWNER_FIXTURE) || defined(DEATH_FIXTURE)
    char ownerPayload[3072];
#ifdef DEATH_FIXTURE
    // Self-observed membership is diagnostic only. Fixed code never changes it.
    int ownerLength = snprintf(ownerPayload, sizeof(ownerPayload),
        "\"owner\":\"%s\",\"pgid\":%d,\"sid\":%d,%s", fixtureOwner, getpgrp(), getsid(0), payload);
#else
    int ownerLength = snprintf(ownerPayload, sizeof(ownerPayload), "\"owner\":\"%s\",%s", fixtureOwner, payload);
#endif
    if (ownerLength <= 0 || (size_t)ownerLength >= sizeof(ownerPayload)) _exit(91);
    const char *recordPayload = ownerPayload;
#else
    const char *recordPayload = payload;
#endif
    count = snprintf(line, sizeof(line),
        "{\"nonce\":\"%s\",\"phase\":\"%s\",\"role\":\"%s\",\"pid\":%d,\"sequence\":%u,\"time\":%.9f,\"clock\":\"CLOCK_MONOTONIC\",%s}\n",
        nonce, phase, PROBE_ROLE, getpid(), ++sequence, monotonicSeconds(), recordPayload);
    if (count < 0 || (size_t)count >= sizeof(line) || sequence > 32 ||
        write(STDOUT_FILENO, line, (size_t)count) != count) _exit(92);
}

#ifdef OWNER_FIXTURE
void ownerRecord(const char *payload) { record("%s", payload); }
#endif

/// number rejects missing and wrongly typed public Security information.
static bool number(CFDictionaryRef information, CFStringRef key, int64_t *value) {
    CFTypeRef object = CFDictionaryGetValue(information, key);
    return object && CFGetTypeID(object) == CFNumberGetTypeID() &&
        CFNumberGetValue(object, kCFNumberSInt64Type, value);
}

/// string copies only restricted signature identifiers suitable for the bounded record.
static bool string(CFDictionaryRef information, CFStringRef key, char *buffer, size_t size) {
    CFTypeRef object = CFDictionaryGetValue(information, key);
    if (!object || CFGetTypeID(object) != CFStringGetTypeID() ||
        !CFStringGetCString(object, buffer, (CFIndex)size, kCFStringEncodingUTF8)) return false;
    return strspn(buffer, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_") == strlen(buffer);
}

/// snapshotCode uses a fresh public dynamic reference for each self or stopped-child observation.
static bool snapshotCode(const char *stage, const char *subjectRole, pid_t subjectPID, const char *baseline) {
    SecCodeRef code = NULL;
    SecRequirementRef requirement = NULL;
    CFDictionaryRef information = NULL;
    // Only the first post-exec Worker self-query gets diagnostic milestones.
    bool progress = (tracedExecPhase() || untracedExecPhase()) && !strcmp(PROBE_ROLE, "Worker") &&
        !strcmp(stage, "S4") && subjectPID == 0;
    if (progress) record("\"kind\":\"workerProgress\",\"point\":\"CFStringCreateWithFormat\",\"boundary\":\"before\"");
#if defined(OWNER_FIXTURE) || defined(DEATH_FIXTURE)
    CFStringRef expression = CFStringCreateWithFormat(NULL, NULL,
        CFSTR("anchor apple generic and identifier \"%s\" and certificate leaf = H\"%s\""),
        fixtureIdentity(subjectRole), SIGNER_HASH);
#else
    CFStringRef expression = CFStringCreateWithFormat(NULL, NULL,
        CFSTR("anchor apple generic and identifier \"hylo.Cascade.Tracing.%s\" and certificate leaf = H\"%s\""),
        subjectRole, SIGNER_HASH);
#endif
    if (progress) record("\"kind\":\"workerProgress\",\"point\":\"CFStringCreateWithFormat\",\"boundary\":\"after\",\"created\":%s", expression ? "true" : "false");
    bool guest = subjectPID > 0;
    OSStatus api;
    if (guest) {
        CFNumberRef pid = CFNumberCreate(NULL, kCFNumberIntType, &subjectPID);
        const void *keys[] = {kSecGuestAttributePid};
        const void *values[] = {pid};
        CFDictionaryRef attributes = CFDictionaryCreate(NULL, keys, values, 1,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        api = SecCodeCopyGuestWithAttributes(NULL, attributes, kSecCSDefaultFlags, &code);
        CFRelease(attributes);
        CFRelease(pid);
    } else {
        if (progress) record("\"kind\":\"workerProgress\",\"point\":\"SecCodeCopySelf\",\"boundary\":\"before\"");
        api = SecCodeCopySelf(kSecCSDefaultFlags, &code);
        if (progress) record("\"kind\":\"workerProgress\",\"point\":\"SecCodeCopySelf\",\"boundary\":\"after\",\"apiStatus\":%d", (int)api);
    }
    OSStatus copySelfStatus = guest ? -1 : api;
    OSStatus copyGuestStatus = guest ? api : -1;
    if (api == errSecSuccess) {
        if (progress) record("\"kind\":\"workerProgress\",\"point\":\"SecRequirementCreateWithString\",\"boundary\":\"before\"");
        api = SecRequirementCreateWithString(expression, kSecCSDefaultFlags, &requirement);
        if (progress) record("\"kind\":\"workerProgress\",\"point\":\"SecRequirementCreateWithString\",\"boundary\":\"after\",\"apiStatus\":%d", (int)api);
    }
    OSStatus requirementStatus = api;
    OSStatus validity = api;
    if (api == errSecSuccess) {
        if (progress) record("\"kind\":\"workerProgress\",\"point\":\"SecCodeCheckValidity\",\"boundary\":\"before\"");
        validity = SecCodeCheckValidity(code, kSecCSDefaultFlags, requirement);
        if (progress) record("\"kind\":\"workerProgress\",\"point\":\"SecCodeCheckValidity\",\"boundary\":\"after\",\"apiStatus\":%d", (int)validity);
        if (progress) record("\"kind\":\"workerProgress\",\"point\":\"SecCodeCopySigningInformation\",\"boundary\":\"before\"");
        api = SecCodeCopySigningInformation((SecStaticCodeRef)code,
            kSecCSDynamicInformation | kSecCSSigningInformation, &information);
        if (progress) record("\"kind\":\"workerProgress\",\"point\":\"SecCodeCopySigningInformation\",\"boundary\":\"after\",\"apiStatus\":%d", (int)api);
    }
    if (progress) record("\"kind\":\"workerProgress\",\"point\":\"extractSigningFields\",\"boundary\":\"before\"");
    int64_t status = 0, flags = 0, runtime = 0;
    char identifier[128] = "", team[64] = "", hash[129] = "";
    const char *entitlements = "unknown";
    bool available = api == errSecSuccess && number(information, kSecCodeInfoStatus, &status) &&
        number(information, kSecCodeInfoFlags, &flags) && number(information, kSecCodeInfoRuntimeVersion, &runtime) &&
        string(information, kSecCodeInfoIdentifier, identifier, sizeof(identifier)) &&
        string(information, kSecCodeInfoTeamIdentifier, team, sizeof(team));
    if (information) {
        CFTypeRef unique = CFDictionaryGetValue(information, kSecCodeInfoUnique);
        if (unique && CFGetTypeID(unique) == CFDataGetTypeID() && CFDataGetLength(unique) <= 64 && CFDataGetLength(unique) > 0) {
            for (CFIndex index = 0; index < CFDataGetLength(unique); index++)
                (void)snprintf(hash + index * 2, 3, "%02x", CFDataGetBytePtr(unique)[index]);
        } else available = false;
        CFTypeRef dictionary = CFDictionaryGetValue(information, kSecCodeInfoEntitlementsDict);
        CFTypeRef raw = CFDictionaryGetValue(information, kSecCodeInfoEntitlements);
        if (!dictionary && !raw) entitlements = "none";
        else if (dictionary && CFGetTypeID(dictionary) == CFDictionaryGetTypeID()) {
            if (CFDictionaryGetCount(dictionary) == 0) entitlements = "none";
            else if (CFDictionaryGetCount(dictionary) == 1 &&
                CFDictionaryGetValue(dictionary, CFSTR("com.apple.security.app-sandbox")) == kCFBooleanTrue)
                entitlements = "sandbox";
#if defined(OWNER_FIXTURE) || defined(DEATH_FIXTURE)
            else if (CFDictionaryGetCount(dictionary) == 2 &&
                CFDictionaryGetValue(dictionary, CFSTR("com.apple.security.app-sandbox")) == kCFBooleanTrue &&
                CFDictionaryGetValue(dictionary, CFSTR("com.apple.security.inherit")) == kCFBooleanTrue)
                entitlements = "inherit";
#endif
        }
    }
    if (progress) record("\"kind\":\"workerProgress\",\"point\":\"extractSigningFields\",\"boundary\":\"after\",\"fieldsAvailable\":%s", available ? "true" : "false");
    char measuredBaseline[512];
    int baselineLength = snprintf(measuredBaseline, sizeof(measuredBaseline), "%lld:%lld:%lld:%s:%s:%s",
        (long long)status, (long long)flags, (long long)runtime, hash, team, entitlements);
#if defined(OWNER_FIXTURE) || defined(DEATH_FIXTURE)
    if (baseline && !strcmp(baseline, "-")) baseline = NULL;
#endif
    bool matched = baselineLength > 0 && (size_t)baselineLength < sizeof(measuredBaseline) &&
        (!baseline || !strcmp(measuredBaseline, baseline));
    record("\"kind\":\"snapshot\",\"stage\":\"%s\",\"subjectRole\":\"%s\",\"subjectPID\":%d,\"source\":\"%s\",\"copyGuestStatus\":%d,\"baselineMatched\":%s,\"api\":%d,\"validity\":%d,\"copySelfStatus\":%d,\"requirementStatus\":%d,\"informationStatus\":%d,\"fieldsAvailable\":%s,\"status\":%lld,\"flags\":%lld,\"runtime\":%lld,\"identity\":\"%s\",\"team\":\"%s\",\"hash\":\"%s\",\"entitlements\":\"%s\",\"valid\":%s,\"hard\":%s,\"kill\":%s,\"debugged\":%s,\"platform\":%s",
        stage, subjectRole, guest ? subjectPID : getpid(), guest ? "guest" : "self", (int)copyGuestStatus, matched ? "true" : "false", available ? (int)api : (api ? (int)api : -1), (int)validity, (int)copySelfStatus, (int)requirementStatus, (int)api, available ? "true" : "false",
        (long long)status, (long long)flags, (long long)runtime, identifier, team, hash, entitlements,
        status & kSecCodeStatusValid ? "true" : "false", status & kSecCodeStatusHard ? "true" : "false",
        status & kSecCodeStatusKill ? "true" : "false", status & kSecCodeStatusDebugged ? "true" : "false",
        status & kSecCodeStatusPlatform ? "true" : "false");
#if defined(OWNER_FIXTURE) || defined(DEATH_FIXTURE)
    const char *expectedProfile = !strcmp(subjectRole, "Supervisor") ? "none" :
        !strcmp(subjectRole, "Worker") ? "inherit" : "sandbox";
#else
    const char *expectedProfile = !strcmp(subjectRole, "Supervisor") ? "none" : "sandbox";
#endif
    bool accepted = available && matched && validity == 0 && (status & kSecCodeStatusValid) &&
        !(status & kSecCodeStatusDebugged) && (flags & kSecCodeSignatureRuntime) &&
        !strcmp(entitlements, expectedProfile);
    if (information) CFRelease(information);
    if (requirement) CFRelease(requirement);
    if (code) CFRelease(code);
    CFRelease(expression);
    return accepted;
}

/// snapshot checks this image against the same-build baseline when phase C requires it.
static bool snapshot(const char *stage) {
    return snapshotCode(stage, PROBE_ROLE, 0, expectedBaseline);
}

/// guard records a lower bound before arming a default terminal alarm.
static void guard(unsigned seconds) {
    signal(SIGALRM, SIG_DFL);
    sigset_t signals;
    sigemptyset(&signals);
    sigaddset(&signals, SIGALRM);
    sigprocmask(SIG_UNBLOCK, &signals, NULL);
    guardLowerBound = monotonicSeconds() + seconds;
    record("\"kind\":\"guard\",\"lowerBound\":%.9f,\"seconds\":%u", guardLowerBound, seconds);
    alarm(seconds);
}

/// controls checks sandbox denials against positively opened observer resources.
static bool controls(const char *foreignFile, const char *portString, bool inherited) {
    errno = 0;
    int descriptor = open(foreignFile, O_RDONLY | O_CLOEXEC);
    int fileError = errno;
    if (descriptor >= 0) close(descriptor);
    int connection = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address = {.sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK),
                                  .sin_port = htons((uint16_t)strtoul(portString, NULL, 10))};
    errno = 0;
    int connected = connection >= 0 ? connect(connection, (struct sockaddr *)&address, sizeof(address)) : -2;
    int socketError = errno;
    if (connection >= 0) close(connection);
    struct rlimit limit = {.rlim_cur = 0, .rlim_max = 0};
    errno = 0;
    int setResult = inherited ? 0 : setrlimit(RLIMIT_NPROC, &limit);
    int setError = errno;
    struct rlimit observed;
    int getResult = getrlimit(RLIMIT_NPROC, &observed);
    limit.rlim_cur = 1; limit.rlim_max = 1;
    errno = 0;
    int raiseResult = setrlimit(RLIMIT_NPROC, &limit);
    int raiseError = errno;
    bool fileDenied = descriptor < 0 && (fileError == EACCES || fileError == EPERM);
    bool socketDenied = connected == -1 && (socketError == EACCES || socketError == EPERM);
    bool raiseDenied = raiseResult == -1 && raiseError == EPERM;
    record("\"kind\":\"controls\",\"inherited\":%s,\"softNproc\":%lld,\"fileDenied\":%s,\"fileErrno\":%d,\"socketDenied\":%s,\"socketResult\":%d,\"socketErrno\":%d,\"setResult\":%d,\"setErrno\":%d,\"hardNproc\":%lld,\"raiseDenied\":%s,\"raiseErrno\":%d",
        inherited ? "true" : "false", getResult == 0 ? (long long)observed.rlim_cur : -1,
        fileDenied ? "true" : "false", fileError, socketDenied ? "true" : "false", connected, socketError,
        setResult, setError, getResult == 0 ? (long long)observed.rlim_max : -1,
        raiseDenied ? "true" : "false", raiseError);
    return fileDenied && socketDenied && setResult == 0 && getResult == 0 && observed.rlim_max == 0 && observed.rlim_cur == 0 && raiseDenied;
}

/// exchange requires an exact nonce/stage token and closes on any partial response.
static bool exchange(int descriptor, const char *stage, bool sending) {
    char expected[128], received[128];
    int length = snprintf(expected, sizeof(expected), "%s:%s:%s", nonce, phase, stage);
    if (length <= 0 || (size_t)length >= sizeof(expected)) return false;
    double remaining = phaseDeadline - monotonicSeconds();
    if (remaining <= 0) return false;
    struct pollfd ready = {.fd = descriptor, .events = sending ? POLLOUT : POLLIN};
    if (poll(&ready, 1, (int)(remaining * 1000)) != 1 || !(ready.revents & ready.events)) return false;
    if (sending) return write(descriptor, expected, (size_t)length) == length;
    ssize_t count = read(descriptor, received, sizeof(received));
    return count == length && !memcmp(expected, received, (size_t)length);
}

/// observeChild consumes only the unreaped direct child and forwards traced terminal stops.
static bool observeChild(bool blocking) {
    if (childReaped) return true;
    int status;
    pid_t waited = waitpid(ownedChild, &status, WUNTRACED | (blocking ? 0 : WNOHANG));
    if (waited < 0 && errno == EINTR) return false;
    if (waited != ownedChild) return false;
    if (WIFEXITED(status) || WIFSIGNALED(status)) {
        childReaped = true;
        childStatus = status;
        record("\"kind\":\"childExit\",\"childPID\":%d,\"waitStatus\":%d,\"observed\":true", ownedChild, status);
        return true;
    }
    if (WIFSTOPPED(status)) {
        int stopSignal = WSTOPSIG(status);
        if (untracedExecPhase()) {
            // An ordinary stopped untraced child is cleaned up without any ptrace call.
            unexpectedStop = true;
            errno = 0;
            int killed = kill(ownedChild, SIGKILL);
            int killError = errno;
            record("\"kind\":\"cleanupRequest\",\"childPID\":%d,\"stopSignal\":%d,\"operation\":\"kill\",\"result\":%d,\"errno\":%d",
                ownedChild, stopSignal, killed, killError);
            return false;
        }
        errno = 0;
        // C never releases an unvalidated or unexpectedly stopped image for work.
        bool execPhase = tracedExecPhase();
        if (execPhase) unexpectedStop = true;
        int continued = ptrace(execPhase ? PT_KILL : PT_CONTINUE, ownedChild, (caddr_t)1, stopSignal);
        int ptraceError = errno;
        record("\"kind\":\"signalStop\",\"childPID\":%d,\"signal\":%d,\"ptraceOperation\":\"%s\",\"ptraceResult\":%d,\"continueResult\":%d,\"errno\":%d",
            ownedChild, stopSignal, execPhase ? "PT_KILL" : "PT_CONTINUE", continued, continued, ptraceError);
    }
    return false;
}

/// signalNotice lets kqueue observe SIGCHLD while retaining the supervisor's default alarm.
static void signalNotice(int value) { (void)value; }

/// awaitChild watches readiness and signal stops instead of blocking on a traced alarm.
static bool awaitChild(int queue, int descriptor, const char *stage) {
    for (unsigned eventCount = 0; eventCount < 12; eventCount++) {
        struct kevent event;
        double remaining = phaseDeadline - monotonicSeconds();
        if (remaining <= 0) return false;
        struct timespec timeout = {.tv_sec = (time_t)remaining,
                                   .tv_nsec = (long)((remaining - (time_t)remaining) * 1e9)};
        int count = kevent(queue, NULL, 0, &event, 1, &timeout);
        if (count < 0 && errno == EINTR) continue;
        if (count != 1) return false;
        if (event.filter == EVFILT_SIGNAL) { if (observeChild(false)) return exchange(descriptor, stage, false); }
        if (event.filter == EVFILT_READ) return exchange(descriptor, stage, false);
    }
    return false;
}

/// executeStoppedWorker accepts only an owned kernel exec stop and authenticates its fresh image.
static bool executeStoppedWorker(int queue, int control, int response, const char *workerBaseline) {
    struct kevent removeResponse;
    EV_SET(&removeResponse, response, EVFILT_READ, EV_DELETE, 0, 0, NULL);
    if (kevent(queue, &removeResponse, 1, NULL, 0, NULL) < 0) return false;
    if (phaseDeadline - monotonicSeconds() <= 0.1) return false;
    record("\"kind\":\"execGrant\",\"childPID\":%d", ownedChild);
    if (!exchange(control, "exec", true)) return false;
    for (unsigned attempt = 0; attempt < 12; attempt++) {
        int status = 0;
        pid_t waited = waitpid(ownedChild, &status, WUNTRACED | WNOHANG);
        if (waited == ownedChild) {
            if (WIFEXITED(status) || WIFSIGNALED(status)) {
                childReaped = true;
                childStatus = status;
                record("\"kind\":\"childExit\",\"childPID\":%d,\"waitStatus\":%d,\"observed\":true", ownedChild, status);
                return false;
            }
            record("\"kind\":\"execStop\",\"childPID\":%d,\"waitStatus\":%d,\"signal\":%d,\"observed\":%s",
                ownedChild, status, WIFSTOPPED(status) ? WSTOPSIG(status) : 0, WIFSTOPPED(status) ? "true" : "false");
            if (!WIFSTOPPED(status) || WSTOPSIG(status) != SIGTRAP ||
                phaseDeadline - monotonicSeconds() <= 0.1) return false;
            // No Stub code object survives: snapshotCode creates/releases a fresh reference here.
            if (!snapshotCode("S3", "Worker", ownedChild, workerBaseline) ||
                phaseDeadline - monotonicSeconds() <= 0.1) return false;
#ifdef DEATH_FIXTURE
            if (!strcmp(phase, "D2")) {
                record("\"kind\":\"heldStop\",\"childPID\":%d,\"terminal\":true", ownedChild);
                // No observer token is ever sent here. EOF, timeout, malformed or
                // even an exact unexpected token always enters owned cleanup.
                (void)exchange(STDIN_FILENO, "death-hold", false);
                record("\"kind\":\"holdFailure\",\"childPID\":%d", ownedChild);
                return false;
            }
#endif
            record("\"kind\":\"continueIntent\",\"childPID\":%d", ownedChild);
            double requestTime = monotonicSeconds();
            errno = 0;
            int continued = ptrace(PT_CONTINUE, ownedChild, (caddr_t)1, 0);
            int continueError = errno;
            record("\"kind\":\"continue\",\"childPID\":%d,\"requestTime\":%.9f,\"result\":%d,\"errno\":%d",
                ownedChild, requestTime, continued, continueError);
            return continued == 0;
        }
        if (waited < 0 && errno != EINTR) return false;
        double remaining = phaseDeadline - monotonicSeconds();
        if (remaining <= 0) return false;
        struct timespec timeout = {.tv_sec = (time_t)remaining,
                                   .tv_nsec = (long)((remaining - (time_t)remaining) * 1e9)};
        struct kevent event;
        int count = kevent(queue, NULL, 0, &event, 1, &timeout);
        if (count < 0 && errno == EINTR) continue;
        if (count != 1) return false;
    }
    return false;
}

/// supervisor samples only its fixed child, reserving the terminal guards for cleanup.
static int supervisor(const char *childPath, const char *foreignFile, const char *port,
                      const char *workerPath, const char *stubBaseline, const char *workerBaseline) {
    guard(3);
    if (!snapshot("S0")) return 20;
    int control[2], response[2];
    if (pipe(control) || pipe(response)) return 21;
    int queue = kqueue();
    if (queue < 0) return 22;
    fcntl(queue, F_SETFD, FD_CLOEXEC);
    signal(SIGCHLD, signalNotice);
    struct kevent registrations[2];
    EV_SET(&registrations[0], response[0], EVFILT_READ, EV_ADD, 0, 0, NULL);
    EV_SET(&registrations[1], SIGCHLD, EVFILT_SIGNAL, EV_ADD, 0, 0, NULL);
    if (kevent(queue, registrations, 2, NULL, 0, NULL) < 0) return 23;
    posix_spawn_file_actions_t actions;
    int setup = posix_spawn_file_actions_init(&actions);
    // fd 9 is fixed only inside this child; all original pipe ends are closed there.
    if (!setup) setup = posix_spawn_file_actions_adddup2(&actions, control[0], STDIN_FILENO);
    if (!setup) setup = posix_spawn_file_actions_adddup2(&actions, response[1], 9);
    int ends[] = {control[0], control[1], response[0], response[1]};
    for (unsigned index = 0; index < 4 && !setup; index++) setup = posix_spawn_file_actions_addclose(&actions, ends[index]);
    char *arguments[] = {(char *)childPath, (char *)phase, (char *)nonce, (char *)foreignFile, (char *)port,
                         (char *)workerPath, (char *)stubBaseline, (char *)workerBaseline,
#ifdef OWNER_FIXTURE
                         (char *)ownSpecimen, (char *)crossSpecimen,
#endif
                         NULL};
    int spawned = setup ? setup : posix_spawn(&ownedChild, childPath, &actions, NULL, arguments, environ);
    posix_spawn_file_actions_destroy(&actions);
    close(control[0]); close(response[1]);
    record("\"kind\":\"spawn\",\"result\":%d,\"childPID\":%d", spawned, ownedChild);
    if (spawned) { close(control[1]); close(response[0]); close(queue); return 24; }
    // Observer registers NOTE_EXIT before the only start token is released.
    bool accepted = exchange(STDIN_FILENO, "registered", false) && exchange(control[1], "start", true);
    if (accepted) accepted = awaitChild(queue, response[0], "S1") && snapshot("S1");
    if (accepted) accepted = exchange(control[1], "S1", true) && awaitChild(queue, response[0], "S2");
    // A post-request parent snapshot is mandatory even when the child reports failure.
    if (accepted) accepted = snapshot("S2");
    if (accepted && tracedExecPhase()) accepted = executeStoppedWorker(queue, control[1], response[0], workerBaseline);
    if (accepted && untracedExecPhase()) {
        accepted = phaseDeadline - monotonicSeconds() > 0.1;
        if (accepted) {
            record("\"kind\":\"execGrant\",\"childPID\":%d", ownedChild);
            accepted = exchange(control[1], "exec", true);
        }
    }
    close(control[1]); close(response[0]);
    if (!accepted && !childReaped) {
        errno = 0;
        int killed = kill(ownedChild, SIGKILL);
        record("\"kind\":\"cleanupRequest\",\"childPID\":%d,\"result\":%d,\"errno\":%d", ownedChild, killed, errno);
    }
    for (unsigned eventCount = 0; eventCount < 12 && !childReaped; eventCount++) observeChild(true);
    close(queue);
    return accepted && !unexpectedStop && childReaped && WIFEXITED(childStatus) && WEXITSTATUS(childStatus) == 0 ? 0 : 25;
}

/// inheritedGuard observes the original timer without resetting or extending it.
static bool inheritedGuard(void) {
    struct itimerval timer;
    struct sigaction action;
    sigset_t mask;
    bool timerRead = getitimer(ITIMER_REAL, &timer) == 0;
    double remaining = timerRead ? timer.it_value.tv_sec + timer.it_value.tv_usec / 1e6 : -1;
    bool defaultSignal = sigaction(SIGALRM, NULL, &action) == 0 && action.sa_handler == SIG_DFL;
    bool unblocked = sigprocmask(0, NULL, &mask) == 0 && sigismember(&mask, SIGALRM) == 0;
    record("\"kind\":\"guardInherited\",\"lowerBound\":%.9f,\"remainingSeconds\":%.9f,\"armed\":%s,\"defaultSignal\":%s,\"unblocked\":%s",
        guardLowerBound, remaining, remaining > 0 ? "true" : "false", defaultSignal ? "true" : "false", unblocked ? "true" : "false");
    return remaining > 0 && defaultSignal && unblocked && monotonicSeconds() < phaseDeadline;
}

/// main limits exec to the generated Worker and retains the pre-exec timer and record sequence.
int main(int argc, char **argv) {
    bool isSupervisor = !strcmp(PROBE_ROLE, "Supervisor");
    if (argc < 3) return 2;
    phase = argv[1]; nonce = argv[2];
    bool execPhase = tracedExecPhase() || untracedExecPhase();
#ifdef DEATH_FIXTURE
    if (!execPhase || argc != (isSupervisor ? 10 : 8) || strlen(nonce) != 32 ||
        strspn(nonce, "0123456789abcdef") != 32 || strlen(argv[isSupervisor ? 4 : 3]) >= 512) return 3;
    if (isSupervisor && (strcmp(argv[3], DEATH_A_STUB_PATH) || strcmp(argv[6], DEATH_A_WORKER_PATH))) return 3;
    if (!isSupervisor && !strcmp(PROBE_ROLE, "Stub") && strcmp(argv[5], DEATH_A_WORKER_PATH)) return 3;
#elif defined(OWNER_FIXTURE)
    if (!execPhase || argc != (isSupervisor ? 12 : 10)) return 2;
    fixtureOwner = !strcmp(phase, "O2") ? "B" : "A";
    if ((!isSupervisor && strcmp(OWNER_COMPILED_OWNER, fixtureOwner)) ||
        strlen(nonce) != 32 || strspn(nonce, "0123456789abcdef") != 32) return 3;
    ownSpecimen = argv[isSupervisor ? 10 : 8];
    crossSpecimen = argv[isSupervisor ? 11 : 9];
    if (strlen(ownSpecimen) >= 1024 || strlen(crossSpecimen) >= 1024 ||
        strlen(argv[isSupervisor ? 4 : 3]) >= 512) return 3;
    const char *fixedStub = !strcmp(fixtureOwner, "A") ? OWNER_A_STUB_PATH : OWNER_B_STUB_PATH;
    const char *fixedWorker = !strcmp(fixtureOwner, "A") ? OWNER_A_WORKER_PATH : OWNER_B_WORKER_PATH;
    if (isSupervisor && (strcmp(argv[3], fixedStub) || strcmp(argv[6], fixedWorker))) return 3;
    if (!isSupervisor && !strcmp(PROBE_ROLE, "Stub") && strcmp(argv[5], fixedWorker)) return 3;
#else
    if (argc != (isSupervisor ? (execPhase ? 10 : 6) : (execPhase ? 8 : 5))) return 2;
    if ((strcmp(phase, "A") && strcmp(phase, "B") && !execPhase) || strlen(nonce) != 32 ||
        strspn(nonce, "0123456789abcdef") != 32) return 3;
#endif
    phaseDeadline = monotonicSeconds() + 1.5;
    setvbuf(stdout, NULL, _IONBF, 0);
    signal(SIGPIPE, SIG_IGN);
    if (isSupervisor) {
        expectedBaseline = execPhase ? argv[7] : NULL;
        return supervisor(argv[3], argv[4], argv[5], execPhase ? argv[6] : NULL,
                          execPhase ? argv[8] : NULL, execPhase ? argv[9] : NULL);
    }
    if (execPhase && !strcmp(PROBE_ROLE, "Worker")) {
        char *end = NULL;
        guardLowerBound = strtod(argv[5], &end);
        if (!end || *end || !isfinite(guardLowerBound) || guardLowerBound <= 0) return 15;
        unsigned long inheritedSequence = strtoul(argv[6], &end, 10);
        if (!end || *end || inheritedSequence == 0 || inheritedSequence > 24) return 15;
        sequence = (unsigned)inheritedSequence;
        record("\"kind\":\"workerProgress\",\"point\":\"mainEntry\",\"boundary\":\"reached\"");
        expectedBaseline = argv[7];
        phaseDeadline = guardLowerBound - 0.4;
        // stdin/fd9 were closed by Stub before exec; only bounded stdout survives.
        if (!snapshot("S4") || !inheritedGuard() || !controls(argv[3], argv[4], true)) return 16;
#ifdef OWNER_FIXTURE
        if (!ownerStorage(fixtureOwner, fixtureIdentity("Stub"), ownSpecimen, crossSpecimen,
                          OWNER_RUN_ID, !strcmp(phase, "O1") || !strcmp(phase, "O2"))) return 26;
#endif
#ifdef DEATH_FIXTURE
        if (!strcmp(phase, "D3")) {
            if (monotonicSeconds() >= phaseDeadline) return 17;
            record("\"kind\":\"idleReady\",\"terminal\":true");
            // One terminal wait, no polling, EOF trigger or renewed alarm.
            (void)pause();
            return 17;
        }
#endif
        return monotonicSeconds() < phaseDeadline ? 0 : 17;
    }
    if (execPhase && strcmp(PROBE_ROLE, "Stub")) return 3;
    expectedBaseline = execPhase ? argv[6] : NULL;
    guard(2);
    if (!exchange(STDIN_FILENO, "start", false) || !snapshot("S0")) return 10;
    if (!controls(argv[3], argv[4], false) || !snapshot("S1")) return 11;
    if (!exchange(9, "S1", true) || !exchange(STDIN_FILENO, "S1", false)) return 12;
    int traceResult = 0;
    if (!strcmp(phase, "B") || tracedExecPhase()) {
        errno = 0;
        traceResult = ptrace(PT_TRACE_ME, 0, NULL, 0);
        int traceError = errno;
        record("\"kind\":\"ptrace\",\"result\":%d,\"errno\":%d", traceResult, traceError);
    }
    bool accepted = snapshot("S2");
    if (!exchange(9, "S2", true)) return 13;
    if (execPhase && accepted && traceResult == 0) {
        if (!exchange(STDIN_FILENO, "exec", false) || phaseDeadline - monotonicSeconds() <= 0.1) return 18;
        record("\"kind\":\"execIntent\",\"targetRole\":\"Worker\"");
        char guardArgument[64], sequenceArgument[16];
        snprintf(guardArgument, sizeof(guardArgument), "%.9f", guardLowerBound);
        snprintf(sequenceArgument, sizeof(sequenceArgument), "%u", sequence);
        char *arguments[] = {argv[5], (char *)phase, (char *)nonce, argv[3], argv[4],
                             guardArgument, sequenceArgument, argv[7],
#ifdef OWNER_FIXTURE
                             (char *)ownSpecimen, (char *)crossSpecimen,
#endif
                             NULL};
        close(9); close(STDIN_FILENO);
        execve(argv[5], arguments, environ);
        int execError = errno;
        record("\"kind\":\"execFailure\",\"result\":-1,\"errno\":%d", execError);
        return 19;
    }
    close(9); close(STDIN_FILENO);
    return accepted && traceResult == 0 ? 0 : 14;
}
