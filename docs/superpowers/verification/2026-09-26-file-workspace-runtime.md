# Task 1 native-path qualification

## Verdict

**Blocked. A signed real provider cannot currently use the common `CascadeAddonSDK` service client through `CascadeRuntime` in the shipping app.** The typed SDK client and the runtime broker/service path exist, but the production native transport/bootstrap and app composition that join them do not.

This means Task 1 can add and test contracts, `FileWorkspaceClient`, and host-side authorization logic, but it cannot satisfy the brief's signed-provider/native-path qualification or claim production mounting. An in-process adapter would only reproduce the existing test arrangement and would violate the explicit no-bypass requirement.

## Concrete composition found

- `TransportServiceClient` is the real public `AddonServiceClient` conformer. It requires an injected `AddonServiceMessageChannel` (`CascadeKit/Sources/CascadeAddonSDK/Services/TransportServiceClient.swift:6,24,37`). The channel contract explicitly says it is not a native transport (`CascadeKit/Sources/CascadeAddonSDK/Services/AddonServiceMessageChannel.swift:11-20`).
- `AddonRuntime` requires an injected `AddonRuntimeAdapter`; protocol 1.3/1.4 service support activates only when that object also conforms to `AddonRuntimeServiceAdapter` / `AddonRuntimeServiceSubscriptionAdapter` (`CascadeKit/Sources/CascadeRuntime/AddonRuntime.swift:553-615`). The base protocol itself records that it has no production conformer (`CascadeKit/Sources/CascadeRuntime/AddonRuntimeTransport.swift:106-112`).
- The only concrete complete runtime service adapter in the checkout is test code: `InvocationMessageAdapter` conforms to the subscription, storage, and asset adapter protocols (`CascadeKit/Tests/CascadeRuntimeTests/ServiceInvocationMessageIntegrationTests.swift:1146-1149`). The codebase graph likewise finds this as the sole concrete `AddonRuntimeServiceSubscriptionAdapter` implementor; other runtime-adapter classes are test fixtures.
- The only `AddonServiceMessageChannel` conformers are test channels. The most complete one, `SubscriptionRuntimeChannel`, is private test code (`CascadeKit/Tests/CascadeRuntimeTests/ServiceSubscriptionMessageIntegrationTests.swift:711-725`). The test at lines 631-675 composes it with `TransportServiceClient`, `AddonRuntime`, modeled process exit, and the test adapter. It proves the internal byte/receipt path, not OS transport or a signed provider.
- The app target links only the `CascadeKit` product (`Cascade.xcodeproj/project.pbxproj:118-124`). That product depends on `CascadeContracts` and `CascadePresentation`, not `CascadeRuntime` or `CascadeAddonSDK` (`CascadeKit/Package.swift:93-98`). `CascadeApp` imports `CascadeKit` and constructs no `AddonRuntime` (`Cascade/CascadeApp.swift:7-15,30-58`). `AddonRuntime` is also an internal actor in the separate runtime product (`CascadeKit/Sources/CascadeRuntime/AddonRuntime.swift:10-12`).
- The signed native probes are separate fixtures with their own `ProbeBootstrap` / `ProbeChannel` XPC vocabulary and do not import `CascadeAddonSDK` or `CascadeRuntime` (`Prototypes/AddonPlatform/Provider/ProbeProvider.swift:6-35`). They therefore do not supply the missing common-SDK/runtime adapter.

## Existing qualification evidence

- The SDK/runtime delivery record calls the composed path an injected internal message path and says it is not a delivered native transport/bootstrap (`docs/superpowers/verification/2026-09-18-addon-service-subscriptions-host-sdk.md:3-5`). It leaves launcher, authenticated OS transport, physical process death, native parity, and distribution unqualified (`:37`).
- The service documentation states that a production native transport adapter remains separate and that the modeled adapters/exits do not qualify native death (`docs/addons/services.md:18-21,217,239`).
- The generated addon is source-only: no bootstrap, signing, installation, or runtime admission is provided (`CascadeKit/Sources/CascadeAddonTool/ScaffoldCommand.swift:5-6,43`).
- The managed-death/native admission gate is still an unconditional hold with exit 78 (`scripts/test-addon-managed-death.sh:7-12`).

## Smallest feasible next work

Within the file-shelf scope, implement only the public wire models, `FileWorkspaceClient` over `AddonServiceClient`, and host-side `FileWorkspaceService` authorization/revision behavior, with tests through the existing injected/model adapter seam. Record those results as internal/model qualification and leave production mounting blocked.

Unblocking the native requirement is a separate prerequisite, not a small File Workspace patch. It needs, at minimum:

1. a production authenticated bootstrap/launcher admitted by the existing native gate;
2. a production runtime adapter conforming to the cumulative service protocols;
3. a production `AddonServiceMessageChannel` for the SDK side;
4. app wiring that owns `AddonRuntime` and connects both sides;
5. a signed provider using `CascadeAddonSDK`, with observed authorization, revocation, and physical exit on that exact path.

No code, tests, build, app restart, or native fixture execution was performed for this read-only qualification.

## Feature implementation checkpoint

- Isolated checkout `codex/file-shelf`, baseline snapshot `5f8f45c`; the snapshot contains pre-existing work and is not part of the file-shelf implementation diff.
- Public bounded wire values are implemented in commit `eb18b8e`; seven focused contract tests pass. Root reviewed spec compliance and code quality.
- SDK client and internal canonical service boundary are implemented in commit `f402d8c`. Root reviewed the production code and tests and requested two corrections: preserve stable domain errors and sanitize host error text. Both corrections are covered by regression tests.
- No file acquisition, persistent shelf, UI mounting, or FFmpeg conversion is delivered by this checkpoint. Task 1 production qualification remains blocked; tasks 2–9 are not completed.
- The managed launcher hold remains unchanged. This verification record does not qualify native transport, process exit, or production availability.

## Final checkpoint verification

- Root ran `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test --package-path CascadeKit --filter FileWorkspace` after the final code commit: exit 0, 21 tests passed (7 contracts, 4 client, 10 authority).
- Implementer ran the existing `ServiceBrokerTests`: 22 passed. The full package run reproduced the baseline failure in `controlDragKeepsExpandedContentAliveUntilMouseUp` at `NotchControllerTests.swift:1385`; its focused rerun passed. The full suite is therefore not claimed green.
- Root ran `scripts/build-development.sh` with `CASCADE_DERIVED_DATA=/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeFileShelf`: exit 0, SDK boundary checks and codesign verification passed. `/Applications/Cascade.app` points to that build.
- Cascade was quit, relaunched, and verified at PID 68339 with its executable under the same DerivedData directory.
- Weekly account budget at completion: 2% used, 98% remaining. The requested 80% reserve was preserved.

The worktree remains attached on `codex/file-shelf`. The original checkout was not edited during implementation. The native prerequisite is the blocker for activation; it was not replaced with a privileged in-process path.

## Persistenza interna — 26 settembre 2026

Commit `bbe1144`, implementato da GPT-5.6 Sol e revisionato dal root: manifest POSIX atomico con fsync; gestione dell’incertezza del commit senza eliminare copie potenzialmente referenziate; bookmark con descriptor e scope; un solo writer per lifetime host, close esplicito prima della riapertura; copie gestite e ricevute parziali, pin sovrapposti, quote disco/stato/memoria reali. Test indipendente root: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test --package-path CascadeKit --scratch-path /tmp/cascade-task2-build2 --filter 'FileWorkspace|ResourceGovernorTests'`, exit 0, 39 runtime + 4 SDK + 7 contratti = 50 test.

Limiti: input promesso già completato, ricevitore nativo non implementato; nessun montaggio nella app. I consumer delle consegne devono usare il descriptor lease. Identità device/inode/generation conservativa dopo rimontaggio; filesystem senza generation significativa non danno identica protezione dal riuso inode. Dati sconosciuti e cleanup falliti restano preservati e addebitati. Build/riavvio della tranche corrente seguiranno gli altri incrementi indipendenti.

## Componente condiviso — 26 settembre 2026

Commit `b8b3756`, implementato da GPT-5.6 Sol e revisionato dal root. Schema contenuti3 con opt-in esplicito; compatibilità1/2 e glass lights preservata; descrittori azione immutabili, asset dichiarati e rimappati in archivio. Renderer comune con fan4/+N, lista paginata, transizioni finite e Riduci movimento, comandi nativi, input/freccia/risultati distinti e avanzamento reale.

Verifica root: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test --package-path CascadeKit --filter 'FileWorkspace|ProtocolAdmissionTests|GlassLightTests|ContentValidationTests|ActionAuthorizerTests'`, exit0, 48 runtime +17 presentation +21 contracts =86 test. Root ha ispezionato le PNG prodotte da NSHostingView/NSWindow in `/private/tmp/cascade-file-shelf-preview/`; corrette righe oltre il bordo, titoli sovrapposti, gruppi sopra la freccia, anteprime erroneamente attribuite ai risultati e comando Convert ambiguo.

Limiti: prova su stati assestati, non su animazioni del notch produttivo; VoiceOver non navigato manualmente. Schema3 non attivato nella app, nessun widget privilegiato o bootstrap abilitato. La prova nativa rimane requisito dei ticket successivi.


## Bundle FFmpeg e consegna della tranche — 26 settembre 2026

Commit `c1c8d51` e correzione `30ba37f`, GPT-5.6 Sol con ricerca preliminare GPT-6 Sol e review personale root. FFmpeg/ffprobe 9.0.2 autenticati prima della compilazione con SHA-256, fingerprint e firma ufficiale. Helper thin arm64, target macOS14, nessuna dipendenza Homebrew nel bundle; H.264 VideoToolbox/AAC/FLAC/PCM disponibili, MP3 escluso. Sorgenti di build, manifest, licenze e istruzioni riproducibili in `docs/third-party/ffmpeg.md`; binari generati esclusi da Git. Nessuna qualifica Intel.

Root ha corretto in review sostituzioni di cartelle output non sicure, quoting dei percorsi e policy del verifier. Suite shell finale exit0: dieci rifiuti attesi, fixture reali su percorsi ordinari/con spazi e sotto sandbox. La prima build Xcode ha rilevato il limite degli output literal nella sandbox; la correzione sposta lo scratch nel TEMP_DIR già autorizzato del target e mantiene la sandbox abilitata. Log `root-ffmpeg-tests.log` nel ledger SDD.

La suite Swift completa comprende 1.374 test: 861 runtime,121 presentation,273 appkit,102 contracts,17 SDK. Ha riprodotto un solo errore intermittente preesistente, `controlDragKeepsExpandedContentAliveUntilMouseUp` in `NotchControllerTests.swift:1385`; ripetizione isolata passata. I test nuovi passano, ma la suite completa non è dichiarata verde. Log `root-full-suite.log` e `root-known-drag-rerun.log` nel ledger SDD. Nessun cambiamento Swift successivo a questa esecuzione.

Build finale root `CASCADE_DERIVED_DATA=/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeFileShelf /bin/zsh scripts/build-development.sh`: exit0, controllo confini SDK e firma completa riusciti. Verifier eseguito anche su `Cascade.app/Contents/Helpers/FFmpeg --require-signature`: conversione H.264/AAC leggibile da ffprobe. App e due helper firmati con lo stesso TeamIdentifier; licenze in `Contents/Resources/ThirdParty/FFmpeg`, nessuna copia duplicata. `/Applications/Cascade.app` aggiornato alla build verificata. Processo precedente 68339 chiuso, nuovo processo 27461 avviato e verificato con eseguibile nella directory CascadeFileShelf.

Wayfinder: ticket 78/80/81 risolti. Restano aperti 77/79/82/83/84/85, dipendenti dalla qualifica nativa 19/22; nessun percorso privilegiato o launcher abilitato. La UI condivisa è stata verificata in preview, non montata nella app. Il ripiano completo e i job di conversione non sono quindi ancora utilizzabili in produzione. Quota settimanale finale 7% usata/93% residua, sopra la riserva 80% richiesta. Worktree conservata, checkout originale non modificato.


## Formati e avanzamento — prosecuzione del 26 settembre 2026

Commit `5c53ae5`, GPT-5.6 Sol, review personale root per conformità e qualità. Il componente interno non effettua I/O né avvia processi: trasforma telemetria e metadati ffprobe in osservazioni e preset chiusi. Riga massima 4096 byte, documento 64 KiB, 32 tracce e 32 ingressi; nessuna cronologia crescente. Copertine e disposizione video assente non qualificano MP4. La durata esclude tracce non selezionate; il marcatore finale non rappresenta il successo del job. Le correzioni sono incluse nei 15 test mirati.

Verifica indipendente root: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test --package-path CascadeKit --filter 'FileWorkspace|FFmpegProgressTests|FFmpegMediaPlanningTests'`, exit0, 64 test passati (44 runtime, 9 presentation/SDK, 11 contratti). Log `root-task6a-tests.log` nel ledger. La suite completa non è stata ripetuta per questo incremento circoscritto; il precedente errore intermittente del drag non viene dichiarato risolto.

Build `scripts/build-development.sh` con DerivedData CascadeFileShelf riuscita, controllo confini SDK e firma completa passati, helper verificati dalla fase Xcode. Log `task6a-app-build.log`. Link Applications aggiornato, vecchio processo27461 chiuso e nuovo processo34695 verificato nella stessa build. Nessuna modifica al launcher, al gate, al trasporto o alla composizione produttiva. Il ticket dei job completi resta aperto con dipendenza nativa; non viene qualificata alcuna conversione del ripiano.

Durante il checkpoint Git un pack del checkout originale su iCloud ha restituito un timeout; la successiva lettura dell’oggetto e `git verify-pack` sono riuscite. Nessuna riparazione/repack eseguita. Worktree conservata e pulita dopo i commit. Quota settimanale osservata7% usata/93% residua, riserva80% rispettata.

## Primo incremento locale — verifica finale

L'[eccezione approvata](../specs/2026-09-26-file-shelf-design.md#9-inserimento-in-cascade) permette una pagina ripiano direttamente integrata nell'app; non qualifica il launcher addon esterno né la conversione completa. Questa sezione registra prove solo quando osservate dal root.

| Verifica | Stato ed evidenza |
| --- | --- |
| Host locale, consegna per voce | **Accettato**: commit `a0508ef`, review root con correzioni; 73 test indipendenti passati (53 runtime, 9 presentazione, 11 contratti), log SDD `root-task87-tests.log`. Nessuna consegna app da questo solo commit. |
| Review root della pagina e del drag in ingresso (ticket 88) | **Accettato**: commit `ec14e70`, review root e 71/71 test mirati passati (`root-task88-tests.log`). Filtro combinato 139/140 con un test drag intermittente preesistente; nessuna qualifica nativa finale da questa prova. |
| Review root della composizione e del drag in uscita (ticket 89) | **Accettato**: commit `e25e75c`, incluse le correzioni per errore parziale persistente e rifiuto visibile. Il solo `drag-ended` non è una ricevuta; il callback di copia riuscita per singola promise può arrivare dopo e rimuove soltanto quella voce. |
| Suite completa dopo la composizione | **Passata sulla build finale**: verifica indipendente root `swift test --package-path CascadeKit --no-parallel`, exit 0, 1.443/1.443 (885 runtime, 122 presentazione/SDK, 317 CascadeKit, 102 contratti, 17 CLI), log SDD `root-receiver-persistent-tests.log`. |
| Test app firmati | **Passati sulla build finale**: 7/7 test indipendenti root, log SDD `root-shelf-clear-app-tests.log`. |
| Build firmata e controlli SDK/firma | **Passati**: build finale exit 0 (`root-receiver-persistent-build.log`), controlli dei confini SDK e firma superati. |
| Correzione drag del ticket 91 | **Review sorgente root passata** nel commit `5718621` dopo fix di hold, hit testing, area espansa, registrazione opt-in, uscita stantia e pulizia. Test mirati agente 26/26. La prova manuale sulla build PID 59537 ha ancora fallito ingresso e Mission Control; l'utente riferisce che l'area ampliata migliora l'uso. Guardia Quartz pubblica: banda orizzontale del ripiano, arretrata verticalmente di 2 punti dal bordo superiore, dopo URL regolari validati; se mancano permessi, fallisce aperta senza prompt. Nessuna garanzia macOS 27 senza prova. |
| Build della correzione drag | **Passata**: `BUILD SUCCEEDED`, exit 0 (`root-drag-regression-build.log`); controllo confini SDK, firma e collegamento Applications verificati. |
| Ammissione precoce del pannello | **Sorgente revisionato, prova utente fallita** in `c43b7af`: pannello candidato su gesto file riconosciuto, ma solo `NSDraggingInfo` nativo ammette file. Suggerimento globale stabile di 1–32 URL regolari usato solo per UI/guardia, non lettura o copia; fallback hover durante apertura e `mouseUp` fisico contro armamento tardivo. Candidatura sull'intera fascia superiore durante drag file può coprire altri drop della barra menu; mouse ordinario invariato. |
| Build dell'ammissione precoce | **Passata**: `BUILD SUCCEEDED`, exit 0 (`root-early-intake-build.log`); confini SDK, codesign e symlink Applications verificati. |
| Registrazione nativa del pannello | **Review e test passati, prova manuale fallita**: commit `43e83eb`, registrazione `NSPanel` e inoltro limitato allo stesso host; diagnostica delle guardie, senza dichiarare una correzione Mission Control. Agente 18/18 test mirati; root 1.436/1.436 test completi. Build firmata `BUILD SUCCEEDED`, exit 0 (`root-window-destination-build.log`), confini SDK, codesign e link Applications verificati. |
| Ricevitore finale e pagina occupata | **Codice revisionato e compilato, QA utente pendente**: commit `5d852e7`, pin visuale conservato e ricevitore nello Space attivo con inoltro allo stesso host; review root di 12 file e correzioni per ownership asincrona, cache pagina, preview, uscita e coordinate. Build firmata exit 0 (`root-receiver-persistent-build.log`), confini SDK/codesign/link verificati. Nessuna qualifica del drag o di Mission Control sulla soluzione finale senza nuova prova. |
| Collegamento `/Applications/Cascade.app` alla build corrente | **Verificato**: symlink a `/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeFileShelf/Build/Products/Debug/Cascade.app`. |
| Chiusura, riavvio e verifica PID/percorso eseguibile | **Verificato sulla build finale**: vecchio PID 69502 chiuso e assente; rilancio da `/Applications/Cascade.app` al PID 74874 il 26 settembre 2026 alle 23:12:31, eseguibile `CascadeFileShelf/Build/Products/Debug/Cascade.app/Contents/MacOS/Cascade`. Readiness ricevitore alle 23:12:32.100: `registered=3`, `activeSpace=true`, `visible=true`. |
| Finder: ingresso e uscita, copie leggibili e originali conservati | **Ingresso fallito sulla build `43e83eb`/PID 68100**: prova utente 22:49:13–14 senza callback nativi, primo drag con 23 eventi drag e 0 clamp, chiusura al `mouseUp`. Nelle prove precedenti Finder sottostante proponeva «Sostituisci». CUA ha temporaneamente osservato `/private/tmp/cascade-native-drop-qa/Cascade-drop-check.txt` in Finder, poi ScreenCaptureKit `-3812`; Dock `getApp` è scaduto dopo 261 secondi. L'A/B successivo ha ricevuto il drop e l'utente ha visto file nel ripiano; uscita e originali in Finder non verificati. |
| A/B pin della finestra | **Routing nativo verificato solo nell'A/B**: la sola omissione temporanea di `windowPinner.pin(panel)` nel PID 69502 ha fatto arrivare `entered`/`updated`/`hover` dalle 22:56:49, `mouseUp` con `nativeHoverHeld=true` alle 22:56:54.397 e drop `accepted=true` per una voce alle 22:56:54.403. `accepted` indica intake, non persistenza. Utente conferma comparsa dei file; manifest autorevole `entries=1`, `revision=3`. Il conteggio file gestiti esclude originali esterni, quindi zero non indica ripiano vuoto. Soluzione finale che conserva il pin visuale e usa un ricevitore separato ancora senza QA. Mission Control non qualificato. |
| Diagnostica ingresso nativo | **Prova manuale ricevuta, ingresso ancora fallito**: PID 61289 pronto (`enabled=true`, `registered=3`, `windowAttached=true`). Alle 21:56:24.969 `begin` con `panelReady`, `ignored=true`, puntatore fuori dal pannello e `intake=false`; alle 21:56:25.579 `intakeWindowReady` con `ignoredPreviously=true`, `intake=true`; al `mouseUp` 21:56:27.859 `nativeHoverHeld=false`. Seconda prova 21:56:29–30 identica; nessun `nativeEntered`/`rawUpdated` né consegna. Attivazione tardiva candidata, da confermare con la nuova prova. Log `.notice` nel log unificato, prima cattura `/private/tmp/cascade-file-drop-diagnostic.log`. |
| Drag annullato, destinazione che rifiuta e consegna parziale | **Pending**: non verificati nel Finder. Il callback promise individuale resta il criterio di rimozione, non `drag-ended`. |
| Ripiano persistente dopo riavvio | **Manifest verificato, UI pendente**: `entries=1`, `revision=3` sopravvive al riavvio finale; screenshot CUA mostra la finestra ricevente trasparente, non il ripiano aperto. |
| Pagina predefinita occupata e navigazione manuale preservata | **Pending**: la richiesta utente di ripiano principale, Svuota e carte semplificate è implementata in `5d852e7` e testata, ma non osservata nel notch reale; risposta alla prova manuale pendente. |
| VoiceOver/accessibilità e Riduci movimento nel notch reale | **Pending**: test unitari Riduci movimento passati, nessuna prova manuale nel notch aperto. |

I ticket locali 91, 92 e 90 restano aperti: soluzione finale revisionata, testata, compilata e riavviata; la prova utente del nuovo drop e della UI del ripiano non è ancora arrivata. Lo screenshot della finestra ricevente trasparente non qualifica la UI. Le file promise in ingresso e Converti non sono disponibili. I ticket addon esterni 77/79/82/83/84/85 restano aperti. Riserva settimanale residua osservata: 89%.

## Revisione del 27 settembre — build `48e682c`

Implementazione con tre subagenti GPT-5.6 Sol, review e correzioni indipendenti del root. Il limite del ripiano usa `NotchConfiguration.expandedHeight`: configurazione corrente 440×144 pt esterni, contenuto 400×124 pt. Il contesto espone l'ostruzione centrale in coordinate SwiftUI; il ricevitore ammette un drop nativo già validato anche prima dell'espansione. Priorità del ripiano e apertura permanente sono ora separate.

Il renderer usa icone Finder senza fondi, ingresso centro→sinistra→ventaglio, fila orizzontale con ritorno, selezione, paginazione e menu contestuali. Converti/Svuota sono solo nella vista del mazzo. Glow sul percorso nativo `notchGlassLights`, icona centrale di drop con Magic Replace e fallback; movimento e trasparenza ridotti rispettati. Root ha corretto geometria centrale, verso del ventaglio, cancellazione/completamento della sequenza, token monotoni e rimosso la vecchia lista verticale.

Verifiche indipendenti: suite SwiftPM finale exit 0, 1.447/1.447 (885 runtime, 124 presentazione, 319 CascadeKit, 102 contratti, 17 CLI), `root-final-tests.log`; test app firmati exit 0, 9/9, `root-final-app-tests.log`; build firmata exit 0 con `BUILD SUCCEEDED`, confini SDK/codesign/link Applications verificati, `root-build.log`. Log in `.superpowers/sdd/2026-09-27-shelf-design/`. Preview PNG native di 1/4/5 file e fila orizzontale esaminate dal root a 400×124 pt; sono verifiche del renderer, non una cattura del notch fisico.

Dopo Quit, nessun processo Cascade rimasto (`pgrep` exit 1). Rilancio verificato al PID 97319, 27 settembre 2026 15:26:52, dal bundle `CascadeFileShelf/Build/Products/Debug/Cascade.app`; `/Applications/Cascade.app` punta alla stessa build. Ricevitore pronto con tre tipi, Space attivo e finestra visibile. CUA continua a selezionare la finestra ricevente trasparente: la prova reale di drag veloce, gesto e resa nel notch resta richiesta all'utente. Nessuna nuova qualifica di Mission Control. Quota osservata 13% usata, 87% residua.
