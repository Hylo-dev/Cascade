// Experimental trusted supervisor. No SIGCHLD handler, automatic reaper or threads.
// The direct child stays unreaped until all sampling/signalling has finished.
#include <errno.h>
#include <fcntl.h>
#include <libproc.h>
#include <mach/mach_time.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static volatile sig_atomic_t child_signal_received = 0;
static void observe_signal(int value) { (void)value; child_signal_received = 1; }
static uint64_t nanoseconds(void) {
    struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
    return (uint64_t)now.tv_sec * 1000000000 + now.tv_nsec;
}

int main(int argc, char **argv) {
    if (argc != 6) return 64;
    setbuf(stdout, NULL);
    signal(SIGCHLD, SIG_DFL);
    signal(SIGUSR1, observe_signal);
    signal(SIGPIPE, SIG_IGN);
    int lease = atoi(argv[1]);
    if (lease < 3 || fcntl(lease, F_SETFD, FD_CLOEXEC) < 0) return 70;
    const char *mode = getenv("CASCADE_DIRECT_MODE");
    int benchmark = mode && !strncmp(mode, "benchmark-", 10);
    int target = mode && !strcmp(mode, "benchmark-reuse") ? 20 : 1;
    int requests[2]; if (pipe(requests)) return 71;
    int output[2]; if (pipe(output)) return 71;
    uint64_t started = nanoseconds();
    pid_t child = fork();
    if (child < 0) return 72;
    if (child == 0) {
        close(lease); close(output[0]);
        if (dup2(output[1], STDOUT_FILENO) < 0) _exit(73);
        close(output[1]); close(requests[1]);
        if (dup2(requests[0], STDIN_FILENO) < 0) _exit(73);
        close(requests[0]);
        // Process limits are installed here, in the child, before exec enters addon code.
        struct rlimit process_limit = {0, 0};
        if (setrlimit(RLIMIT_NPROC, &process_limit) != 0) _exit(75);
        execl(argv[2], argv[2], argv[3], argv[4], argv[5], NULL);
        _exit(74);
    }
    close(output[1]); close(requests[0]);
    struct rlimit supervisor_limit; getrlimit(RLIMIT_NPROC, &supervisor_limit);
    printf("{\"event\":\"supervisor\",\"pid\":%d,\"childPID\":%d,\"processSoftLimit\":%llu,\"processHardLimit\":%llu}\n", getpid(), child, supervisor_limit.rlim_cur, supervisor_limit.rlim_max);
    char report[4096]; size_t count = 0; int report_done = 0;
    const char *reason = NULL;
    struct rusage_info_v4 first = {0}, last = {0};
    int samples = 0, metric_error = 0, echoes = 0;
    uint64_t sent_at = 0, next_request = 0;
    struct rusage_info_v4 self_usage = {0}, host_usage = {0};
    uint64_t combined_peak = 0;
    int trusted_samples = 0;
    uint64_t host_cpu_first = 0, host_cpu_last = 0;
    while (!reason) {
        uint64_t now = nanoseconds();
        if (now - started > 3000000000ULL) { reason = "supervisor-deadline"; break; }
        if (benchmark && report_done && !sent_at && echoes < target && now >= next_request) {
            sent_at = nanoseconds();
            if (write(requests[1], "E", 1) != 1) { reason = "request-write-failed"; break; }
        }
        // WNOWAIT observes termination without releasing this child's PID identity.
        siginfo_t information = {0};
        if (waitid(P_PID, child, &information, WEXITED | WNOHANG | WNOWAIT) < 0) { reason = "waitid-error"; break; }
        if (information.si_pid == child) { reason = "child-exited"; break; }
        if (report_done) {
            struct rusage_info_v4 sample = {0};
            if (proc_pid_rusage(child, RUSAGE_INFO_V4, (rusage_info_t *)&sample) == 0) {
                if (!samples) first = sample;
                last = sample; samples++;
                if (!proc_pid_rusage(getpid(), RUSAGE_INFO_V4, (rusage_info_t *)&self_usage) &&
                    !proc_pid_rusage(getppid(), RUSAGE_INFO_V4, (rusage_info_t *)&host_usage)) {
                    uint64_t total = self_usage.ri_phys_footprint + host_usage.ri_phys_footprint;
                    if (total > combined_peak) combined_peak = total;
                    uint64_t cpu = host_usage.ri_user_time + host_usage.ri_system_time;
                    if (!trusted_samples) host_cpu_first = cpu;
                    host_cpu_last = cpu; trusted_samples++;
                }
            } else metric_error = errno;
        }
        struct pollfd descriptors[2] = {{ lease, POLLIN | POLLHUP, 0 }, { output[0], POLLIN | POLLHUP, 0 }};
        int ready = poll(descriptors, 2, 20);
        if (ready < 0 && errno != EINTR) { reason = "poll-error"; break; }
        if (descriptors[0].revents & (POLLIN | POLLHUP | POLLERR)) {
            char command;
            ssize_t amount = read(lease, &command, 1);
            if (amount == 1 && mode && !strcmp(mode, "supervisor-crash")) {
                printf("{\"event\":\"supervisor-crash\",\"pid\":%d}\n", getpid());
                kill(getpid(), SIGKILL);
            }
            if (benchmark && amount == 1 && command == 'S') continue;
            reason = amount == 0 ? "host-lease-closed" : amount == 1 && command == 'S' ? "explicit-stop" : "lease-error";
        }
        if (descriptors[1].revents & POLLIN) {
            ssize_t amount = read(output[0], report + count, sizeof report - count - 1);
            if (amount <= 0) { reason = "worker-report-missing"; continue; }
            count += amount; report[count] = 0;
            char *newline;
            while ((newline = strchr(report, '\n'))) {
                size_t length = (size_t)(newline - report) + 1;
                fwrite(report, 1, length, stdout);
                if (strstr(report, "worker-ready")) report_done = 1;
                if (benchmark && strstr(report, "\"event\":\"echo\"")) {
                    if (!sent_at) { reason = "unsolicited-echo"; break; }
                    printf("{\"event\":\"echo-latency\",\"sequence\":%d,\"milliseconds\":%.6f}\n", ++echoes, (nanoseconds() - sent_at) / 1e6);
                    sent_at = 0; next_request = nanoseconds() + 5000000;
                    if (echoes == target) reason = "explicit-stop";
                }
                memmove(report, report + length, count - length);
                count -= length; report[count] = 0;
            }
            if (count == sizeof report - 1) reason = "worker-report-oversized";
        }

    }
    // No waitpid has reaped the child yet. Even a concurrent exit cannot reuse its PID.
    uint64_t stop_started = nanoseconds();
    int stop_result = kill(child, SIGKILL), stop_errno = stop_result ? errno : 0;
    int status = 0; pid_t reaped;
    struct rusage final_usage = {0};
    do { reaped = wait4(child, &status, 0, &final_usage); } while (reaped < 0 && errno == EINTR);
    // After this one reap, never sample or signal the numeric PID again.
    mach_timebase_info_data_t timebase = {0}; mach_timebase_info(&timebase);
    printf("{\"event\":\"stopped\",\"reason\":\"%s\",\"childPID\":%d,\"reaped\":%s,\"signal\":%d,\"stopErrno\":%d,\"receivedChildSignal\":%s,\"elapsedMilliseconds\":%.2f,\"metricSamples\":%d,\"metricErrno\":%d,\"footprintBytes\":%llu,\"userCPURaw\":%llu,\"systemCPURaw\":%llu,\"cpuDeltaRaw\":%llu,\"timebaseNumerator\":%u,\"timebaseDenominator\":%u,\"wait4CPUSeconds\":%.6f,\"signalToReapMilliseconds\":%.2f}\n",
           reason, child, reaped == child ? "true" : "false", WIFSIGNALED(status) ? WTERMSIG(status) : 0,
           stop_errno, child_signal_received ? "true" : "false", (nanoseconds() - started) / 1e6,
           samples, metric_error, last.ri_phys_footprint, last.ri_user_time, last.ri_system_time,
           last.ri_user_time + last.ri_system_time - first.ri_user_time - first.ri_system_time,
           timebase.numer, timebase.denom, (double)final_usage.ru_utime.tv_sec + final_usage.ru_stime.tv_sec +
           (final_usage.ru_utime.tv_usec + final_usage.ru_stime.tv_usec) / 1e6,
           (nanoseconds() - stop_started) / 1e6);
    printf("{\"event\":\"trusted-cost\",\"samples\":%d,\"hostSupervisorPeakFootprintBytes\":%llu,\"supervisorFootprintBytes\":%llu,\"supervisorCPURaw\":%llu,\"hostCPUDeltaRaw\":%llu,\"hostCPURaw\":%llu,\"timebaseNumerator\":%u,\"timebaseDenominator\":%u}\n",
        trusted_samples, combined_peak, self_usage.ri_phys_footprint,
        self_usage.ri_user_time + self_usage.ri_system_time, host_cpu_last - host_cpu_first, host_cpu_last, timebase.numer, timebase.denom);
    close(requests[1]); close(output[0]); close(lease);
    return reaped == child && WIFSIGNALED(status) && WTERMSIG(status) == SIGKILL &&
        (!strcmp(reason, "explicit-stop") || !strcmp(reason, "host-lease-closed")) ? 0 : 1;
}
