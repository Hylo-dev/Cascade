#ifndef BOOTSTRAP_ABORT_TESTING
#define _POSIX_C_SOURCE 200809L
#endif

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

enum {
    BOOTSTRAP_ABORT_ACTIVE = -1,
    BOOTSTRAP_ABORT_EOF = 70,
    BOOTSTRAP_ABORT_PROTOCOL = 71,
    BOOTSTRAP_ABORT_DEADLINE = 72,
    BOOTSTRAP_ABORT_IO = 73,
    BOOTSTRAP_ABORT_MAX_PAYLOAD = 96,
    BOOTSTRAP_ABORT_MAX_TOTAL = 196,
    BOOTSTRAP_ABORT_MAX_PARTIAL = 97,
    BOOTSTRAP_ABORT_FRAME_BUFFER = 98
};

static const int64_t bootstrap_abort_budget_ns = 2000000000LL;

typedef struct {
    char nonce[33];
    int64_t deadline_ns;
    int64_t last_ns;
    size_t total_bytes;
    size_t partial_len;
    unsigned frame_count;
    int exit_code;
    bool normal_seen;
    uint8_t partial[BOOTSTRAP_ABORT_FRAME_BUFFER];
} BootstrapAbort;

static bool bootstrap_abort_valid_nonce(const char *nonce) {
    size_t index;

    if (nonce == NULL) {
        return false;
    }
    for (index = 0; index < 32; ++index) {
        if (!((nonce[index] >= '0' && nonce[index] <= '9') ||
              (nonce[index] >= 'a' && nonce[index] <= 'f'))) {
            return false;
        }
    }
    return nonce[32] == '\0';
}

static int bootstrap_abort_finish(BootstrapAbort *state, int code) {
    state->partial_len = 0;
    state->exit_code = code;
    return code;
}

static void bootstrap_abort_begin(BootstrapAbort *state, const char *nonce,
                                  int64_t start_ns) {
    memset(state, 0, sizeof(*state));
    state->exit_code = BOOTSTRAP_ABORT_ACTIVE;
    if (!bootstrap_abort_valid_nonce(nonce) || start_ns < 0 ||
        start_ns > INT64_MAX - bootstrap_abort_budget_ns) {
        bootstrap_abort_finish(state, BOOTSTRAP_ABORT_PROTOCOL);
        return;
    }
    memcpy(state->nonce, nonce, 33);
    state->last_ns = start_ns;
    state->deadline_ns = start_ns + bootstrap_abort_budget_ns;
}

static bool bootstrap_abort_record_matches(const BootstrapAbort *state,
                                           const uint8_t *payload,
                                           size_t length) {
    const unsigned sequence = state->frame_count + 1;
    const char *command = sequence == 1 ? "advance" : "complete";
    const size_t command_length = sequence == 1 ? 7 : 8;

    return sequence <= 2 && length == 47 + command_length &&
           payload[0] == '1' && payload[1] == '|' &&
           memcmp(payload + 2, state->nonce, 32) == 0 &&
           memcmp(payload + 34, "|bootstrap|", 11) == 0 &&
           payload[45] == (uint8_t)('0' + sequence) &&
           payload[46] == '|' &&
           memcmp(payload + 47, command, command_length) == 0;
}

static int bootstrap_abort_observe(BootstrapAbort *state, int64_t now_ns,
                                   const uint8_t *data, size_t length,
                                   bool eof, bool setup_failed,
                                   bool read_failed) {
    size_t offset = 0;

    if (state->exit_code != BOOTSTRAP_ABORT_ACTIVE) {
        return state->exit_code;
    }
    if (now_ns < 0 || now_ns < state->last_ns ||
        (length != 0 && data == NULL)) {
        return bootstrap_abort_finish(state, BOOTSTRAP_ABORT_PROTOCOL);
    }
    state->last_ns = now_ns;
    if (now_ns >= state->deadline_ns) {
        return bootstrap_abort_finish(state, BOOTSTRAP_ABORT_DEADLINE);
    }
    if (setup_failed || read_failed) {
        return bootstrap_abort_finish(state, BOOTSTRAP_ABORT_IO);
    }
    if (length > BOOTSTRAP_ABORT_MAX_TOTAL - state->total_bytes) {
        return bootstrap_abort_finish(state, BOOTSTRAP_ABORT_PROTOCOL);
    }
    state->total_bytes += length;

    while (offset < length) {
        size_t needed;
        size_t take;
        size_t payload_length;

        if (state->normal_seen || state->frame_count >= 2) {
            return bootstrap_abort_finish(state, BOOTSTRAP_ABORT_PROTOCOL);
        }
        if (state->partial_len < 2) {
            needed = 2 - state->partial_len;
            take = length - offset < needed ? length - offset : needed;
            memcpy(state->partial + state->partial_len, data + offset, take);
            state->partial_len += take;
            offset += take;
            if (state->partial_len < 2) {
                break;
            }
        }
        payload_length = ((size_t)state->partial[0] << 8) | state->partial[1];
        if (payload_length == 0 || payload_length > BOOTSTRAP_ABORT_MAX_PAYLOAD) {
            return bootstrap_abort_finish(state, BOOTSTRAP_ABORT_PROTOCOL);
        }
        needed = payload_length + 2 - state->partial_len;
        take = length - offset < needed ? length - offset : needed;
        memcpy(state->partial + state->partial_len, data + offset, take);
        state->partial_len += take;
        offset += take;
        if (state->partial_len < payload_length + 2) {
            break;
        }
        if (!bootstrap_abort_record_matches(state, state->partial + 2,
                                            payload_length)) {
            return bootstrap_abort_finish(state, BOOTSTRAP_ABORT_PROTOCOL);
        }
        ++state->frame_count;
        state->normal_seen = state->frame_count == 2;
        state->partial_len = 0;
    }

    if (eof) {
        return bootstrap_abort_finish(
            state, state->partial_len == 0 ? BOOTSTRAP_ABORT_EOF
                                           : BOOTSTRAP_ABORT_PROTOCOL);
    }
    if (state->normal_seen) {
        return bootstrap_abort_finish(state, 0);
    }
    return BOOTSTRAP_ABORT_ACTIVE;
}

#ifndef BOOTSTRAP_ABORT_TESTING
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <time.h>
#include <unistd.h>

static bool bootstrap_abort_clock(int64_t *now_ns) {
    struct timespec value;

    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0 || value.tv_sec < 0 ||
        value.tv_nsec < 0 || value.tv_nsec >= 1000000000L ||
        (uint64_t)value.tv_sec >
            ((uint64_t)INT64_MAX - (uint64_t)value.tv_nsec) / 1000000000ULL) {
        return false;
    }
    *now_ns = (int64_t)value.tv_sec * 1000000000LL + value.tv_nsec;
    return *now_ns >= 0;
}

static int bootstrap_abort_poll_timeout(const BootstrapAbort *state,
                                        int64_t now_ns) {
    const int64_t remaining = state->deadline_ns - now_ns;
    const int64_t milliseconds = (remaining + 999999LL) / 1000000LL;

    return milliseconds > INT_MAX ? INT_MAX : (int)milliseconds;
}

int main(int argc, char **argv) {
    BootstrapAbort state;
    struct pollfd control = {STDIN_FILENO, POLLIN, 0};
    uint8_t input[BOOTSTRAP_ABORT_MAX_TOTAL + 1];
    int64_t now_ns;
    int flags;
    bool setup_failed;

    if (argc != 2 || !bootstrap_abort_valid_nonce(argv[1])) {
        _exit(BOOTSTRAP_ABORT_PROTOCOL);
    }
    if (!bootstrap_abort_clock(&now_ns)) {
        _exit(BOOTSTRAP_ABORT_IO);
    }
    bootstrap_abort_begin(&state, argv[1], now_ns);
    if (state.exit_code != BOOTSTRAP_ABORT_ACTIVE) {
        _exit(state.exit_code);
    }
    flags = fcntl(STDIN_FILENO, F_GETFL);
    setup_failed = flags == -1 ||
                   fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK) == -1;
    if (!bootstrap_abort_clock(&now_ns)) {
        _exit(BOOTSTRAP_ABORT_IO);
    }
    if (bootstrap_abort_observe(&state, now_ns, NULL, 0, false, setup_failed,
                                false) != BOOTSTRAP_ABORT_ACTIVE) {
        _exit(state.exit_code);
    }

    for (;;) {
        int result;
        int io_error;
        ssize_t count;

        if (!bootstrap_abort_clock(&now_ns)) {
            _exit(BOOTSTRAP_ABORT_IO);
        }
        result = bootstrap_abort_observe(&state, now_ns, NULL, 0, false,
                                         false, false);
        if (result != BOOTSTRAP_ABORT_ACTIVE) {
            _exit(result);
        }

        control.revents = 0;
        result = poll(&control, 1, bootstrap_abort_poll_timeout(&state, now_ns));
        io_error = errno;
        if (!bootstrap_abort_clock(&now_ns)) {
            _exit(BOOTSTRAP_ABORT_IO);
        }
        if (bootstrap_abort_observe(&state, now_ns, NULL, 0, false, false,
                                    false) != BOOTSTRAP_ABORT_ACTIVE) {
            _exit(state.exit_code);
        }
        if (result < 0) {
            if (io_error == EINTR) {
                continue;
            }
            _exit(BOOTSTRAP_ABORT_IO);
        }
        if (result == 0) {
            continue;
        }
        if ((control.revents & (POLLNVAL | POLLERR)) != 0) {
            _exit(BOOTSTRAP_ABORT_IO);
        }
        if ((control.revents & (POLLIN | POLLHUP)) == 0) {
            continue;
        }

        count = read(STDIN_FILENO, input, sizeof(input));
        io_error = errno;
        if (!bootstrap_abort_clock(&now_ns)) {
            _exit(BOOTSTRAP_ABORT_IO);
        }
        if (count > 0) {
            result = bootstrap_abort_observe(&state, now_ns, input,
                                             (size_t)count, false, false, false);
        } else if (count == 0) {
            result = bootstrap_abort_observe(&state, now_ns, NULL, 0, true,
                                             false, false);
        } else if (io_error == EINTR || io_error == EAGAIN || io_error == EWOULDBLOCK) {
            result = bootstrap_abort_observe(&state, now_ns, NULL, 0, false,
                                             false, false);
        } else {
            result = bootstrap_abort_observe(&state, now_ns, NULL, 0, false,
                                             false, true);
        }
        if (result != BOOTSTRAP_ABORT_ACTIVE) {
            _exit(result);
        }
    }
}
#endif
