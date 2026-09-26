// Bounded launchd process-group hypothesis. Never signals discovered worker PIDs.
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <unistd.h>
#include <time.h>
static double monotonic(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec + t.tv_nsec / 1e9; }
int main(int argc, char **argv) {
    setbuf(stdout, NULL);
    if (argc != 4) return 64;
    // Guardrail installed before fork or any addon work; inherited across exec.
    alarm(3);
    if (!strcmp(argv[1], "helper")) {
        int p[2], gate[2]; if (pipe(p) || pipe(gate)) return 65;
        int group_setup = !strcmp(argv[3], "helper-joins-worker");
        printf("{\"event\":\"helper-session\",\"pid\":%d,\"session\":%d,\"group\":%d}\n", getpid(), getsid(0), getpgrp());
        pid_t child = fork();
        if (child < 0) return 66;
        if (!child) {
            close(p[0]); close(gate[1]);
            if (group_setup) {
                if (setpgid(0, 0)) _exit(72);
                if (write(p[1], "G", 1) != 1) _exit(73);
                char go; if (read(gate[0], &go, 1) != 1) _exit(74);
            }
            close(gate[0]);
            if (dup2(p[1], 3) < 0) _exit(67);
            if (p[1] != 3) close(p[1]);
            struct rlimit r = {0, 0}; if (setrlimit(RLIMIT_NPROC, &r)) _exit(68);
            // Capture before alarm() so this is a conservative earliest firing time.
            // A later worker-side rearm may extend, never shorten, this guard.
            double guard_deadline = monotonic() + 3.0;
            alarm(3);
            printf("{\"event\":\"guard-armed\",\"workerPID\":%d,\"deadlineLowerBound\":%.9f}\n", getpid(), guard_deadline);
            execl(argv[2], argv[2], argv[3], "worker", getenv("CASCADE_SENTINEL"), NULL);
            _exit(69);
        }
        close(p[1]); close(gate[0]);
        if (group_setup) {
            char grouped; if (read(p[0], &grouped, 1) != 1) return 75;
            errno = 0; int result = setpgid(0, child); int error = errno;
            printf("{\"event\":\"helper-join\",\"result\":%d,\"errno\":%d,\"session\":%d,\"group\":%d}\n", result, error, getsid(0), getpgrp());
            if (write(gate[1], "G", 1) != 1) return 76;
        }
        close(gate[1]);
        char ready = 0; ssize_t count = read(p[0], &ready, 1); close(p[0]);
        printf("{\"event\":\"helper-ready\",\"pid\":%d,\"workerPID\":%d,\"group\":%d,\"ready\":%s}\n", getpid(), child, getpgrp(), count == 1 && ready == 'R' ? "true" : "false");
        // Allow external kqueue observers to register before the injected crash.
        usleep(500000);
        printf("{\"event\":\"helper-kill\",\"time\":%.9f}\n", monotonic());
        kill(getpid(), SIGKILL);
        return 70;
    }
    int old_group = getpgrp();
    errno = 0; int file = open(argv[3], O_RDONLY); int file_error = errno;
    if (file >= 0) close(file);
    errno = 0; int sock = socket(AF_INET, SOCK_STREAM, 0); int sock_result = -1; int sock_error = errno;
    if (sock >= 0) {
        struct sockaddr_in address = {0}; address.sin_len = sizeof address;
        address.sin_family = AF_INET; address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        address.sin_port = htons(atoi(getenv("CASCADE_PORT")));
        errno = 0; sock_result = connect(sock, (struct sockaddr *)&address, sizeof address);
        sock_error = errno; close(sock);
    }
    struct rlimit before = {0}; getrlimit(RLIMIT_NPROC, &before);
    struct rlimit r = {RLIM_INFINITY, RLIM_INFINITY}; errno = 0;
    int raise = setrlimit(RLIMIT_NPROC, &r); int raise_error = errno;
    errno = 0;
    int changed = !strcmp(argv[1], "setsid") ? setsid() : !strcmp(argv[1], "setpgid") ? setpgid(0, 0) : -2;
    int change_error = errno;
    printf("{\"event\":\"worker-ready\",\"pid\":%d,\"parentPID\":%d,\"oldGroup\":%d,\"group\":%d,\"changeResult\":%d,\"changeErrno\":%d,\"fileResult\":%d,\"fileErrno\":%d,\"socketResult\":%d,\"socketErrno\":%d,\"hardNproc\":%llu,\"raiseResult\":%d,\"raiseErrno\":%d}\n", getpid(), getppid(), old_group, getpgrp(), changed, change_error, file, file_error, sock_result, sock_error, before.rlim_max, raise, raise_error);
    if (write(3, "R", 1) != 1) return 71;
    close(3);
    // Idle and noncooperative; no watchdog recovery is counted as containment.
    for (;;) pause();
}
