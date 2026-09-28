# SDK and example boundary check implementation plan

> **For agentic workers:** Use test-driven-development and verification-before-completion. This implements the source boundary check already specified in C6/C12; the user authorized continued execution. No additional product policy or native permission is introduced.

**Goal:** Reject private host dependencies/imports in the public SDK and independent source examples.

**Architecture:** Evaluate the existing trusted manifests with SwiftPM into a structured target graph. Parse actual Swift source with the matching installed SwiftParser/SwiftSyntax toolchain, including conditional branches, rather than treating comments and string literals as imports. The selected SwiftPM describe command supplies the exact compiled source lists. A small Python driver checks the evaluated graph, source containment and discovered imports; a shell entry point builds the scanner into a temporary directory and cleans its own files.

**Tech Stack:** Python3 standard library, zsh, installed Xcode Swift compiler and its bundled SwiftParser/SwiftSyntax libraries; no package or production dependency added.

**Spec:** C6/C12 in [the approved completion plan](2026-09-10-addon-runtime-completion.md), existing CascadeKit/Package.swift and both example manifests. Public SDK target closure is explicitly CascadeAddonSDK, CascadeContracts and CascadePresentation. Runtime, CascadeKit, tool and host test targets are not part of that closure.

## Scope and ownership

Four new files only: scripts/check-addon-boundaries.sh, scripts/check_addon_boundaries.py, scripts/check-addon-imports.swift and scripts/tests/test_addon_boundaries.py. Root develops them in `/private/tmp/cascade-boundary-check-20260918/delivery/`, with private caches and evidence. Do not import into live scripts or touch source/cache owned by the subscription worker until its ownership handoff permits it. Root owns this tool's docs/tracker and later independent review.

The test repository is copied from the immutable delivered subscription-contract snapshot plus unchanged examples. Its result is labeled a baseline check, never a check of the concurrently edited live SDK. Final live validation occurs after integration.

## Rules

- SDK public products must resolve to their expected regular targets, whose dependencies remain in the explicit public closure. Do not infer public safety from every library product: CascadeRuntime is exported for host use but is not an addon SDK dependency.
- Example targets may depend on their own regular/executable/test targets and the three public SDK products from the one explicit local SDK package. Validate that package path against the selected SDK directory. Reject other host products, unknown dependencies and escaping target/source paths. The existing explicit CASCADE_SDK_PATH development dependency remains supported.
- Reject unsafe build flags, binary/macro/plugin target dependencies and plugin code generation in the audited closure. This preserves the existing source-only profile; it does not redesign package distribution.
- Source imports of the Xcode host module Cascade and private package targets are forbidden. Public SDK imports through @testable or @_spi are forbidden in SDK/example code; tests may use @testable for their own example targets. Foundation/SwiftUI and other system imports are not host-module violations.
- Use actual declared Swift sources from the selected toolchain’s SwiftPM describe output, validating target paths and contained symlinks; SwiftPM owns source/exclude/resource selection. Fail with useful diagnostics if files or manifest fields needed for the check cannot be understood; never silently pass malformed input or parser errors.
- This bounded profile accepts only Package.swift; reject version-specific Package@swift manifests explicitly before evaluation and if added during the audit. Hash/recheck all selected base manifests and parsed source files.
- Evaluate trusted project manifests only; this development tool is not a sandbox for arbitrary Package.swift. Record the selected toolchain/environment scope. It checks static imports/graph for that evaluation, not alternate environment-generated manifests, macro expansions, dynamic loading, runtime isolation or native SDK parity.

## Finite verification

- [x] Preserve baseline manifest/source hashes and start with a meaningful failing graph-policy test.
- [x] Add graph cases for direct/transitive private dependencies, forged SDK product/package path, unsafe settings/plugins, missing/duplicate targets and target source escapes; implement the minimal checked graph reader.
- [x] Compile an initial scanner and demonstrate a behavioral failing import case; implement syntax traversal, preserving attributes, module identity and file/line diagnostics.
- [x] Test plain/typed/attributed/conditional imports, nested comments, multiline/raw strings, escaped identifiers, malformed Swift and missing files. Exercise the actual compiled parser, not mocked import lists alone.
- [x] Test allowed example-local @testable and forbidden public-SDK @testable/_spi; verify comment/string text creates no false violation.
- [x] Run the real command on the immutable delivered package/examples snapshot with isolated caches; preserve all failures, command arrays, toolchain versions and exact file hashes.
- [x] Obtain independent source/spec review, import exactly four files, run final live check once permitted, update testing documentation and record delivery without claiming C6/C12/native completion.

No Git mutation, no existing source/Package changes, no C0d or app lifecycle operations inside the checker. It may compile its own scanner and evaluate manifests; it never launches an addon, builds the application, rewrites application links or controls unrelated processes.
