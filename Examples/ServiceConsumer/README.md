# Public ServiceConsumer source example

This Swift 6 source package contains three library products: a shared example
contract, a synthetic service provider and a consumer provider. The synthetic
provider always returns **3** completed sessions. It reads no real session history
and is not a service exported by StandaloneFocus. Neither manifest installs an
addon or provides a runnable entry point, signed container or host bootstrap.

Copy this directory to a separate development directory. Set `CASCADE_SDK_PATH`
to an absolute path to a compatible public SDK source package, then run:

```sh
export CASCADE_SDK_PATH="/absolute/path/to/public-sdk"
swift test --package-path /absolute/path/to/ServiceConsumer --no-parallel
swift build --package-path /absolute/path/to/ServiceConsumer
cascade-addon validate /absolute/path/to/ServiceConsumer/Manifests/Consumer.json
cascade-addon validate /absolute/path/to/ServiceConsumer/Manifests/Provider.json
```

Use a Swift 6.2 or newer toolchain on macOS 14 or newer. There is no implicit
repository fallback or remote SDK release dependency. Direct SDK dependencies
select only `CascadeAddonSDK` and `CascadeContracts`; the SDK also reaches its
public presentation target. The consumer does not depend on the provider
implementation.

The example service is `com.example.focus.sessions`, version `1.0.0`, operation
`read`. Its request is exactly empty bytes. Its response has exactly the literal
JSON keys `schemaVersion` (integer 1) and `completedSessions` (integer 0...1000),
in either order, within 256 UTF-8 bytes. The small codec accepts JSON whitespace
and plain integer tokens; escaped key spellings, duplicate keys, fractions and
exponents are unsupported. The fixed response is
`{"schemaVersion":1,"completedSessions":3}`.

Supply an authenticated owner and the **exact host-assigned** publication ID when
constructing `ServiceConsumerProvider`. Revisions start at zero in memory and
advance only after a valid output is constructed. Each new provider object needs
a fresh assignment with no host revision history. This is not reconnect, restore
or recovery support; the example stores no checkpoint or result cache.

On refresh, the consumer selects exactly one supplied grant matching owner,
service, summary/read scope, generation and finite unexpired civil expiry. It
rejects ambiguity. No usable grant returns exactly one scoped `requestService`
operation without invoking. This is a defensive path: root `REQUIRES` normally
prevents admission when the provider is absent or incompatible. The example does
not acquire grants, resolve versions, poll, subscribe or redispatch itself.
Grant delivery and the next dispatch require the host adapter.

A granted refresh invokes once with a new request ID and a positive deadline
bounded by two seconds and supplied expiry. Structured client failures propagate
without retry, including uncertain outcomes. Successful responses must match the
contract and operation and pass the bounded codec. The consumer publishes a
public widget labeled “Example completed sessions: 3” with a finite 30-second
expiry and remove stale policy; its output has no invocation completion. Outbound
request correlation belongs to the service client/transport.

One refresh remains busy across suspension. Stop is accepted while an invocation
is suspended and permanently invalidates this object's response authority.
Cancellation and accepted stop discard late results. A civil-clock check after
await rejects obviously expired responses. The injected civil clock does not
replace host monotonic deadlines or prove canonical grant validity.

The host must resolve the declared `>=1.0.0 <2.0.0` requirement, authenticate the
consumer session, enforce cross-publisher consent, bind canonical grants to the
selected provider/version/digest/privacy partition, recheck authority at dispatch
and completion, enforce monotonic deadlines and reject late or revoked results.
A snapshot grant contains no provider version or identity and cannot establish
these facts. The public protocol alone gives no timeout guarantee.

Tests use public APIs and in-process wiring to the actual synthetic provider.
Recording clients and scripted failures test consumer behavior under supplied
outcomes. They do not establish authentication, canonical revocation, OS policy,
real absent/disabled/incompatible/cyclic provider resolution, native transport,
installation, signature, resource-policy parity or lifecycle qualification.
No actions, storage, subscriptions, background work or process control are used.
The public native gate C0d is unchanged; this remains partial C12 source evidence.

A separate [source verification of these exact manifests with the real host resolver](../../docs/superpowers/verification/2026-09-18-service-consumer-manifest-resolution.md)
now covers compatible/absent/disabled/incompatible providers, a derived cycle and
cross-publisher consent removal with prior bindings. Its archived harness does not
add private imports to this package. This is policy resolution of synthetic host
inputs, not authentication, active IPC revocation or native addon qualification.
The public package tests above retain their narrower consumer/provider boundary.
