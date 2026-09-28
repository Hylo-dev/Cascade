// Experimental native host: owns the only write end of the supervisor lease.
#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc != 7) return 64;
    setbuf(stdout, NULL);
    int lease[2];
    if (pipe(lease)) return 70;
    pid_t supervisor = fork();
    if (supervisor < 0) return 71;
    if (supervisor == 0) {
        close(lease[1]);
        char descriptor[20]; snprintf(descriptor, sizeof descriptor, "%d", lease[0]);
        execl(argv[1], argv[1], descriptor, argv[2], argv[4], argv[5], argv[6], NULL);
        _exit(72);
    }
    close(lease[0]);
    struct rlimit process_limit; getrlimit(RLIMIT_NPROC, &process_limit);
    printf("{\"event\":\"host\",\"pid\":%d,\"supervisorPID\":%d,\"case\":\"%s\",\"processSoftLimit\":%llu,\"processHardLimit\":%llu}\n", getpid(), supervisor, argv[3], process_limit.rlim_cur, process_limit.rlim_max);
    // The external harness starts the action only after a real worker-ready event.
    char trigger;
    if (read(STDIN_FILENO, &trigger, 1) != 1) { close(lease[1]); return 73; }
    if (!strcmp(argv[3], "host-crash")) { kill(getpid(), SIGKILL); return 74; }
    if (!strcmp(argv[3], "host-exit")) { close(lease[1]); return 0; }
    if (write(lease[1], "S", 1) != 1) return 75;
    int status = 0;
    while (waitpid(supervisor, &status, 0) < 0 && errno == EINTR) {}
    printf("{\"event\":\"host-alive-after-stop\",\"pid\":%d,\"supervisorStatus\":%d}\n", getpid(), status);
    close(lease[1]);
    return WIFEXITED(status) && WEXITSTATUS(status) == 0 ? 0 : 76;
}
