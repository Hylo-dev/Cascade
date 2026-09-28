# Cascade

A high-performance Dynamic Notch for macOS: an always-resident overlay that
hugs the MacBook's hardware notch and morphs into an expanded surface hosting
modular widgets. See [`PRODUCT.md`](PRODUCT.md) for what it does and
[`CLAUDE.md`](CLAUDE.md) / [`CODE_STYLE.md`](CODE_STYLE.md) for how it is built.

## Requirements

- macOS 14 (Sonoma) or newer to run.
- Xcode 26 or newer to build. Day-to-day development and verification happen on
  Xcode 27 beta; Xcode 26 is expected to work but is not regularly tested.

## Build and run

```sh
git clone <repo-url> Cascade
cd Cascade
open Cascade.xcworkspace
```

Pick the `Cascade` scheme and press Run. Nothing else is required: no Apple
account, no Homebrew, no generated files.

From the command line:

```sh
xcodebuild -workspace Cascade.xcworkspace -scheme Cascade -configuration Debug build
```

Launch the built app with `open` (or from Xcode), not by executing
`Cascade.app/Contents/MacOS/Cascade` directly. Started from a shell, macOS
attributes its Bluetooth and Automation requests to the shell and aborts the
process for a missing usage description.

Every successful scheme build points `/Applications/Cascade.app` at the build
it just produced (`scripts/update-application-link.sh`), so Launchpad and
Spotlight always open the latest build. A real app at that path is never
touched.

### Signing

A fresh clone signs ad hoc, which needs no account. macOS then forgets the
Accessibility and Automation grants after every rebuild and asks again. To keep
them, sign with your own team:

```sh
cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig
# then set DEVELOPMENT_TEAM in it
```

The file is gitignored; see [`Config/Signing.xcconfig`](Config/Signing.xcconfig).

### FFmpeg helpers (optional for development)

Debug builds do not need FFmpeg. Only an archive (Product ▸ Archive) embeds and
verifies the `ffmpeg` / `ffprobe` helpers, which must be built once with
`scripts/build-ffmpeg.sh`. See [`docs/third-party/ffmpeg.md`](docs/third-party/ffmpeg.md).

## Tests

```sh
cd CascadeKit && swift test --no-parallel
```

Run them serially. Several runtime tests simulate a slow synchronous read by
parking a cooperative-pool thread for seconds; in the default parallel mode
enough of those overlap to starve the pool, and unrelated tests time out. The
serial run is reliable and takes about 11 s.
