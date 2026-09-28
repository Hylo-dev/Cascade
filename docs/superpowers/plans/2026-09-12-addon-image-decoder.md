# Addon image decoder — C5 continuation

This bounded increment implements the decoder requirement in the approved
[completion plan](2026-09-10-addon-runtime-completion.md#c5-on-disk-state-and-assets-with-a-lifetime-independent-of-the-process).
The user requested continuation on 12 September, with existing libraries preferred
and a stop before 60% of the weekly Codex allowance is consumed.

## Design

Use Apple's ImageIO to inspect and decode compressed images, and CoreGraphics to
normalize pixels. Do not implement image codecs, container parsers, or a second
raster lifetime manager. `AssetDisposalCoordinator` remains responsible for the
actual lifetime of returned images; the canonical `ResourceGovernor` admits both
temporary work and retained pixels.

The initial internal host service accepts complete PNG/JPEG data up to 1 MiB,
single-frame images up to one megapixel, with a narrow supported pixel/metadata
profile. It returns the existing immutable premultiplied RGBA8 sRGB backing.
One admitted operation runs outside MainActor; competing operations fail as busy
before reaching the worker queue. Closure and cancellation invalidate pending
return authority and cannot refund buffers that remain alive.

Reserve temporary decode capacity before ImageIO parses the source. A protected
reservation must survive bulk owner cleanup while work is in flight. Temporary
admission is an allowance for controlled buffers and framework work, not proof of
a hard bound on ImageIO's private allocations or CPU time.

This is an internal codec boundary. It does not authenticate an addon, expose SDK
imports, bind assets to publications, or enable the native launcher. `AssetState`,
transport assembly, renderer lookup, and hostile-process qualification remain
separate work.

## Execution and checks

- [x] Add native-image fixtures and observe behavioral failures before implementation.
- [x] Implement bounded decode using ImageIO/CoreGraphics and shared accounting.
- [x] Verify malformed/oversized/unsupported input, normalization, quota denial,
  busy/close/cancel behavior, bulk cleanup, and the last real image reference.
- [x] Review the increment independently; resolve actionable findings.
- [x] Run the full package serially, build the signed app, update the Applications
  link, restart Cascade and verify its executable and new process.
- [x] Record actual evidence and remaining boundaries without marking all C5 complete.

The current checkout contains extensive prior uncommitted work. Preserve it, use
an external copy for app build isolation, compare build inputs, and do not stage
or commit unrelated files. No native addon tracing tests are part of this task.

## Implementation rulings

ImageIO proved tolerant of missing PNG/JPEG terminal bytes, even with eager decoding.
A fixed signature/terminal-marker preflight is therefore part of the adapter. It
is not a custom codec, CRC checker, or chunk parser; matching terminal bytes do not
prove the absence of earlier trailing data. Native status is checked after drawing
to catch deferred scan failures, including a truncated JPEG with a restored EOI.

The original five tests failed before implementation. The later concurrency/close
tests were written before implementation but first ran against working code;
subsequent temporary fault mutations established their failure sensitivity. The
extra row-orientation and exact-limit tests were added during review. These are
recorded separately rather than claiming an initial RED for every test.
