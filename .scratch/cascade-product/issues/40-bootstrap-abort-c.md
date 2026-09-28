# Implement the C bootstrap with a pre-tracing abort

ID: 40
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 39

## Question

Translate the finite protocol already verified in the offline model into a small trusted C bootstrap, without tracing or exec. Compile the candidate and verify the logic with a single C test; leave the future native test with supervisor/child separate and unrun.

## Scope

Resumption authorized on 19 September with Ponytail: two new files, libc, no dependency or new abstract model. Contract of the [offline model](39-bootstrap-abort-offline.md): exact advance/complete framing, bounded input, absolute 2 s deadline and codes 0/70/71/72/73. The candidate binary reads only its own stdin; no dynamic endpoint, addon loading, fork/spawn/exec, tracing, signal, process observation or signing/entitlement.

The local test compiles separately with the main/IO branch excluded and tests the real deterministic logic. The POSIX main is compiled but not run: no physical exit or launcher qualification is inferred. The C0d gate and all pre-existing drivers remain identical.

Sol medium implements the two files; the root reviews before accepting, runs the verifications and takes care of documentation/restart. Requested cap: 20% of the weekly Codex budget, with a dispatch stop at 15% and a precautionary work stop at 18% to keep a margin. Baseline measured at 0% in the current window; resets and samples are in the artifacts of 19 September. The deadline of the previous run at 00:00 is historical and does not apply to the new resumption.

## Answer

Source candidate completed by Sol medium and fixed/reviewed by the root: [BootstrapAbort.c](../../../Prototypes/AddonPlatform/Tracing/BootstrapAbort.c) and [single C check](../../../Prototypes/AddonPlatform/Tracing/BootstrapAbortTests.c). Strict C11 compilation and in-memory check with AddressSanitizer/UndefinedBehaviorSanitizer PASS. No new dependency; 14 pre-existing inputs of the diagnostics and 484 inputs of the app unchanged.

Root fixes: bounded nonce validation, immediate saving of errno, terminal POLLERR, preservation of the invalid initial state and the deadline rechecked after setup. [Review and evidence](../../codex-addon/20260919-ponytail/root-review.md), commands/logs/hashes in the same directory. The POSIX main is compiled but not run: physical stop, identity, dead supervisor, attach or launcher are not proven. The C0d check remains identical.

To reproduce only the in-memory check from the checkout:

```sh
check_dir=$(mktemp -d /private/tmp/cascade-bootstrap-check.XXXXXX)
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun clang -std=c11 -Wall -Wextra -Werror -pedantic -fsanitize=address,undefined Prototypes/AddonPlatform/Tracing/BootstrapAbortTests.c -o "$check_dir/check"
"$check_dir/check"
```

The Python model can receive bytes+EOF in the same batch; POSIX read returns them separately. The main therefore accepts the complete command as a normal exit 0 in the current read. No local result certifies the supervisor's death; the future native test remains separate.
