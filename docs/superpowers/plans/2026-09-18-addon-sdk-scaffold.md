# Public addon source scaffold — Implementation Plan

> **For agentic workers:** use superpowers:subagent-driven-development. User’s sustained Codex-only continuation authorizes this pending C12 increment. Preserve the dirty checkout; no commits/staging/reset. Review before delivery.

**Goal:** Make `cascade-addon init` generate a compilable public-SDK provider source package and validated manifest without overwriting developer files or pretending native bootstrap is available.

**Architecture:** Extend the existing tool command router; keep manifest validation intact. Generate a SwiftPM library target implementing AddonProvider, a simple refresh publication, and public-API tests. Accept developer-provided identity and explicit local SDK package dependency. Publish a fully prepared sibling staging directory using exclusive rename. Existing destinations, including empty directories/symlinks, are refused; this precise stronger no-overwrite policy avoids partial edits to caller-owned directories.

**Tech Stack:** existing Swift6/Foundation/Darwin, SwiftPM tools6.2, macOS14 declaration, SwiftTesting. No dependency or remote repository invented.

**Spec:** C12 / task04.2 of the approved completion/release plans, plus user’s request to continue all pending addon work. Source scaffolding can advance before native qualification; distributed packaging and executable entrypoint remain dependent on C0/C1.

## Scope and behavior

- CLI: `cascade-addon init --name <Name> --identifier <reverse.dns.id> --destination <new-directory> --sdk-path <CascadeKit-package>`; all flags exactly once, order-independent, no unknown/empty flags. Project name ASCII letter followed by alphanumerics, max64bytes; append `Addon` to the target and `Provider` to type name so language keywords do not become bare identifiers. Identifier validated by AddonID. Explicit SDK path must name a directory with a regular Package.swift; never evaluate it during init.
- Outputs: Package.swift, Manifest.json, Sources/<Name>Addon/<Name>Provider.swift, Tests/<Name>AddonTests/<Name>ProviderTests.swift, README.md, .gitignore. The source package links only public CascadeAddonSDK and CascadeContracts products. Generated tests exercise refresh publication, identity refusal and stop without importing Runtime or host internals. No test or build automatically executed by init.
- Provider: one bounded actor revision counter; refresh uses host-supplied publication identity, validates matching addon owner, emits a basic widget with finite expiry and schema1 content. Stop returns empty output. Unsupported events fail explicitly, no silent claimed action/service success. This is a development source example; reconnect/restoration/transport are not declared solved. Signing identity remains developer-assigned later, no certificates/entitlements fabricated.
- File safety: parent must exist; prepare under that parent with exclusive creation, no following output symlinks and no overwriting. Use descriptor-relative creation/rename where necessary to keep parent identity stable. Publish with macOS renameatx_np RENAME_EXCL. On failure clean only owned staging files/directories; never recursively delete a raced external destination.
- Swift and JSON literals must escape developer input, including SDK path quotes/backslashes/interpolation characters; no shell expansion/execution.
- Exit0 success/help,2 bad arguments,1 invalid inputs or filesystem failure. Clear bounded diagnostics, existing validate semantics preserved.

## Execution and evidence

- [x] Meaningful compiling RED: valid init currently fails, refusing to create the complete expected project; preserve malformed/sentinel destinations tests.
- [x] Implement narrow router, ScaffoldCommand/template/writer files and focused CLI tests. Cover valid manifest, content/identity fields, bad/duplicate/missing flags, existing file/empty/nonempty directory/symlink, quoted/Unicode/spaced SDK paths, no-shell marker, and staging cleanup on publication refusal.
- [x] Compile and run generated project tests outside checkout with an explicitly supplied local copy of public SDK sources. Confirm target dependencies/public imports and manifest validation. No OS launcher or runtime qualification implied.
- [x] Integrate only after unchanged-preimage check; record before/after hashes and cumulative delta. Independent review with scoped fixes, targeted/full SwiftPM verification on final sources.
- [x] Update SDK quickstart/README and Wayfinder progress, signed app build/link/restart; continue the next unblocked slice while Codex remains available.

## Filesystem assumption clarified during review

RENAME_EXCL prevents replacement of an existing destination entry. Descriptor-relative, nonrecursive cleanup checks recorded identities, but separate check/unlink and mkdir/open calls cannot provide isolation from arbitrary concurrent mutation by another process with the same user’s filesystem authority. Owned staging assumes no such adversary; no crash-durability or atomic unlink-by-inode guarantee is claimed.
