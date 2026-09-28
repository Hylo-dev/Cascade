#include <assert.h>
#include <stdint.h>
#include <string.h>

#define BOOTSTRAP_ABORT_TESTING 1
#include "BootstrapAbort.c"

static const char nonce[] = "0123456789abcdef0123456789abcdef";

static size_t frame(uint8_t *output, unsigned sequence, const char *command) {
    const size_t command_length = strlen(command);
    const size_t payload_length = 47 + command_length;

    output[0] = (uint8_t)(payload_length >> 8);
    output[1] = (uint8_t)payload_length;
    output[2] = '1';
    output[3] = '|';
    memcpy(output + 4, nonce, 32);
    memcpy(output + 36, "|bootstrap|", 11);
    output[47] = (uint8_t)('0' + sequence);
    output[48] = '|';
    memcpy(output + 49, command, command_length);
    return payload_length + 2;
}

static BootstrapAbort begun(void) {
    BootstrapAbort state;
    bootstrap_abort_begin(&state, nonce, 10);
    assert(state.exit_code == BOOTSTRAP_ABORT_ACTIVE);
    assert(state.deadline_ns == 2000000010LL);
    return state;
}

static void test_nonce_and_clock_boundaries(void) {
    BootstrapAbort state;
    const char *bad[] = {"", "0123456789abcdef0123456789abcde",
                         "0123456789abcdef0123456789abcdef0",
                         "0123456789abcdef0123456789abcdeF",
                         "g123456789abcdef0123456789abcdef"};
    size_t index;

    for (index = 0; index < sizeof(bad) / sizeof(bad[0]); ++index) {
        bootstrap_abort_begin(&state, bad[index], 0);
        assert(state.exit_code == BOOTSTRAP_ABORT_PROTOCOL);
    }
    bootstrap_abort_begin(&state, NULL, 0);
    assert(state.exit_code == BOOTSTRAP_ABORT_PROTOCOL);
    bootstrap_abort_begin(&state, nonce, -1);
    assert(state.exit_code == BOOTSTRAP_ABORT_PROTOCOL);
    bootstrap_abort_begin(&state, nonce, INT64_MAX - 1999999999LL);
    assert(state.exit_code == BOOTSTRAP_ABORT_PROTOCOL);

    state = begun();
    assert(bootstrap_abort_observe(&state, 9, NULL, 0, false, false, false) ==
           BOOTSTRAP_ABORT_PROTOCOL);
}

static void test_frames_chunks_and_splits(void) {
    uint8_t wire[128];
    const size_t first = frame(wire, 1, "advance");
    const size_t total = first + frame(wire + first, 2, "complete");
    size_t split;

    assert(first == 56);
    assert(total == 113);
    for (split = 0; split <= total; ++split) {
        BootstrapAbort state = begun();
        assert(bootstrap_abort_observe(&state, 11, wire, split, false, false,
                                       false) ==
               (split == total ? 0 : BOOTSTRAP_ABORT_ACTIVE));
        assert(bootstrap_abort_observe(&state, 12, wire + split, total - split,
                                       false, false, false) == 0);
    }
    {
        BootstrapAbort state = begun();
        size_t index;
        for (index = 0; index < total; ++index) {
            const int result = bootstrap_abort_observe(
                &state, 11 + (int64_t)index, wire + index, 1, false, false, false);
            assert(state.partial_len <= BOOTSTRAP_ABORT_MAX_PARTIAL);
            assert(result == (index + 1 == total ? 0 : BOOTSTRAP_ABORT_ACTIVE));
        }
    }
}

static void test_eof_timeout_and_io(void) {
    uint8_t wire[128];
    const size_t first = frame(wire, 1, "advance");
    const size_t total = first + frame(wire + first, 2, "complete");
    size_t split;
    BootstrapAbort state = begun();

    assert(bootstrap_abort_observe(&state, 11, NULL, 0, true, false, false) ==
           BOOTSTRAP_ABORT_EOF);
    state = begun();
    assert(bootstrap_abort_observe(&state, 11, wire, first, true, false, false) ==
           BOOTSTRAP_ABORT_EOF);
    for (split = 1; split < first; ++split) {
        state = begun();
        assert(bootstrap_abort_observe(&state, 11, wire, split, false, false,
                                       false) == BOOTSTRAP_ABORT_ACTIVE);
        assert(bootstrap_abort_observe(&state, 12, NULL, 0, true, false, false) ==
               BOOTSTRAP_ABORT_PROTOCOL);
    }
    state = begun();
    assert(bootstrap_abort_observe(&state, 11, wire, total, true, false, false) ==
           BOOTSTRAP_ABORT_EOF);

    state = begun();
    assert(bootstrap_abort_observe(&state, 2000000009LL, wire, 1, false, false,
                                   false) == BOOTSTRAP_ABORT_ACTIVE);
    assert(state.deadline_ns == 2000000010LL);
    assert(bootstrap_abort_observe(&state, 2000000010LL, wire + 1, total - 1,
                                   true, false, true) ==
           BOOTSTRAP_ABORT_DEADLINE);
    state = begun();
    assert(bootstrap_abort_observe(&state, 11, NULL, 0, false, true, false) ==
           BOOTSTRAP_ABORT_IO);
    state = begun();
    assert(bootstrap_abort_observe(&state, 11, NULL, 0, false, false, true) ==
           BOOTSTRAP_ABORT_IO);
}

static void test_malformed_and_fixed_limits(void) {
    uint8_t wire[256];
    uint8_t partial[97];
    size_t first = frame(wire, 1, "advance");
    size_t total = first + frame(wire + first, 2, "complete");
    BootstrapAbort state;

    /* Corrupt each authority-bearing field in an otherwise complete frame. */
    const size_t fields[] = {4, 36, 47, 49};
    for (size_t index = 0; index < sizeof(fields) / sizeof(fields[0]); ++index) {
        first = frame(wire, 1, "advance");
        wire[fields[index]] = 'x';
        state = begun();
        assert(bootstrap_abort_observe(&state, 11, wire, first, false, false,
                                       false) == BOOTSTRAP_ABORT_PROTOCOL);
    }
    first = frame(wire, 1, "advance");

    state = begun();
    wire[2] = '2';
    assert(bootstrap_abort_observe(&state, 11, wire, first, false, false, false) ==
           BOOTSTRAP_ABORT_PROTOCOL);
    wire[2] = '1';
    state = begun();
    wire[47] = '2';
    assert(bootstrap_abort_observe(&state, 11, wire, first, false, false, false) ==
           BOOTSTRAP_ABORT_PROTOCOL);
    wire[47] = '1';
    state = begun();
    wire[0] = 0;
    wire[1] = 0;
    assert(bootstrap_abort_observe(&state, 11, wire, 2, false, false, false) ==
           BOOTSTRAP_ABORT_PROTOCOL);
    state = begun();
    wire[1] = 97;
    assert(bootstrap_abort_observe(&state, 11, wire, 2, false, false, false) ==
           BOOTSTRAP_ABORT_PROTOCOL);

    memset(wire, 'x', sizeof(wire));
    wire[0] = 0;
    wire[1] = 96;
    state = begun();
    assert(bootstrap_abort_observe(&state, 11, wire, 97, false, false, false) ==
           BOOTSTRAP_ABORT_ACTIVE);
    assert(state.partial_len == BOOTSTRAP_ABORT_MAX_PARTIAL);
    assert(bootstrap_abort_observe(&state, 12, wire + 97, 1, false, false,
                                   false) == BOOTSTRAP_ABORT_PROTOCOL);
    state = begun();
    assert(bootstrap_abort_observe(&state, 11, wire, 98, false, false, false) ==
           BOOTSTRAP_ABORT_PROTOCOL);
    state = begun();
    assert(bootstrap_abort_observe(&state, 11, wire, 197, false, false, false) ==
           BOOTSTRAP_ABORT_PROTOCOL);
    assert(state.total_bytes == 0);

    first = frame(wire, 1, "advance");
    memset(partial, 'x', sizeof(partial));
    partial[0] = 0;
    partial[1] = 96;
    state = begun();
    assert(bootstrap_abort_observe(&state, 11, wire, first, false, false,
                                   false) == BOOTSTRAP_ABORT_ACTIVE);
    assert(bootstrap_abort_observe(&state, 12, partial, sizeof(partial), false,
                                   false, false) == BOOTSTRAP_ABORT_ACTIVE);
    assert(state.total_bytes == 153);
    assert(bootstrap_abort_observe(&state, 13, partial + 2, 43, false, false,
                                   false) == BOOTSTRAP_ABORT_PROTOCOL);
    assert(state.total_bytes == BOOTSTRAP_ABORT_MAX_TOTAL);
    state = begun();
    assert(bootstrap_abort_observe(&state, 11, wire, first, false, false,
                                   false) == BOOTSTRAP_ABORT_ACTIVE);
    assert(bootstrap_abort_observe(&state, 12, partial, sizeof(partial), false,
                                   false, false) == BOOTSTRAP_ABORT_ACTIVE);
    assert(bootstrap_abort_observe(&state, 13, partial + 2, 44, false, false,
                                   false) == BOOTSTRAP_ABORT_PROTOCOL);
    assert(state.total_bytes == 153);

    first = frame(wire, 1, "advance");
    total = first + frame(wire + first, 2, "complete");
    wire[total] = 0;
    state = begun();
    assert(bootstrap_abort_observe(&state, 11, wire, total + 1, false, false,
                                   false) == BOOTSTRAP_ABORT_PROTOCOL);
}

static void test_empty_notifications_and_terminal_stickiness(void) {
    uint8_t wire[128];
    const size_t first = frame(wire, 1, "advance");
    const size_t total = first + frame(wire + first, 2, "complete");
    BootstrapAbort states[5];
    size_t index;

    states[0] = begun();
    bootstrap_abort_observe(&states[0], 11, NULL, 0, true, false, false);
    states[1] = begun();
    bootstrap_abort_observe(&states[1], 11, (const uint8_t *)"\0\0", 2,
                            false, false, false);
    states[2] = begun();
    bootstrap_abort_observe(&states[2], 2000000010LL, NULL, 0, false, false,
                            false);
    states[3] = begun();
    bootstrap_abort_observe(&states[3], 11, NULL, 0, false, false, true);
    states[4] = begun();
    bootstrap_abort_observe(&states[4], 11, wire, total, false, false, false);
    assert(states[0].exit_code == 70 && states[1].exit_code == 71 &&
           states[2].exit_code == 72 && states[3].exit_code == 73 &&
           states[4].exit_code == 0);

    for (index = 0; index < 5; ++index) {
        const int terminal = states[index].exit_code;
        assert(bootstrap_abort_observe(&states[index], -1, NULL, 1, true, true,
                                       true) == terminal);
        assert(states[index].exit_code == terminal);
    }

    {
        BootstrapAbort state = begun();
        assert(bootstrap_abort_observe(&state, 11, NULL, 0, false, false,
                                       false) == BOOTSTRAP_ABORT_ACTIVE);
        assert(bootstrap_abort_observe(&state, 12, NULL, 0, false, false,
                                       false) == BOOTSTRAP_ABORT_ACTIVE);
        assert(bootstrap_abort_observe(&state, 13, wire, first, false, false,
                                       false) == BOOTSTRAP_ABORT_ACTIVE);
    }
}

int main(void) {
    test_nonce_and_clock_boundaries();
    test_frames_chunks_and_splits();
    test_eof_timeout_and_io();
    test_malformed_and_fixed_limits();
    test_empty_notifications_and_terminal_stickiness();
    return 0;
}
