# ExtensionFoundation lifetime: draft question for Apple

24 September 2026. **Archived local draft, not sent and not intended to be sent.**
The user clarified: "Let's search the docs. I won't write to Apple about this."
Contacting Apple is not a step of the work: the work continues with public
documentation, the SDK and local probes. The questions below remain only a historical
list of doubts to verify. See the [new documentation research](2026-09-24-extension-startup-documentation.md).

The draft updated the previous question with
the broker → external extension composition, now run. It does not request a change
of policy nor assume that an undocumented guarantee exists.

## Draft

We are evaluating a macOS 14+ application with an embedded, sandboxed XPC broker
hosting an external app extension through ExtensionFoundation. The extension is
packaged inside a separate signed container app. Our requirement is that a managed
extension cannot remain orphaned after its host dies, including while startup is
still pending. We must also observe the old process's exit before restarting it.

On macOS 27 beta (26A5425a, arm64, SDK 27.0), a fixed signed fixture successfully
starts the external extension from the embedded broker using legacy identity
discovery. After authenticated XPC startup, the provider blocks a callback. Invalidating
and releasing the channel, bootstrap, listener and AppExtensionProcess does not produce an exit
within two seconds. Exiting the broker does: the root application remains responsive.
Normal root exit and SIGKILL of the root also terminate the broker and provider.
We observe registered process exit events, separately from cleanup timers. These
observations do not establish behavior before startup or on older OS versions.

Could you clarify the supported public contract for:

1. Host/broker death while `AppExtensionProcess(configuration:)` is awaiting startup,
   including a stall in dyld or an initializer: is cleanup guaranteed from process
   creation, and how can an application verify it without relying on private APIs?
2. Obtaining or correlating an incarnation-specific exit observation before that
   initializer returns, from an observer that survives host death and does not keep
   the provider alive by opening another connection.
3. Process reuse across hosts/brokers: what scope of exclusivity is supported, and
   how should selective per-addon recovery handle a provider shared by other clients?
4. Whether embedding the ExtensionFoundation host in an application-scoped XPC
   service is supported on macOS 14+, including external publishers and consent.
   In this fixture, the modern monitor reports `unapprovedCount=1` in the broker
   while legacy discovery can start the approved local test provider.

If these guarantees are unavailable, which supported architecture or API is
recommended? We do not equate connection invalidation or interruption callbacks
with independently verified process exit, and do not use PID-discovery-based kills.

## Available local material

The [report](../../superpowers/verification/2026-09-24-addon-global-recovery.md),
[fixture](../../../Prototypes/AddonPlatform/BrokerRecovery/README.md), manifest,
signed sources and kernel observations are kept in the repository.
Before sharing a package, select only the files needed for
reproduction and remove personal local paths from logs intended for outside parties.
