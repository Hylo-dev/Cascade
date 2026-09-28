# Addon Contracts and SwiftUI SDK Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rendere manifest, contenuti, dipendenze e API Swift indipendenti dall'esecuzione del provider, con limiti verificabili.

**Architecture:** Valori serializzabili in Contracts, composizione dichiarativa in Presentation e renderer SwiftUI condiviso. Il resolver e la conservazione dei contenuti sono logica dell'host separata dalla UI.

**Tech Stack:** Swift tools 6.2, Foundation, SwiftUI, Swift Testing; nessuna libreria esterna.

**Spec:** [specifica](../specs/2026-09-09-addon-runtime-design.md), [piano principale](2026-09-09-addon-runtime.md).

## Stato di esecuzione

Implementati i quattro blocchi P1; test automatici e revisioni completati per il codice implementato; 230 test del package passano con --no-parallel, come registrato nel [rapporto P1](../verification/2026-09-09-addon-runtime-P1.md). Rimangono da qualificare VoiceOver, impostazioni di accessibilità del sistema, comportamento energetico nel desktop e collegamento allo scheduler P2/P3. I test unitari e la preview non sono una prova della scena SwiftUI remota. Nessun commit del lavoro pregresso è incluso.

## Global Constraints

- macOS 14 come minimo dell'app. Non si alza implicitamente il deployment target.
- Stesso SDK e controlli per tutti i futuri widget del team e per addon esterni.
- Nessuna serializzazione automatica di AnyView o closure; nessuna dipendenza dai nomi dei widget concreti nel renderer.
- Nessun codice del provider nel MainActor o nel callback di animazione dell'host.
- Tutti i nuovi tipi wire sono Codable e Sendable con schema/versioni espliciti; i tipi del dominio non ereditano l'isolamento globale MainActor.

## Task 01.1 — Package, identità, schema e messaggi

**Files:** modificare CascadeKit/Package.swift; creare Sources/CascadeContracts/AddonIdentity.swift, AddonManifest.swift, AddonRequirement.swift, AddonPermission.swift, AddonResourceRequest.swift, Publication.swift, ProviderMessage.swift, AddonFailure.swift sotto CascadeKit; creare Tests/CascadeContractsTests/ManifestTests.swift, MessageTests.swift, FixtureData.swift, Fixtures/focus.json, Fixtures/requires-cycle-a.json, Fixtures/requires-cycle-b.json, Fixtures/incompatible.json.

**Interfaces:** definire tutti i valori della tabella "Vocabolario di interfaccia comune" del piano principale, mantenendo le forme JSON della specifica. API pure:

```swift
public struct AddonID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init?(rawValue: String)
}
public struct AddonManifest: Codable, Sendable {
    public static func decode(_ data: Data) throws -> AddonManifest
    public func validate() throws
}
public struct ProviderOutput: Codable, Sendable {
    public let publications: [Publication]
    public let operations: [OperationRequest]
    public let completion: InvocationCompletion?
    public let checkpoint: Data?
}
```

OperationRequest è un enum con casi requestService(requirementID, scope), schedule(deadline, eventID), releaseLease(leaseID), endPublication(PublicationID); identificatori come stringhe validate, scope come oggetto chiuso di campi consentiti, nessun dizionario di oggetti Foundation arbitrari. Publication include content oppure timeline, mai entrambe; date finite e revisioni UInt64 non riciclate nella stessa sessione. InvocationCompletion associa requestID a risultato di azione oppure risposta di servizio: pubblicare uno snapshot non prova il completamento del comando. AddonFailure contiene i casi espliciti della specifica e motivi leggibili.

- [x] Aggiungere target Contracts e relativi test al package con risorse di fixture processate, mantenendo il prodotto CascadeKit attuale. Limitare dipendenze del target a Foundation; aggiungere controlli di concorrenza sui nuovi target senza migrare globalmente il language mode.
- [x] Copiare focus.json dall'esempio della specifica e aggiungere un loader di fixture nel target test:

```swift
func fixtureData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
}

@Test func rejectsOversizedManifestBeforeDecode() {
    #expect(throws: (any Error).self) {
        try AddonManifest.decode(Data(repeating: 32, count: 65_537))
    }
}
```

- [x] Implementare limite manifest 64 KiB prima del JSONDecoder, rifiuto di major sconosciuta, ID invalidi, range SemVer malformati, risorse negative/NaN e capability sconosciute obbligatorie. Campi opzionali sconosciuti possono essere ignorati solo se non cambiano semantica di sicurezza; discriminanti sconosciuti vengono rifiutati.
- [x] Definire limiti distinti per contenuto ed envelope: 64 KiB per documento, 256 KiB per piano temporale, 512 KiB totali per envelope; massimo 16 pubblicazioni e 16 operazioni per risposta, input azione 4 KiB, checkpoint 64 KiB. Valgono sia i massimi dei campi sia quello totale. Gli asset usano trasferimento separato limitato, non aumentano questi massimi. Testare risultato di azione con requestID errato, risposta di servizio alla richiesta sbagliata e lista che supera il limite pur restando sotto i byte massimi.
- [x] Definire PresentationSet come mappa delle sole rappresentazioni widget, compactLeading, compactTrailing, minimal, expanded. Publication.content contiene un set; ogni ScheduledEntry ne contiene uno. Tutte le rappresentazioni condividono PublicationID e revisione; nessuna attività duplicata per lato o espansione. Il set corrente completo rispetta 64 KiB complessivi, e un piano temporale 256 KiB complessivi. Validare le rappresentazioni obbligatorie per widget/activity/notice e assenza di expanded negli avvisi.
- [x] Aggiungere test di round-trip dei messaggi, duplicati di feature/service/action, `sourceApp.required == false`, requirements per feature e impossibilità di usare bundleID come identità autenticata. Definire le fixture di conflitto modificando ID/REQUIRES e PROVIDES quando necessario per rappresentare un ciclo reale rispetto a focus; non usare fixture risolte in rete.
- [x] Eseguire ManifestTests e MessageTests; revisionare compatibilità dei nomi fra documenti e codice, aggiornare lo schema pubblico in docs/addons/manifest.schema.json e il registro errori in docs/addons/protocol.md. La consegna dei file è registrata nel rapporto P1; nessun commit del lavoro pregresso.

## Task 01.2 — Builder Swift e renderer delle stesse descrizioni

**Files:** creare Sources/CascadeContracts/ContentDocument.swift, ContentNode.swift, ActionDescriptor.swift; Sources/CascadePresentation/CascadeContent.swift, CascadeContentBuilder.swift, CascadeComponents.swift, ContentRenderer.swift, ContentPreview.swift; Sources/CascadeAddonSDK/AddonProvider.swift, AddonContext.swift; Tests/CascadePresentationTests/ContentArchiveTests.swift, ContentValidationTests.swift sotto CascadeKit. Aggiornare Package.swift con prodotti pubblici Contracts, Presentation e AddonSDK.

**Interfaces:** ContentDocument ha schemaVersion Int, root ContentNode, privacy enum, accessibilityLabel String e assetIDs [String]. `encode() throws -> Data`, `static decode(_:) throws -> ContentDocument`, `validate() throws`. ContentNode è uno struct validato con discriminante Kind e factory throwing per text(String), symbol(String), image(assetID), row([ContentNode]), column([ContentNode]), progress(value: Double), countdown(until: Date), clock(format: ClockFormat), action(ActionDescriptor). ClockFormat enum chiuso per ora/minuti/secondi, rispettando locale e accessibilità.

```swift
public protocol CascadeContent {
    var contentNode: ContentNode { get }
}

public protocol AddonProvider: Sendable {
    func handle(_ event: AddonEvent, context: AddonContext) async throws -> ProviderOutput
}
```

AddonEvent enum: refresh(PublicationID), scheduled(eventID: String), action(ActionRequest), serviceChanged(ServiceEvent), serviceRequest(ServiceInvocation), stop(StopReason). ServiceEvent contiene subscriptionID, token valido della nuova connessione e payload di servizio validato. ServiceInvocation contiene requestID, servizio/operazione, input e deadline; il broker autentica il chiamante prima dell'invio. AddonContext espone soltanto client di servizi/storage, generazione e concessioni correnti; nessun NotchEngine, NSApp, factory dell'host o collegamento al catalogo.

- [x] Scrivere il test di archiviazione di un documento costruito soltanto con valori:

```swift
@Test func keepsCountdownWithoutProviderObjects() throws {
    let document = try ContentDocument(
        schemaVersion: 1,
        root: try .countdown(until: Date(timeIntervalSince1970: 2_000_000_000)),
        privacy: .publicContent,
        accessibilityLabel: "Tempo rimanente",
        assetIDs: []
    )
    let decoded = try ContentDocument.decode(document.encode())
    #expect(decoded == document)
}
```

- [x] Implementare i tipi come valori Equatable oltre a Codable/Sendable dove pertinente; la privacy wire usa publicContent/sensitive e viene adattata alla privacy esistente solo al confine del motore.
- [x] Implementare CascadeRow, CascadeColumn, CascadeText, CascadeSymbol, CascadeImage, CascadeProgress, CascadeCountdown, CascadeClock e CascadeButton come componenti CascadeContent. Il result builder converte componenti in nodi. CascadeButton accetta ActionDescriptor (ID e payload), non una closure eseguibile dall'host. Documentare che questi non sono sostituti trasparenti di ogni SwiftUI.View.
- [x] Implementare ContentRenderer come SwiftUI.View con input ContentDocument e callback host per ActionDescriptor. La preview usa esattamente quel renderer, con un dispatcher di anteprima esplicito. Niente JSON costruito manualmente dallo sviluppatore e niente introspezione di una vista arbitraria.
- [x] Verificare 64 KiB wire, profondità 8, 128 nodi, stringhe 4 KiB, valori progress finite/clamped, simboli/URL consentiti, conteggio asset e azioni univoche. Provare immagini e pulsanti senza label accessibile, schema ignoto e profondità 9; devono essere rifiutati prima della costruzione delle viste.
- [ ] Eseguire ContentArchiveTests e ContentValidationTests; renderizzare le componenti con movimento/trasparenza ridotti e VoiceOver. Aggiungere docs/addons/content.md con componenti ammessi e differenza fra descrizione durevole e scena remota; commit.

## Task 01.3 — Resolver deterministico per addon e feature

**Files:** creare Sources/CascadeRuntime/Resolution/ResolutionPlanner.swift, ResolutionModels.swift, SemanticVersionRange.swift; Tests/CascadeRuntimeTests/ResolutionPlannerTests.swift, ResolutionFixtures.swift sotto CascadeKit; aggiornare Package.swift con Runtime e test. Il target Runtime dipende da Contracts e, da P2, Transport; non da CascadeKit o dalle Features.

**Interfaces:** `ResolutionPlanner.resolve(catalog: [InstalledAddon], environment: HostEnvironment, prior: [ServiceBinding]) throws -> Resolution`. InstalledAddon contiene manifest, identità firmatario verificata, digest e stato enabled. HostEnvironment contiene versione OS, capacità host, app installed/running e grants, tutti valori. Resolution contiene addon ammessi, feature bloccate con motivo, ordine di avvio, binding e dipendenti inversi. ServiceBinding identifica requirementID, consumer, provider, providerIdentity verificata, contractVersion, digest e featureID opzionale. Il valore nil indica lo scope radice; due feature possono avere binding diversi, mentre tutte le condizioni congiunte nello stesso scope devono soddisfare un unico binding.

- [x] Preparare nel target test fixture JSON con tre addon: Focus fornisce sessions 1.0; Consumer richiede >=1 <2; OptionalConsumer richiede l'app sorgente solo per openInSourceApp. Il parser di fixture produce i valori InstalledAddon con firma marcata test-only; nessun fake viene importato in produzione.
- [x] Verificare assenza dell'app: localTimer ammesso e openInSourceApp bloccata. Aggiungere ciclo A→B→A, conflitto major, due provider equivalenti, disabilitazione, vecchio binding valido e permesso mancante. Ogni caso deve avere output deterministico a parità di input, anche dopo permutazione del catalogo.
- [x] Implementare l'algoritmo, fuori dal MainActor:

```text
validate bounded catalog
evaluate root requirements and feature requirements separately
filter providers by enabled state, identity restriction, grants and version
choose explicit binding, then valid prior binding, then host, then stable candidate order
reject cycles and closures over 32 addons / 128 edges / depth 8
topologically order accepted dependencies and build reverse edges
return a plan with blocked reasons; perform no install, launch or permission request
```

- [x] Applicare un budget monotono di 256 passi alle alternative anyOf e ai tentativi di provider, senza restituire i passi durante il rollback; interrompere con resolutionTooComplex se il numero di esplorazioni supera il massimo della policy. Aggiungere tale errore al registro di 01.1. Nessuna ricerca combinatoria illimitata e nessun provider scelto perché ha risposto per primo.
- [x] Eseguire ResolutionPlannerTests e test generativi con seed registrato per ordine/cicli. Salvare docs/addons/requires.md con installato versus aperto, versioni di servizio versus pacchetto e limiti. Revisionate anche riproduzioni esterne e rollback, grafi già ammessi e vincoli congiunti per scope.

## Task 01.4 — Contenuti posseduti dall'host e adattamento del notch

**Files:** creare Sources/CascadeRuntime/Publications/PublicationStore.swift, PublicationTimeline.swift; Sources/CascadeKit/Core/AddonPresentation/AddonPresentationBridge.swift, SnapshotWidget.swift, SnapshotActivity.swift, SnapshotNotice.swift; Tests/CascadeRuntimeTests/PublicationStoreTests.swift e Tests/CascadeKitTests/AddonPresentationTests.swift sotto CascadeKit. Modificare Core/Widgets/WidgetContext.swift, WidgetHost.swift e Core/Activities/LiveActivityHost.swift solo per revoca/identità e bridge necessari.

**Interfaces:** `actor PublicationStore` espone `accept(_ publication: Publication, owner: AddonID) throws`, `snapshot(at: Date) -> [Publication]`, `remove(owner: AddonID)`, `expire(at: Date)`. Nessuno di questi metodi conserva AddonProvider. `@MainActor AddonPresentationBridge.apply(_ publications: [Publication])` riceve solo valori e usa il motore; non importa Runtime. L'app collegherà i due in P3.

- [x] Scrivere PublicationStoreTests per accettare una pubblicazione, distruggere il produttore di test, leggere la stessa pubblicazione; revisione inferiore rifiutata, altro owner rifiutato, scadenza finita, rimozione di tutte le voci future al disable.
- [x] Implementare snapshot/piani temporali con date ordinate, 32 voci e 256 KiB per istanza; budget iniziale di stato host conservato 8 MiB globale, separato da 32 MiB di asset e dallo storage su disco. Non preallocare 8 MiB per ogni addon. Countdown/clock sono regole temporali, non liste di tick.
- [x] Adattare documenti a NotchWidget/NotchLiveActivity/NotchTransientNotice solo dentro il bridge. Namespacing runtime prima del motore. Preservare sessioni 8 ore ancorate, avvisi 10 s/backlog 8, privacy prima del rendering, priorità e comportamento delle due attività. Non sostituire l'arbitraggio esistente con le priorità del provider.
- [x] Rendere revocabile WidgetContext e verificare che una copia trattenuta non invalidi dopo suspend. Invalidare solo l'istanza/revisione interessata nel bridge, senza ricreare tutta la pagina per un valore identico. Aggiungere test a AddonPresentationTests per rilascio della vista clock nascosta dalle cache (la misura energetica resta da qualificare), snapshot visibile senza provider e contenuto sensibile redatto anche nell'accessibilità.
- [x] Gestire asset tramite riferimenti: il bridge accetta solo asset già validati dal servizio P2, con segnaposto in caso assente. Nessuna lettura di percorso o decodifica sincrona nelle factory; decoder e quota saranno introdotti in 02.5.
- [x] Eseguire PublicationStoreTests, AddonPresentationTests, LiveActivityHostTests e NotchActivityLifetimeTests; eseguire la build e il riavvio prescritti se si è modificato il codice app/engine integrato. Registrare esiti P1 e reintegrare solo i file pertinenti con controllo dei conflitti. Il commit è differito perché il checkout contiene lavoro pregresso non committato.
