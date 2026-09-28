// Signed, App Sandbox enabled, deliberately noncooperative native fixture.
#include <arpa/inet.h>
#include <CoreServices/CoreServices.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;
int main(int argc, char **argv) {
    if (argc != 4 && argc != 5) return 64;
    // Diagnostic guard only: it deliberately does not qualify supervisor crash cleanup.
    alarm(3);
    const char *mode = getenv("CASCADE_DIRECT_MODE");
    int benchmark = mode && !strncmp(mode, "benchmark-", 10);
    if (argc == 5) {
        printf("{\"event\":\"replacement-running\",\"pid\":%d}\n", getpid());
        fflush(stdout);
        for (;;) pause();
    }
    if (benchmark) {
        printf("{\"event\":\"worker-ready\",\"pid\":%d,\"parentPID\":%d}\n", getpid(), getppid());
        fflush(stdout);
        char request; unsigned sequence = 0;
        while (read(STDIN_FILENO, &request, 1) == 1) {
            if (request != 'E') return 65;
            printf("{\"event\":\"echo\",\"sequence\":%u}\n", ++sequence);
            fflush(stdout);
        }
        return 0;
    }
    setbuf(stdout, NULL);
    struct rlimit initial; getrlimit(RLIMIT_NPROC, &initial);
    struct rlimit raised = { RLIM_INFINITY, RLIM_INFINITY };
    errno = 0; int raise_result = setrlimit(RLIMIT_NPROC, &raised), raise_errno = errno;
    pid_t subprocess = -1;
    char *arguments[] = { "/usr/bin/true", NULL };
    int spawn_error = posix_spawn(&subprocess, arguments[0], NULL, NULL, arguments, environ);
    if (!spawn_error) { int status; waitpid(subprocess, &status, 0); }
    errno = 0; int file = open(argv[1], O_RDONLY), file_errno = errno;
    if (file >= 0) close(file);
    errno = 0; int socket_fd = socket(AF_INET, SOCK_STREAM, 0), network_result = -1, network_errno = errno;
    if (socket_fd >= 0) {
        struct sockaddr_in address = {0};
        address.sin_len = sizeof address; address.sin_family = AF_INET;
        address.sin_port = htons(atoi(argv[2])); address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        errno = 0; network_result = connect(socket_fd, (struct sockaddr *)&address, sizeof address); network_errno = errno;
        close(socket_fd);
    }
    errno = 0; int signal_result = kill(getppid(), SIGUSR1), signal_errno = errno;
    CFURLRef application = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault,
        (const UInt8 *)argv[3], strlen(argv[3]), true);
    char fixture_info[4096]; snprintf(fixture_info, sizeof fixture_info, "%s/Contents/Info.plist", argv[3]);
    int fixture_fd = open(fixture_info, O_RDONLY), fixture_errno = errno;
    if (fixture_fd >= 0) close(fixture_fd);
    // Only the benign, newly built probe application is ever supplied by the harness.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OSStatus launch_status = LSOpenCFURLRef(application, NULL);
#pragma clang diagnostic pop
    CFRelease(application);
    // Materialize a small, bounded allocation so the metric is an actual footprint.
    volatile unsigned char *memory = malloc(16 * 1024 * 1024);
    if (!memory) return 70;
    for (size_t index = 0; index < 16 * 1024 * 1024; index += 4096) memory[index] = 1;
    printf("{\"event\":\"worker-ready\",\"pid\":%d,\"parentPID\":%d,\"processSoftLimit\":%llu,\"processHardLimit\":%llu,\"raiseResult\":%d,\"raiseErrno\":%d,\"spawnErrno\":%d,\"foreignFileResult\":%d,\"foreignFileErrno\":%d,\"networkResult\":%d,\"networkErrno\":%d,\"signalParentResult\":%d,\"signalParentErrno\":%d,\"launchServicesStatus\":%d,\"launchFixtureReadable\":%s,\"launchFixtureReadErrno\":%d}\n",
        getpid(), getppid(), initial.rlim_cur, initial.rlim_max, raise_result, raise_errno, spawn_error,
        file, file_errno, network_result, network_errno, signal_result, signal_errno, (int)launch_status,
        fixture_fd >= 0 ? "true" : "false", fixture_fd >= 0 ? 0 : fixture_errno);
    if (mode && !strcmp(mode, "exec-replacement")) {
        char replacement[4096];
        snprintf(replacement, sizeof replacement, "%s-replacement", argv[0]);
        execl(replacement, replacement, argv[1], argv[2], argv[3], "replacement", NULL);
        printf("{\"event\":\"exec-failed\",\"errno\":%d}\n", errno);
    }
    pid_t original_parent = getppid();
    unsigned ticks = 0; int orphan_reported = 0;
    for (;;) {
        memory[0] = (unsigned char)(memory[0] + 1);
        if (++ticks == 65536) {
            ticks = 0;
            if (!orphan_reported && getppid() != original_parent) {
                printf("{\"event\":\"orphan-running\",\"pid\":%d,\"parentPID\":%d}\n", getpid(), getppid());
                orphan_reported = 1;
            }
        }
    }
}
