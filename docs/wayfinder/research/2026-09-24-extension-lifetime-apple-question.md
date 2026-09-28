# ExtensionFoundation lifetime: bozza di domanda per Apple

24 settembre 2026. **Bozza locale archiviata, non inviata e non destinata all'invio.**
L'utente ha chiarito: «Cerchiamo nella doc. non scrivero a apple per questo».
Il contatto con Apple non è un passo del lavoro: si prosegue con documentazione
pubblica, SDK e prove locali. Le domande sotto restano soltanto una lista storica
dei dubbi da verificare. Vedi la [nuova ricerca documentale](2026-09-24-extension-startup-documentation.md).

La bozza aggiornava la domanda precedente con
la composizione broker → estensione esterna ora eseguita. Non richiede un cambio
di policy né assume che esista una garanzia non documentata.

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

## Materiale locale disponibile

[Rapporto](../../superpowers/verification/2026-09-24-addon-global-recovery.md),
[fixture](../../../Prototypes/AddonPlatform/BrokerRecovery/README.md), manifest,
sorgenti firmati e osservazioni del kernel sono conservati nel repository.
Prima di condividere un pacchetto, selezionare soltanto i file necessari alla
riproduzione e rimuovere percorsi locali personali dai log destinati all'esterno.
