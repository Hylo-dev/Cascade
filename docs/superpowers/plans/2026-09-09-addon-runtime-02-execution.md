# Addon Execution and Resource Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eseguire addon nativi su domanda mantenendo contenuti durevoli, servizi condivisi e controllo verificabile delle risorse.

**Architecture:** Runtime actor separato dalla UI, canali asincroni autenticati e processi controllati dal launcher provato in P0. Scheduler e broker possiedono richieste, lease, piani temporali e quote; il provider non possiede il ciclo di vita del notch.

**Tech Stack:** Foundation/XPC, ExtensionFoundation dietro adapter di disponibilità, Swift Concurrency/Dispatch, sandbox e strumenti di processo Apple.

**Spec:** [specifica](../specs/2026-09-09-addon-runtime-design.md), [piano principale](2026-09-09-addon-runtime.md); prerequisiti P0 per il launcher e P1 per i valori.

## Global Constraints

- macOS 14 come minimo dell'app. Non si alza implicitamente il deployment target.
- Stesso SDK, isolamento, concessioni e budget per addon del team ed esterni.
- Cascade deve essere aperta; nessun processo figlio orfano accettato come successo.
- La pubblicazione è posseduta dall'host e non coincide con la connessione o una lease di lavoro.
- Nessun proxy sincrono, attesa di processo o decodifica non limitata sul MainActor.
- Quote applicative vincolanti; CPU/RAM native sorvegliate con intervallo di rilevamento esplicito.

## Task 02.1 — Canale autenticato e avvio su domanda

**Files:** creare Sources/CascadeTransport/AddonConnection.swift, WireEnvelope.swift, PeerVerifier.swift, XPCAddonConnection.swift; Sources/CascadeRuntime/Processes/AddonProcessLaunching.swift, NativeAddonLauncher.swift, ProcessIdentity.swift, AddonProcessPool.swift; Sources/CascadeAddonSDK/AddonProviderEntrypoint.swift; Tests/CascadeRuntimeIntegrationTests/ProcessConnectionTests.swift, Fixtures/ProbeAddon/ sotto CascadeKit. Aggiornare Package.swift e progetto Xcode solo dove occorrono bundle eseguibili firmati.

**Interfaces:** usare AddonManifest, AddonEvent, ProviderOutput e ConnectionGeneration di P1. Aggiungere ProcessIdentity (PID, istante/identificatore di nascita verificato, editore, bundle ID, digest) e RunningAddon (identità, generazione, connessione). API:

```swift
protocol AddonProcessLaunching: Sendable {
    func start(_ addon: InstalledAddon) async throws -> RunningAddon
    func stop(_ running: RunningAddon, reason: StopReason) async throws
}
protocol AddonConnection: Sendable {
    func send(_ event: AddonEvent) async throws -> ProviderOutput
    func close() async
}
```

Il pool mantiene al massimo un provider nativo per addon attivo; non crea un processo per istanza UI. "Pool" indica riuso controllato dei processi, non caricamento di addon di editori diversi nello stesso processo. L'identità viene rivalidata prima di operazioni sul processo; un PID da solo non è un handle sufficiente.

- [ ] Scrivere ProcessConnectionTests che avviano una fixture reale e verificano major compatibile, peer autorizzato, generazione nuova a ogni avvio e rifiuto di un messaggio della generazione precedente. Riprodurre anche un provider che invia un envelope con owner diverso.
- [ ] Implementare handshake: peer verificato → manifest/digest corrispondenti → versione negoziata → concessioni assegnate → messaggi ammessi. Verificare il caso di firma valida ma editore non autorizzato e quello di binario modificato dopo la verifica iniziale.
- [ ] Usare il launcher scelto in P0 senza introdurre un secondo meccanismo non provato. Il processo addon ha configurazione sandbox verificata, nessun listener non autenticato di rete e nessuna possibilità dichiarata di creare sottoprocessi non gestiti; questa restrizione deve corrispondere a una verifica reale del profilo.
- [ ] Applicare i limiti P1 prima del parsing applicativo profondo: envelope totale 512 KiB, documenti 64 KiB e piani temporali 256 KiB, oltre ai massimi per campo/numero. Coda di stato: un elemento pendente per istanza; ack e crediti per ulteriori invii. Messaggi di comando usano una coda distinta, senza scarto silenzioso. Un peer che ignora i crediti viene disconnesso e fermato, misurando anche allocazioni preliminari del trasporto.
- [ ] Implementare stop e rilevamento uscita effettiva. Provare host exit, host crash, provider spin e identity mismatch con il harness P0 adattato ai bundle produttivi. Non accettare "connection invalidated" come prova di assenza del processo.
- [ ] Eseguire ProcessConnectionTests e creare scripts/test-addon-runtime.sh per le fixture firmate; registrare risultati e commit. Uno script deve rifiutarsi di colpire processi che non appartengono alle proprie fixture.

## Task 02.2 — Scheduler, azioni e pubblicazioni indipendenti dal processo

**Files:** creare Sources/CascadeRuntime/AddonRuntime.swift, Scheduling/AddonScheduler.swift, Scheduling/DeadlineQueue.swift, Actions/ActionDispatcher.swift, Actions/ActionJournal.swift; Tests/CascadeRuntimeTests/AddonSchedulerTests.swift, ActionDispatcherTests.swift, PublicationLifecycleTests.swift; Tests/CascadeRuntimeIntegrationTests/ProviderExitTests.swift sotto CascadeKit.

**Interfaces:** `AddonRuntime.dispatch(_ request: ActionRequest) async -> ActionOutcome`; `refresh(_ id: PublicationID) async throws`; `disable(_ id: AddonID) async`; `stop() async`. Dipendenze in init: PublicationStore, AddonProcessLaunching, ResolutionPlanner tramite snapshot Resolution, ServiceBroker di 02.3 e clock iniettabile. Nei test si usa un FakeClock definito nel file TestClock.swift, con `now: Date` e `advance(by: TimeInterval)`; produzione distingue Date persistente e ContinuousClock per durate.

- [ ] Scrivere il test centrale con provider finto soltanto nel target test:

```text
given a timer publication expiring in 60 seconds
when its provider completes and exits normally
then the publication remains and no process is required
when an authorized pause action arrives
then exactly one provider starts, a new generation is used, and the result revises the same publication
when a reply from the old generation arrives
then it changes nothing
```

Ripetere la sequenza con una fixture di processo reale in ProviderExitTests. Il test unitario da solo non dimostra il requisito del processo assente.

- [ ] Implementare stati separati per processo, job e pubblicazione. Il lavoro termina con output limitato; la pubblicazione non trattiene istanze del provider. Uscita prevista conserva stato/azioni valide; crash marca obsolete le informazioni secondo la policy; disable revoca azioni e rimuove contenuti/piani anche futuri.
- [ ] Implementare una sola coda di deadline, riarmata sul minimo cambiato; niente timer per addon e niente heartbeat di rinnovo. Alla riattivazione/sleep-wake rivalutare eventi scaduti, eliminare avvisi superati e non riavviare sessioni finite. Orario civile persistente e clock monotono devono avere test separati di salto dell'orologio.
- [ ] Ammettere un job pesante per addon e due globali iniziali; azioni utente precedono refresh discrezionali, con coda e attesa massima limitate per evitare starvation. Pianificare la breve finestra di riuso con la stessa coda centrale e la policy misurata in P0; zero processi residenti senza domanda fuori dalla finestra. Non congelare i processi per simulare turni CPU.
- [ ] Separare ack, completed e outcomeUnknown. ActionJournal conserva almeno ID richiesta e stato entro limiti espliciti (128 richieste/10 minuti per addon iniziali), contando la memoria. Comando non idempotente con connessione persa dopo l'invio: outcomeUnknown, nessun retry automatico. Comando ripetibile: retry solo nella finestra dichiarata e con lo stesso ID. Il caso timeout deve revocare il risultato tardivo, senza fingere che l'effetto esterno sia stato annullato.
- [ ] Provare code piene, 100 revisioni accorpate, quattro comandi pendenti, deadline scaduta prima dell'avvio, due azioni concorrenti sulla stessa revisione, stop durante checkpoint e nessuna riattivazione al disable. Per endActivity la rimozione resta immediata anche a vista aperta.
- [ ] Eseguire AddonSchedulerTests, ActionDispatcherTests, PublicationLifecycleTests e ProviderExitTests; aggiornare docs/addons/lifecycle.md con garanzie di consegna e persistenza; commit.

## Task 02.3 — Lease, broker e dipendenze vive

**Files:** creare Sources/CascadeRuntime/Services/ServiceBroker.swift, ServiceRegistry.swift, ServiceBindingStore.swift, LeaseStore.swift, PermissionStore.swift; Sources/CascadeAddonSDK/Services/AddonServiceClient.swift, Storage/AddonStorageClient.swift; Tests/CascadeRuntimeTests/ServiceBrokerTests.swift, PermissionRevocationTests.swift sotto CascadeKit.

**Interfaces:** `ServiceBroker.acquire(requirementID: String, consumer: AddonID, scope: ServiceScope) async throws -> Lease`; `release(_ leaseID: UUID, consumer: AddonID) async`; `call(_ request: ServiceRequest) async throws -> ServiceResponse`. ServiceScope enum per ownStorage, selectedFiles, networkHosts e namedService; ServiceRequest contiene leaseID, consumer autenticato dall'envelope, operationID e input limitato. Non accettare identità del consumer direttamente dal payload.

- [ ] Scrivere ServiceBrokerTests con un servizio CountingSource definito nel target test: conta start/stop e consegna eventi tramite AsyncStream con bufferingNewest(1). Due acquisizioni compatibili devono chiamare start una volta; il primo rilascio non ferma la fonte, il secondo sì.
- [ ] Implementare chiave di condivisione comprendente versione, account, scope e vincoli di riservatezza. Due account o grant incompatibili non condividono cache/dati. Il costo del servizio conta una sola volta nel totale, mentre il lavoro richiesto rimane attribuibile ai consumatori.
- [ ] Separare la sottoscrizione di interesse conservata dall'host dal token di accesso della connessione. L'interesse ha owner, feature/sessione, grant, scadenza e quota; può sopravvivere all'uscita normale del provider e risvegliarlo su un evento ammesso. Alla nuova connessione si crea un token nuovo, senza riusare lease di generazioni precedenti. Disable, scadenza e revoca rimuovono entrambi. Provare evento con provider assente e nessuna sorgente dopo la revoca dell'ultimo interesse.
- [ ] Instradare una chiamata a servizio di terzi come ServiceInvocation e correlare InvocationCompletion.service al ServiceResponse del client. Eventi conservano soltanto l'ultimo stato utile per sottoscrizione; comandi mantengono esiti e deadline espliciti. Quando A attende B, il broker non deve trattenere permessi di esecuzione che impediscono a B di partire: trasferire l'ammissione di lavoro durante l'attesa, mantenendo memoria/processi contabilizzati, oppure rifiutare prima con resourceDenied. Provare A→B→C e una catena oltre la capacità di processi: nessuno stallo o crescita senza limiti.
- [ ] Applicare la risoluzione di P1 a cambi reali di installazione, abilitazione, app running e permessi. Rivalutare la chiusura inversa dei dipendenti, senza polling. Un servizio perso blocca soltanto le feature dipendenti; nessuna selezione di un altro provider a metà sessione senza nuovo binding autorizzato.
- [ ] Implementare lease revocabili per proprietario, scope, generazione e deadline. Un provider o consumer disabilitato perde gli handle; un'altra feature senza quella dipendenza continua. Rifiutare prestito di permessi, handle usato da altro addon e accesso a dati dopo revoca anche se l'azione era già in coda.
- [ ] Eseguire ServiceBrokerTests e PermissionRevocationTests; aggiungere integrazione con due fixture addon firmate quando disponibile. Il broker non deve offrire shell, proxy generico di NSWorkspace o API private del motore. Documentare servizi pubblici e scope in docs/addons/services.md; commit.

## Task 02.4 — Quote, supervisione e quarantena

**Files:** creare Sources/CascadeRuntime/Resources/ResourcePolicy.swift, ResourceGovernor.swift, ProcessMetricsReader.swift, AddonHealthStore.swift; Tests/CascadeRuntimeTests/ResourceGovernorTests.swift, QuarantineTests.swift; Tests/CascadeRuntimeIntegrationTests/ResourceAbuseTests.swift sotto CascadeKit; creare scripts/test-addon-resources.sh.

**Interfaces:** ResourcePolicy è configurazione host versionata; `ResourceGovernor.admit(_ request: ResourceRequest, owner: AddonID) throws -> Reservation`, `release(_ reservationID: UUID)`, `observe(_ metrics: ProcessMetrics, identity: ProcessIdentity) -> GovernorDecision`. ResourceRequest enum publication, asset, job, command, storage; Reservation contiene ID, owner e importo. ProcessMetrics contiene CPU user+system delta, footprint, timestamp e identità; GovernorDecision enum keep, reduce, stop, quarantine.

- [ ] Scrivere ResourceGovernorTests con la stessa richiesta e identico budget per origine bundled ed external: stesso risultato. Verificare 4 attività/addon e 16 globali, avvisi 8, 16 istanze/addon, limiti messaggi, stato 8 MiB globale, immagini 8 MiB/addon e 32 globali, tre provider al massimo e ammissione memoria globale 256 MiB. Le quote sono massimi simultanei, non somme riservate per installazione.
- [ ] Implementare prenotazione prima dell'allocazione/lavoro controllato dall'host e rilascio su errore, timeout e cancellazione. CPU e footprint del codice nativo vengono invece osservati con l'adapter verificato in P0; nessuna promessa di limite RAM istantaneo o metrica simulata se l'OS nega la lettura.
- [ ] Un solo supervisore campiona processi attivi, inizialmente al massimo 1 Hz, e si disarma senza processi. Conteggiare il suo costo. Applicare i candidati della specifica: event-driven credito condiviso addon100ms con ricarica5ms CPU/s, conservato fra job e riavvii provider; footprint provider obiettivo 64 MiB/soglia osservata 96; scena remota totale addon obiettivo 128/soglia 192. Profilo audio/UI continua non eredita questi numeri: deve passare 04.3 prima dell'abilitazione pubblica.
- [ ] Per tre violazioni moderate in cinque minuti mettere in quarantena la versione. Per soglia di arresto/flooding fermare subito il processo tramite launcher; registrare tempo di rilevamento e uscita. Retry per crash a 1/5/30 s solo con domanda ancora valida, poi quarantena; usare DeadlineQueue, non timer aggiuntivi per addon.
- [ ] Provare loop CPU, espansione memoria limitata dal harness, allagamento IPC, quote aggirate con molte sessioni, servizio condiviso usato per scaricare costo e metrica assente. Il harness interrompe i soli processi test e ha deadline globale; nessun test deve poter esaurire deliberatamente la macchina.
- [ ] Eseguire ResourceGovernorTests, QuarantineTests e `/bin/zsh scripts/test-addon-resources.sh`. Salvare latenza di arresto/overshoot e costi del supervisore, oltre al semplice pass/fail; commit.

## Task 02.5 — Asset, checkpoint e persistenza limitata

**Files:** creare Sources/CascadeRuntime/Storage/AddonStateStore.swift, StateMigration.swift, AssetStore.swift, AssetDecoder.swift; Tests/CascadeRuntimeTests/AddonStateStoreTests.swift, AssetStoreTests.swift, StateMigrationTests.swift sotto CascadeKit. Modificare AddonStorageClient e il bridge di 01.4 per consumare handle autorizzati.

**Interfaces:** `AddonStateStore.read(owner: AddonID) async throws -> Data?`; `write(_ data: Data, schemaVersion: Int, owner: AddonID) async throws`; `AssetStore.importAsset(_ data: Data, owner: AddonID) async throws -> AssetHandle`; AssetHandle contiene ID, owner, dimensioni e revisione dell'asset, mai un percorso arbitrario. La revisione dell'asset non è ConnectionGeneration: i riferimenti dell'host sopravvivono all'uscita prevista del provider; soltanto i token con cui il provider li usa sono legati alla connessione. Migrazione riceve copia dello stato precedente e produce un nuovo file validato prima della sostituzione atomica.

- [ ] Scrivere test che interrompono una scrittura fra staging e commit: il vecchio stato deve rimanere leggibile. Verificare quote disco 10 MiB stato e 20 MiB cache/addon, 100 MiB globali iniziali; cancellazione cache separata dalla rimozione dei dati dell'utente.
- [ ] Implementare directory separate per owner verificato, rifiuto di path traversal/symlink di ingresso e nessun accesso ai dati dell'app sorgente per convenzione. Scrivere su eventi significativi, non per frame o ogni secondo. Checkpoint limitato nel tempo; stop non aspetta per sempre un provider.
- [ ] Decodificare immagini fuori dal MainActor con concorrenza limitata, massimo 1 MiB compresso e 1 megapixel; rifiutare metadati/immagini malformati e contabilizzare il buffer decodificato prima di pubblicarlo. Se P0/analisi decoder richiede isolamento del decoder, usare worker nativo controllato, non una nuova pipeline non supervisionata.
- [ ] Conservare gli asset referenziati da pubblicazioni valide dopo l'uscita normale del provider; rilasciarli quando sparisce l'ultima referenza. Revoca owner impedisce uso degli handle residui. La cache di uno stesso asset non si condivide fra scope privati incompatibili.
- [ ] Provare ripartenza con pubblicazione ancora valida, scaduta, file corrotto e schema futuro. Non riprodurre comandi o avvisi dalla persistenza; non rinnovare automaticamente la durata massima di un'attività.
- [ ] Eseguire AddonStateStoreTests, AssetStoreTests e StateMigrationTests; eseguire tutte le suite P2 e registrare rapporto P2 con build/riavvio se l'app è stata toccata; commit.
