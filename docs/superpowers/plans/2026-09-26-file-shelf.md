# Persistent File Shelf Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consegnare il ripiano persistente con carte ed elenco animati, conversione con freccia centrale e drag in uscita verificato per file.

**Architecture:** Un servizio host conserva riferimenti e risultati; il provider del ripiano usa gli stessi contratti SDK e le stesse autorizzazioni degli addon esterni. Un componente dichiarativo condiviso descrive il workspace file; AppKit gestisce il trasferimento e SwiftUI la presentazione. FFmpeg opera fuori dal main actor e viene supervisionato indipendentemente dalla visibilità della pagina.

**Tech Stack:** Swift 6.2, macOS 14+, AppKit, SwiftUI, Foundation, ImageIO, PDFKit, FFmpeg/ffprobe; moduli CascadeContracts, CascadePresentation, CascadeAddonSDK e CascadeRuntime.

**Spec:** [Specifica approvata](../specs/2026-09-26-file-shelf-design.md).

## Global Constraints

- «Gli originali rimangono nella loro posizione.»
- «Il limite proposto è di quattro carte visibili, con contatore +N oltre la quarta.»
- «La freccia occupa il centro verticale e orizzontale dello spazio fra i due gruppi di carte.»
- «Il batch iniziale elabora un file alla volta in background, senza bloccare la UI.»
- «Una pagina nascosta non annulla il lavoro.»
- «Si persiste prima la rimozione della voce; soltanto dopo si può ripulire il file».
- «Non si dipende da Homebrew installato dall'utente.»
- «La pagina persistente si coordina con la specifica delle pagine contestuali, che è ancora in discussione».
- Rispettare CODE_STYLE.md: macOS 14, nessun force unwrap, protocolli ai confini dei servizi, IO fuori dal main actor, nessun polling inattivo.
- Nessun widget interno privilegiato; file, processi e memoria passano attraverso la policy comune. Non alzare implicitamente le quote di ResourcePolicy.
- Converti è incluso. Condividi e Crea ZIP rimangono successivi; nessuna implementazione della navigazione generale a tre attività è implicita.
- Conservare le numerose modifiche preesistenti del checkout. Durante l'esecuzione usare un checkout che le includa: un worktree da HEAD da solo non rappresenta questa base.

## Review Focus

1. Crash fra scrittura della copia e salvataggio della rimozione: l'elemento può restare, ma il risultato non deve essere perso (task 2 e 3).
2. File rinominato, symlink sostituito, volume scollegato o file cloud non materializzato: nessuna conversione di un bersaglio diverso o rimozione silenziosa (task 2 e 6).
3. Input media che rimanda ad altri file o URL, nomi con trattini e caratteri shell: nessun accesso oltre i file autorizzati e nessuna interpolazione shell (task 5 e 6).
4. Drag durante Spotlight, cambio display o transizione dell'elenco: nessuna perdita di focus, consegna duplicata o carta non più raggiungibile (task 3 e 7).
5. Ricevuta tardiva dopo riavvio/revoca, quota esaurita e processo ancora vivo dopo annullamento: non riattivare lavoro, non liberare prematuramente file o risorse (task 1, 2 e 6).

## Base verificata e ordine

Il grafo `cascade-task6` individua i simboli, ma alcune posizioni non seguono le
modifiche correnti: verificare il sorgente del checkout prima di editarlo.

- MouseEventMonitor osserva già drag locali/globali; non riconosce ancora file.
- NotchDisplayCoordinator ha trigger e hold `.drag` e garantisce un solo notch aperto.
- NotchPanel non diventa key/main e usa hit testing tramite `ignoresMouseEvents`.
- ContentNode non ha workspace file, selettore o drag source; ContentDocument supporta schemi 1 e 2.
- AddonPresentationBridge rende documenti ammessi; non deve acquisire URL, eseguire FFmpeg o diventare il database.
- ServiceBroker ha operazioni finite (deadline massima 30 secondi) e sorgenti/eventi separati: avvio conversione restituisce un job ID, non attende tutta la conversione.
- Il confine AddonRuntimeAdapter è ancora documentato senza conformer di produzione qualificato. Una fixture non prova il percorso di distribuzione.
- ResourcePolicy pone attualmente 10 MiB di stato disco e 20 MiB di cache per proprietario, 30 MiB complessivi; i risultati persistenti non possono essere nascosti nella cache o esclusi dal conteggio. Video grandi possono essere rifiutati: una revisione della policy è un intervento distinto da questo piano.

Ordine: 1 → 2 → 3 → 4 → 7 produce il ripiano; 5 → 6 → 8 aggiunge la conversione;
9 verifica la composizione. I task 4 e 5 sono tecnicamente indipendenti, ma
l'esecuzione può rimanere sequenziale. L'esito del task 1 è prerequisito della
distribuzione, non una dichiarazione che il runtime sia già pronto.

## Mappa dei file

I nuovi file di modello contengono valori; le implementazioni di sistema stanno
nel lato host. I percorsi indicati nei task sono relativi alla radice del progetto.

| Area | Responsabilità |
| --- | --- |
| CascadeContracts/FileWorkspace/ | Snapshot paginati, identificatori opachi, comandi e stati di conversione. |
| CascadeRuntime/FileWorkspace/ | Autorità sui file, persistenza, ricevute e job supervisionati. |
| CascadeAddonSDK/FileWorkspace/ | Client del servizio e provider attraverso contratti pubblici. |
| CascadePresentation/FileWorkspace/ | Componente comune, layout e animazioni senza accesso ai percorsi. |
| CascadeKit/Core/Interaction/ e Core/Engine/ | Adattatori AppKit, routing del drag e pagina contestuale. |
| Cascade/Integrations/FileWorkspace/ | Composizione del servizio e risorse firmate dell'app. |
| Config/FFmpeg/ e scripts/ | Versione, provenienza, compilazione e verifica dei binari. |

Ogni task aggiunge test al target del modulo corrispondente. SwiftPM include
automaticamente i file sotto Sources/Tests; il collegamento del target app e
dei binari richiede invece Cascade.xcodeproj/project.pbxproj.

### Task 1: Contratto pubblico e verifica del percorso autorizzato

**Files:** Create in `CascadeKit/Sources/CascadeContracts/FileWorkspace/`: `FileWorkspaceSnapshot.swift`, `FileWorkspaceCommand.swift`, `FileWorkspaceEntry.swift`, `FileWorkspaceError.swift`, `FileConversionFormat.swift`, `FileConversionJobSnapshot.swift`; create `CascadeKit/Sources/CascadeAddonSDK/FileWorkspace/FileWorkspaceClient.swift`; create `CascadeKit/Sources/CascadeRuntime/FileWorkspace/FileWorkspaceService.swift`; test `CascadeKit/Tests/CascadeContractsTests/FileWorkspaceContractTests.swift`, `CascadeKit/Tests/CascadeRuntimeTests/FileWorkspaceAuthorityTests.swift`; consult `CascadeKit/Sources/CascadeRuntime/AddonRuntimeTransport.swift` and `CascadeKit/Sources/CascadeRuntime/Services/ServiceBroker.swift`.

**Interfaces:**
- `FileWorkspaceEntry`: `id: UUID`, `name: String`, `typeIdentifier: String`, `availability: FileAvailability`, `ownership: FileOwnership`, `thumbnailAssetID: String?`; no URL/bookmark nel wire.
- `FileWorkspaceSnapshot`: `revision: UInt64`, `entries: [FileWorkspaceEntry]`, `totalCount: Int`, `nextCursor: String?`, `jobs: [FileConversionJobSnapshot]`. Massimo 32 voci per pagina, payload entro 64 KiB; il limite di pagina non limita il ripiano.
- `FileWorkspaceCommand`: `.list(cursor: String?)`, `.remove(ids: [UUID], revision: UInt64)`, `.relink(id: UUID)`, `.convert(ids: [UUID], formatID: String, revision: UInt64)`, `.cancel(jobID: UUID)`.
- `FileWorkspaceClient.send(_ command: FileWorkspaceCommand) async throws -> FileWorkspaceSnapshot` usa AddonServiceClient; servizio `files.workspace`, feature `workspace`, operazione `command`. Gli eventi usano la stessa sorgente autorizzata; nessun client SDK legge file.
- `FileWorkspaceService` ammette comandi solo dopo validazione del ServiceWork canonico. Gli ID sono riferimenti, mai permessi.
- `FileWorkspaceError`: codici `unavailable`, `permissionDenied`, `unsupported`, `quotaExceeded`, `staleRevision`, `interrupted`, `ioFailure`; testo utente localizzato dal renderer. `FileConversionFormat`: `id`, `label`, `outputTypeIdentifier`; `FileConversionJobSnapshot` ha i campi fissati nel task 6. Questi valori vengono definiti qui per mantenere compilabile il client prima del motore.

- [ ] Scrivere `FileWorkspaceContractTests` per limite 32, campi sconosciuti, ID duplicati, revisioni obsolete e dimensione wire; `FileWorkspaceAuthorityTests` per owner diverso, grant revocato, comando duplicato e stesso comportamento builtin/esterno. Assertion: `#expect(snapshot.entries.count == 32)` e rifiuto della voce 33 nello stesso payload.
- [ ] Eseguire `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test --package-path CascadeKit --filter FileWorkspace`; atteso fallimento per contratto mancante.
- [ ] Implementare i contratti e l'adattamento al broker, mantenendo il limite di 30 secondi per il comando di avvio. Collegare un piccolo provider firmato al percorso nativo corrente e verificare autorizzazione, revoca e uscita osservata. Non creare un bypass in-process per superare l'assenza del trasporto.
- [ ] Ripetere i test; eseguire `zsh scripts/check-addon-boundaries.sh --root "$PWD"`. Registrare in `docs/superpowers/verification/2026-09-26-file-workspace-runtime.md` il percorso reale usato. Se il runtime nativo non può essere qualificato, il montaggio in produzione resta bloccato; modelli e renderer possono avanzare, ma non si dichiara la feature consegnata.
- [ ] Commit selettivo: `feat: add authorized file workspace contracts`.

### Task 2: Ripiano persistente e conservazione dei file

**Files:** Create in `CascadeKit/Sources/CascadeRuntime/FileWorkspace/`: `FileWorkspaceStore.swift`, `FileWorkspacePersisting.swift`, `FileReferenceResolving.swift`; test `CascadeKit/Tests/CascadeRuntimeTests/FileWorkspaceStoreTests.swift`.

**Interfaces:**
- `FileWorkspaceStore.init(directory: URL, persistence: any FileWorkspacePersisting, references: any FileReferenceResolving)`; actor con unico writer.
- `restore() async throws`, `addOriginals(_ urls: [URL]) async throws -> [UUID]`, `importPromisedFile(_ url: URL) async throws -> UUID`, `snapshot(cursor: String?) async throws -> FileWorkspaceSnapshot`.
- `beginDelivery(ids: [UUID]) async throws -> UUID`; `finishDelivery(_ deliveryID: UUID, itemID: UUID, result: Result<Void, FileWorkspaceError>) async throws`.
- `FileWorkspacePersisting.load() async throws -> Data?`, `save(_ data: Data) async throws`; implementazione Foundation con sostituzione atomica di un record versionato. `FileReferenceResolving.resolve(_ bookmark: Data) async throws -> URL` aggiorna bookmark obsoleti dopo verifica dell'identità.
- Stati `available`, `unavailable`, `receiving`; ownership `externalReference`, `managed`. File incompleti e metadati restano separati dai risultati completi.

- [ ] Scrivere test con directory temporanee reali: riapertura dello store conserva ordine e ID; stesso originale non duplicato; omonimi distinti; volume/originale mancante resta visibile; corruzione/versione futura non viene sovrascritta; salvataggio fallito conserva stato precedente. Verificare `#expect(restoredIDs == originalIDs)`.
- [ ] Lanciare il filtro `FileWorkspaceStoreTests` col comando Swift del task 1: atteso FAIL.
- [ ] Implementare riferimenti persistenti e risultati sotto Application Support del proprietario, con addebito alle quote esistenti prima dell'acquisizione. Nessuna copia preventiva degli originali. Per file promessi: ammettere spazio prima della scrittura, controllare la crescita, nessuna voce disponibile prima del completamento.
- [ ] Aggiungere prove di crash ai confini: copia completata senza conferma persistita mantiene la voce; rimozione persistita prima della pulizia lascia al più un file orfano recuperabile. Una rimozione manuale di risultato gestito usa testo esplicito e conferma prima di eliminare l'unica copia; revoche non cancellano originali.
- [ ] Ripetere il filtro: PASS. Commit selettivo `feat: persist file shelf entries and delivery receipts`.

### Task 3: Drag nativo, acquisizione e consegna per elemento

**Files:** Create `CascadeKit/Sources/CascadeKit/Core/Interaction/FileWorkspaceDragging.swift`; modify under `CascadeKit/Sources/CascadeKit/`: `Core/Events/MouseEventMonitor.swift`, `Core/Events/EventMonitoring.swift`, `Core/Window/NotchPanel.swift`, `Core/Engine/NotchController.swift`; test `CascadeKit/Tests/CascadeKitTests/FileWorkspaceDraggingTests.swift`.

**Interfaces:**
- `@MainActor protocol FileWorkspaceTransferring` con `receive(_ draggingInfo: any NSDraggingInfo) -> Bool` e `beginDrag(ids: [UUID], event: NSEvent, sourceView: NSView) throws -> NSDraggingSession`.
- Adattatore AppKit riceve store/autorità host attraverso un protocollo async, non attraverso il renderer pubblico. Una NSFilePromiseProvider per elemento; la completion chiama `finishDelivery` con il token del task 2.
- Il monitor emette `onFileDragChanged: ((Bool) -> Void)?` soltanto ai cambi rilevati; l'ingresso AppKit convalida i tipi realmente offerti.

- [ ] Test: mouse drag non-file non attiva il ripiano; pasteboard vecchia non riattiva il battito; drop annullato non acquisisce; batch con una promise riuscita e una fallita rimuove soltanto la prima. `#expect(remainingIDs == [failedID])`.
- [ ] Eseguire filtro `FileWorkspaceDraggingTests`: FAIL prima dell'implementazione.
- [ ] Collegare monitor locale/globale esistente e bersaglio AppKit alla sagoma animata. Consentire la ricezione nell'area del notch durante drag senza intercettare l'intera menu bar; usare trigger/hold `.drag` esistenti.
- [ ] Implementare copia per promessa fuori dal main actor, nomi di destinazione sicuri e collisioni senza sovrascrittura. Risultati gestiti solo tramite promises; URL-only degli originali mantiene la voce. Non usare l'esito globale endedAt per svuotare il batch.
- [ ] Verificare filtro PASS più drop reale Finder, annullamento e drop parziale. Verificare che Mail/app URL-only non provochino rimozioni non dimostrate. Commit `feat: support verified native file shelf transfers`.

### Task 4: Componente SDK comune e lista animata

**Files:** Create `CascadeKit/Sources/CascadeContracts/FileWorkspace/FileWorkspacePresentation.swift`; modify under `CascadeKit/Sources/CascadeContracts/`: `ContentNode.swift`, `ContentNode+Components.swift`, `ContentDocument.swift`, `ProviderMessage.swift`; modify `CascadeKit/Sources/CascadeRuntime/Admission/ProtocolNegotiator.swift` and `PublicationSessionRegistry.swift` in the same directory; create under `CascadeKit/Sources/CascadePresentation/FileWorkspace/`: `CascadeFileWorkspace.swift`, `FileWorkspaceLayout.swift`; modify `CascadeKit/Sources/CascadePresentation/ContentRenderer.swift`; test `CascadeKit/Tests/CascadeContractsTests/FileWorkspaceContentTests.swift`, `CascadeKit/Tests/CascadePresentationTests/FileWorkspacePresentationTests.swift`.

**Interfaces:**
- `FileWorkspacePresentation`: snapshot paginato, `mode: FileWorkspaceMode` (`deck`, `list`, `conversion`), selezione `[UUID]`, destinazioni `[FileConversionFormat]`, formato selezionato e descrittori azione validati.
- `CascadeFileWorkspace.init(_ presentation: FileWorkspacePresentation) throws`; un nodo `.fileWorkspace` nello schema contenuti 3, disponibile a builtin ed esterni. Nessuna URL, closure provider o scelta di autorità nel documento.
- `FileWorkspaceLayout.cardTransforms(count: Int, reduceMotion: Bool) -> [FileCardTransform]`; `conversionFrames(in bounds: CGRect) -> FileConversionFrames` produce ingressi, freccia, controlli e risultati senza sovrapposizioni.

- [ ] Test: schema 1/2 rifiuta nuovo nodo; schema 3 negoziato lo accetta; limiti globali di nodi/byte/asset ancora applicati; azioni duplicati rifiutate. Layout: `#expect(cardTransforms.count == min(count, 4))`, +N corretto e centro della freccia fra i gruppi.
- [ ] Eseguire filtri `FileWorkspaceContentTests` e `FileWorkspacePresentationTests`: FAIL.
- [ ] Implementare il componente con miniature risolte tramite asset resolver esistente. Identità stabili e matched geometry per carte→righe→carte, sfalsamento breve, selezione distinta dal drag, lista scorrevole e paginata. Il viewport non carica tutte le miniature.
- [ ] Aggiungere il campo opzionale `fileWorkspace: FileWorkspacePresentation?` a ContentNode, valido solo sul nuovo kind. Estendere ContentDocument, ProviderMessage.validateContext e ProtocolNegotiator da insiemi 1/2 a 1/2/3; l'host pubblicizza 3 solo con renderer/adattatori installati. PublicationSessionRegistry conserva l'insieme negoziato. Mantenere default legacy e nessun fallback che elimini campi; verificare anche documenti nelle timeline future. Lo schema 3 conserva glassLights come il 2.
- [ ] Verificare filtri PASS e preview montata con 1/4/5/40 file, VoiceOver e Riduci movimento. Nessun timer a transizione conclusa. Commit `feat: add shared animated file workspace content`.

### Task 5: FFmpeg riproducibile nel bundle

**Files:** Create `Config/FFmpeg/manifest.json`, `scripts/build-ffmpeg.sh`, `scripts/verify-ffmpeg.sh`, `docs/third-party/ffmpeg.md`; modify `Cascade.xcodeproj/project.pbxproj`, `scripts/build-development.sh`; create `Cascade/Resources/ThirdParty/FFmpeg/` for staged executables and notices.

**Interfaces:**
- `build-ffmpeg.sh --output <directory> --arch arm64|x86_64` produce ffmpeg e ffprobe per macOS 14; il manifest registra versione, URL, hash verificato, flags e dipendenze.
- `verify-ffmpeg.sh <directory>` controlla architettura, deployment target, librerie non di sistema, versione, encoder e risultato di una conversione fixture.
- Baseline sorgente: release FFmpeg 9.0.2 dalla pagina ufficiale consultata il 26 settembre 2026; verificare firma e registrare SHA-256 prima della build. Nessun hash inventato nel piano.

- [ ] Scrivere la verifica che fallisce su binari mancanti, architettura errata, dipendenza da /opt/homebrew o versione diversa dal manifest.
- [ ] Eseguire `zsh scripts/verify-ffmpeg.sh Cascade/Resources/ThirdParty/FFmpeg`: atteso FAIL prima di preparare gli artefatti.
- [ ] Compilare dal sorgente verificato con programmi ffmpeg/ffprobe, senza ffplay, GPL o nonfree. Usare VideoToolbox per H.264 quando disponibile, encoder nativi AAC/PCM/FLAC; MP3 compare solo se l'encoder redistribuibile è incluso e verificato. Non introdurre libx264 implicitamente. Registrare licenze e sorgenti/configurazione corrispondenti.
- [ ] Copiare e firmare gli helper nel bundle con l'identità di sviluppo dell'app; la normale build consuma artefatti già verificati senza scaricare dipendenze dalla rete. Verificare architettura effettivamente consegnata, senza attribuire prove Intel alla sola esecuzione ARM.
- [ ] Ripetere verifica: PASS e fixture convertita leggibile da ffprobe. Commit `build: bundle verified ffmpeg conversion tools`.

### Task 6: Conversioni effettive e job recuperabili

Checkpoint: la parte pura di formati, preset e parser del progresso è implementata nel sottotask [Preparare formati e avanzamento della conversione](../../../.scratch/cascade-product/issues/86-file-workspace-conversion-planning.md), commit `5c53ae5`. Non completa il task: coordinatore, persistenza job, motori nativi e processi supervisionati rimangono da implementare/qualificare.

**Files:** Create under `CascadeKit/Sources/CascadeRuntime/FileWorkspace/`: `FileConversionCoordinator.swift`, `FileConverting.swift`, `FFmpegConverter.swift`, `NativeDocumentConverter.swift`, `FFmpegProgressParser.swift`, `FileConversionRequest.swift`; test under `CascadeKit/Tests/CascadeRuntimeTests/`: `FileConversionTests.swift`, `FFmpegProgressTests.swift`.

**Interfaces:**
- `FileConverting.formats(for inputs: [URL]) async throws -> [FileConversionFormat]`; `convert(_ request: FileConversionRequest, progress: @Sendable (Double?) -> Void) async throws -> [URL]`.
- `FileConversionRequest`: job/item ID, input URL autorizzata dall'host, directory provvisoria gestita e format ID chiuso; nessuna opzione CLI fornita dal widget.
- `FileConversionCoordinator.start(ids: [UUID], formatID: String, revision: UInt64) async throws -> UUID`, `cancel(jobID: UUID) async throws`; aggiornamenti tramite sorgente del task 1, stesso store del task 2.
- `FileConversionJobSnapshot`: ID, stato `queued/running/completed/failed/cancelled/interrupted`, progresso opzionale e risultati completati. Il comando di avvio restituisce dopo l'ammissione, non al termine del job.

- [ ] Test parser con righe spezzate, durata assente, progress=end con exit nonzero; test coordinatore per due file sequenziali, selezione mista, annullamento e riavvio. `#expect(maximumConcurrentConversions == 1)`; output parziale non appare nei risultati.
- [ ] Eseguire filtri `FileConversionTests|FFmpegProgressTests`: atteso FAIL.
- [ ] Implementare Process con argomenti separati, `-nostdin`, progress su pipe e stderr drenato con buffer limitato. Identificare contenuti con ffprobe; applicare protocol whitelist, rifiutare playlist/riferimenti esterni e confinare il processo ai file autorizzati. Nessuna shell né download dai media.
- [ ] Prima di avviare, riservare job/processo/memoria/spazio secondo la policy comune; addebitare crescita dell'output e fermare il job prima di superare la quota. Non usare la sola dimensione dell'ingresso come garanzia della dimensione convertita. Stop/timeout attende l'uscita osservata prima di rilasciare risorse e cancellare provvisori.
- [ ] Implementare ImageIO e PDFKit dietro FileConverting: JPEG/PNG/TIFF/HEIC disponibili, immagini→PDF, PDF→una immagine per pagina. Politiche esplicite: orientamento applicato, colore conservato dove supportato, JPEG senza alpha usa fondo bianco, nessuna falsa conservazione di testo selezionabile dal PDF. Elaborare pagine sequenzialmente con limite di memoria.
- [ ] Verificare media reali piccoli e generati localmente: video→MP4, audio→WAV/FLAC/M4A e MP3 se incluso, immagine con alpha/orientamento, PDF multipagina; quota insufficiente, nomi shell, file sostituito, input corrotto e riferimenti esterni rifiutati. PASS dei filtri, originali invariati e output verificati prima della pubblicazione. Commit `feat: run recoverable file conversion jobs`.

### Task 7: Ripiano come pagina principale e battito del notch

**Files:** Create `CascadeKit/Sources/CascadeKit/Core/Widgets/ContextualPageRegistry.swift`; modify under `CascadeKit/Sources/CascadeKit/`: `Core/AddonPresentation/AddonPresentationBridge.swift`, `Core/Engine/NotchEngine.swift`, `Core/Engine/NotchDisplayCoordinator.swift`, `Core/Engine/NotchController.swift`, `Components/NotchHostView.swift`; test `CascadeKit/Tests/CascadeKitTests/FileWorkspaceRoutingTests.swift`.

**Interfaces:**
- `ContextualPageRegistry.setFileWorkspace(publicationID: PublicationID, occupied: Bool)` riceve solo identità validate dall'host, mai direttamente dal documento non fidato; `remove(publicationID:)` ritira la registrazione.
- Il provider continua a pubblicare `.widget` attraverso lo SDK; la registrazione del ruolo di pagina è una decisione host comune per addon autorizzati, non un nuovo kind di Live Activity o un numero di priorità gigantesco.
- Lo stato di navigazione distingue destinazione aperta, destinazione precedente al drag e pagina predefinita. L'occupazione è derivata dal servizio persistente, non dalla scadenza di una singola publication.

- [ ] Test: ripiano occupato diventa predefinito; scelta manuale resta fino a chiusura; drag annullato ripristina pagina; ultimo file consegnato ripristina selezione ordinaria; display rimosso non duplica acquisizione. `#expect(openDisplayCount == 1)`.
- [ ] Eseguire filtro `FileWorkspaceRoutingTests`: FAIL.
- [ ] Collegare registro, host e bridge riusando SnapshotWidget e il renderer condiviso. Provider nascosto sospeso; stato e conversioni nel servizio. Pubblicazioni finite si rinnovano su apertura/evento reale, senza deadline infinita né polling di keepalive; mostrare stato di caricamento invece di comandi scaduti.
- [ ] Collegare doppio impulso una volta per drag e hold durante ricezione/consegna; animare tramite il percorso della molla esistente senza spostare il taglio fisico. Ripristinare bersaglio e hit testing dopo annullamento, fine drag, lock o cambio display.
- [ ] Verificare filtri PASS e regressioni NotchControllerTests/NotchDisplayCoordinatorTests. Prova nativa Spotlight con testo presente: drag annullato conserva ricerca e focus; se la composizione non è supportata, registrare il blocco anziché chiudere silenziosamente Spotlight. Commit `feat: route the persistent file shelf through the notch`.

### Task 8: Provider del ripiano e interfaccia di conversione

**Files:** Create `CascadeKit/Sources/CascadeAddonSDK/FileWorkspace/FileWorkspaceProvider.swift`; create `Cascade/Integrations/FileWorkspace/FileWorkspaceComposition.swift`; modify `Cascade/CascadeServices.swift`; test `CascadeKit/Tests/CascadePresentationTests/FileWorkspaceProviderTests.swift`; add strings under `Cascade/Resources/FileWorkspace.xcstrings` and SDK localization resources where used.

**Interfaces:**
- `FileWorkspaceProvider: AddonProvider` implementa `handle(_:context:) async throws -> ProviderOutput` con sola API SDK. Stato UI selezione/formato non è l'autorità dei file.
- `FileWorkspaceComposition.start() async throws`, `stop() async`; registra provider/servizio e capacità tramite il percorso qualificato nel task 1. La UI non costruisce processi o store autonomi.
- Action IDs chiusi: `openList`, `closeList`, `select`, `nextPage`, `convert`, `selectFormat`, `start`, `cancel`, `remove`, `relink`, `preview`, `reveal`. Le azioni sul filesystem passano sempre all'host autorizzato.

- [ ] Test: clic mazzo produce mode list e ritorno deck; selezione compatibile propone formati; Avvia assente senza formato; snapshot aggiornato non riavvia job; progress indeterminato non mostra percentuale fittizia; completamento preserva ingressi.
- [ ] Eseguire filtro `FileWorkspaceProviderTests`: FAIL.
- [ ] Comporre componenti del task 4 e servizio del task 6. Freccia centrata sulla linea che unisce le carte, selettore nella zona centrale sopra la freccia, Avvia/Annulla in spazio distinto senza spostare la freccia al fondo. Le anteprime di risultato sono etichettate prima dell'esecuzione.
- [ ] Collegare Anteprima/Mostra nel Finder e ricollegamento con selezione esplicita del file; preservare le autorizzazioni al riavvio. Offrire alternative da tastiera al drag attraverso comandi nativi; focus solo su invocazione esplicita, mai durante hover o heartbeat.
- [ ] Verificare filtro PASS e schermo reale: carte leggibili, testo lungo, finestra stretta, 40 elementi, tastiera, VoiceOver, Riduci movimento. Commit `feat: connect file shelf actions and conversion presentation`.

### Task 9: Verifica integrata, build e consegna

**Files:** Create `docs/superpowers/verification/2026-09-26-file-shelf.md`; update `docs/addons/content.md`, `docs/addons/services.md` con i soli contratti effettivamente implementati; nessuna modifica estranea.

- [ ] Eseguire tutti i filtri FileWorkspace/FileConversion/FFmpegProgress e i test di routing. Se passano, eseguire una volta `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test --package-path CascadeKit`; atteso nessun test fallito. Classificare separatamente eventuali errori preesistenti con evidenza, senza dichiarare PASS.
- [ ] Eseguire `zsh scripts/check-addon-boundaries.sh --root "$PWD"` e verifica FFmpeg. Dimostrare che builtin ed esempio esterno usano stesso renderer, client e autorizzazioni; registrare versione/schema realmente negoziati.
- [ ] Eseguire la matrice reale: Finder→ripiano→riavvio→Finder; cinque file e lista animata; conversione→risultato→consegna; copia fallita; drop parziale; riavvio durante conversione e consegna; originale mancante; cambio display; Spotlight; idle dopo transizione. Registrare limiti di runtime, codec, quote e architetture effettivamente osservati.
- [ ] Eseguire `zsh scripts/build-development.sh`; atteso BUILD SUCCEEDED, firma verificata e collegamento /Applications/Cascade.app aggiornato dallo script. Se fallisce, non avviare una build vecchia dichiarandola aggiornata.
- [ ] Chiudere Cascade, attendere uscita, aprire /Applications/Cascade.app e verificare nuovo PID e percorso dell'eseguibile; confermare che i file del ripiano siano ancora presenti. Registrare questi esiti prima di completare il lavoro.
- [ ] Rivedere diff finale, copertura F1–F11 e limiti dichiarati; commit selettivo `docs: record file shelf integration verification`. Nessuna pulizia delle modifiche preesistenti.

## Self-review e handoff

- F1–F4: task 2, 3, 4 e 7. F5: task 4 e 8. F6–F9: task 5, 6 e 8. F10: task 2 e 3. F11: task 2, 6 e 9.
- I cinque Review Focus hanno prove nei task indicati; la qualifica nativa non viene sostituita da mock.
- Schema 3 non elimina supporto 1/2; pagina del ripiano non introduce implicitamente tre attività o nuove policy generali.
- FFmpeg, documenti nativi e ripiano condividono ricevute e persistenza; nessun motore AVFoundation aggiuntivo.
- Il piano è da revisionare. Raccomandata esecuzione nativa in questa chat, sequenziale: gli adattatori condividono autorità, stato e lifecycle; una revisione finale indipendente precede la consegna.
- Limiti da rendere visibili nella consegna: quote attuali possono rifiutare file grandi; disponibilità MP3 dipende dalla build; produzione resta subordinata alla qualifica del task 1. Non aumentare quote o aggirare isolamento per far passare una demo.

Fonti esterne per il task 5: [release ufficiali FFmpeg](https://ffmpeg.org/download.html), [redistribuzione](https://ffmpeg.org/legal.html). Versione e data sono state consultate il 26 settembre 2026, non dedotte dalla versione eventualmente installata sul Mac.
