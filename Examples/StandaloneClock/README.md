# StandaloneClock public source example

`StandaloneClockProvider` is a source-only Swift 6.2 library for macOS 15. It uses only the public `CascadeAddonSDK` and `CascadeContracts` products and publishes a declarative `clock(format: .hourMinute)` widget from an exact host-assigned `PublicationID`. The host supplies the authenticated owner and, when recreating the provider, its previously accepted revision.

Set `CASCADE_SDK_PATH` to an absolute public SDK package path, then build or test an independent copy:

```sh
export CASCADE_SDK_PATH=/absolute/path/to/PublicCascadeSDK
swift test --package-path /absolute/path/to/StandaloneClock --scratch-path /private/tmp/standalone-clock-build --no-parallel
```

Each refresh publishes content that expires after 24 hours; the example does not schedule its own renewal. After recreation, the caller must provide the last accepted revision for the same assignment (or issue a genuinely new assignment).

The provider has no timer, background task, storage, network, assets, services, executable, launcher, signing, or installation flow. The host renders and updates the clock while admitted content is mounted. This example does not replace `ClockWidget` and does not qualify native provider exit, lifecycle behavior, or visual parity.
