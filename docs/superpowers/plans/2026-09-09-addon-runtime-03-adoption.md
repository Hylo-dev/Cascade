# P3 — Integrazione e widget del team

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Portare i widget Cascade sul percorso pubblico, provando contenuti autonomi, servizi condivisi e scene SwiftUI remote nell'app reale.

**Architecture:** La composizione dell'app registra pacchetti nel catalogo. I provider pubblicano valori attraverso l'SDK; un bridge generico collega il runtime al notch. Le integrazioni macOS diventano servizi del broker.

**Tech Stack:** Prodotti Swift di P1/P2, SwiftUI, launcher e scene remote verificati in P0, target addon firmati e script di regressione esistenti.

**Spec:** [architettura](../specs/2026-09-09-addon-runtime-design.md); [piano principale](2026-09-09-addon-runtime.md).

## Global Constraints

Valgono tutti i vincoli del piano principale. Prerequisiti: P1/P2 verificati; per le scene remote anche 00.3. Nessun widget del team ha quote speciali o un executor in-process di produzione. Preservare comportamento, privacy, accessibilità e interazioni esistenti. Ogni task che modifica l'app termina con build, aggiornamento del collegamento in /Applications, riavvio verificato e rapporto.

## Task 03.1 — Composizione dell'app e Clock sul percorso pubblico

**Files:** creare Cascade/Addons/BundledAddonCatalog.swift, Cascade/AddonRuntimeComposition.swift; Addons/Clock/Manifest.json, ClockProvider.swift, Info.plist e file di firma previsti dal formato scelto in P0; CascadeKit/Tests/CascadeRuntimeIntegrationTests/BundledClockTests.swift; scripts/check-addon-boundaries.sh. Modificare Cascade/CascadeServices.swift, Cascade.xcodeproj/project.pbxproj e il bridge di P1. Migrare e poi rimuovere Cascade/Features/ClockWidget.swift quando non ha più utilizzatori.

**Interfaces:** `BundledAddonCatalog.entries() throws -> [InstalledAddon]` restituisce metadati di pacchetti verificati, non factory di widget. AddonRuntimeComposition collega catalogo, servizi, runtime e AddonPresentationBridge. ClockProvider implementa AddonProvider e produce una Publication con componente temporale clock; nessun tick IPC.

- [ ] Scrivere BundledClockTests: abilitare Clock, ricevere una pubblicazione, attendere l'uscita normale del provider e verificare che l'orologio rimanga valido; disabilitarlo deve rimuovere anche azioni e stato. Controllare che il PID del provider sia diverso dall'host.
- [ ] Collegare i prodotti del package e creare il target addon secondo P0. La sua origine bundled cambia la discovery, non identità autenticata, handshake, permessi o ResourcePolicy. Anche gli aggiornamenti futuri del Clock passano dal normale catalogo.
- [ ] Sostituire la registrazione diretta `notch.register(ClockWidget())` con l'abilitazione del pacchetto Clock. Il bridge non conosce ClockProvider e non sceglie viste attraverso switch su AddonID.
- [ ] Creare check-addon-boundaries.sh per verificare il grafo delle dipendenze package e gli import dei target addon: vietati CascadeKit, CascadeRuntime, API del notch e integrazioni private. Elencare temporaneamente soltanto i file legacy esistenti ancora da migrare nei task successivi; una nuova eccezione deve fallire la verifica.
- [ ] Verificare clock, calendario/locale, cambio fuso orario, sleep/wake e ritorno dopo lunga chiusura del notch. La presentazione temporale si aggiorna nell'host quando necessaria; nessuna coda di tick arretrati e nessun loop addon mentre è nascosta.
- [ ] Eseguire BundledClockTests, AddonPresentationTests introdotti in P1 e check-addon-boundaries.sh; eseguire build/riavvio e registrare confronto visivo e consumi con il Clock precedente; commit limitato al task.

## Task 03.2 — Timer autonomo e primo progetto esterno

**Files:** creare Addons/FocusTimer/Manifest.json, FocusTimerProvider.swift, FocusCore/FocusSession.swift; Examples/StandaloneFocus/Package.swift, README.md, Sources/StandaloneFocusProvider/ e progetto/contenitore firmato richiesto da P0; CascadeKit/Tests/CascadeRuntimeIntegrationTests/StandaloneFocusTests.swift; scripts/test-addon-standalone.sh.

**Interfaces:** FocusSession è una libreria di valori indipendente dall'app sorgente: ID, stato, deadline e revisione. Il provider usa azioni start/pause/resume/end identificate da stringhe stabili e pubblica il countdown SDK. Il pacchetto di esempio include le funzioni usate; non cerca librerie nell'app sorgente.

- [ ] Scrivere un test di sessione start → uscita provider → avanzamento dell'orologio controllato → pause con nuovo provider → resume → scadenza. Verificare revisioni e un solo evento finale, senza processo vivo per ciascun secondo del timer.
- [ ] Condividere FocusCore fra esempio di app sorgente e addon tramite dipendenza di build. Costruire il contenitore autonomo in una directory temporanea usando soltanto i prodotti pubblici SDK; l'esempio non importa sorgenti del repository tramite percorsi relativi nascosti.
- [ ] Il timer deve funzionare con app sorgente chiusa e con app sorgente mai installata. L'azione facoltativa per aprirla dichiara appInstalled e rimane indisponibile quando manca; non blocca start/pause/end e non apre/installa nulla automaticamente.
- [ ] Registrare la deadline nel runtime con un evento pianificato: distinguere l'aggiornamento visivo del countdown dall'esecuzione della funzione alla scadenza. Dopo sleep oltre la deadline consegnare un evento scaduto una sola volta; nessuna raffica di recupero.
- [ ] Provare rifiuto del permesso, disabilitazione, host chiuso, file di stato corrotto e scadenza mentre il processo è assente. Se l'host era chiuso, applicare la policy di ripristino senza promettere lavoro eseguito in sua assenza o ripetere un avviso passato.
- [ ] Eseguire StandaloneFocusTests e `/bin/zsh scripts/test-addon-standalone.sh`; salvare PID, firma, assenza dell'app sorgente e log delle azioni nel rapporto. Build/riavvio dell'app quando modificata; commit.

## Task 03.3 — Avvisi di sistema e Bluetooth attraverso i servizi comuni

**Files:** creare Addons/SystemNotices/Manifest.json, ChargingProvider.swift, VolumeProvider.swift, BluetoothProvider.swift e relative risorse; Cascade/Addons/SystemServiceRegistration.swift; CascadeKit/Tests/CascadeRuntimeIntegrationTests/SystemNoticeAddonTests.swift, SharedSystemServiceTests.swift. Modificare Cascade/Integrations/Power/, Volume/, Bluetooth/, CascadeServices.swift e migrare Cascade/Features/ChargingNotice.swift, VolumeChangeNotice.swift, BluetoothConnectionActivity.swift e relativi helper/risorse.

**Interfaces:** Registrare versioni esplicite dei servizi system.power, system.volume e system.bluetooth. Eventi di servizio sono valori limitati; azioni di modifica e lettura hanno scope distinti. Un adapter per sorgente viene condiviso da tutti i consumatori con concessioni compatibili. I provider pubblicano famiglie notice/activity del contratto comune.

- [ ] Prima della migrazione eseguire e registrare le regressioni disponibili per alimentazione, volume, Bluetooth, presentazione e instradamento audio Bluetooth. Salvare le aspettative di privacy, durata, priorità, revisione ed etichette accessibili; la migrazione non è una riprogettazione visiva.
- [ ] Scrivere SharedSystemServiceTests: due addon richiedono lo stesso monitor, una sola sorgente reale viene avviata; la revoca di un consumer non interrompe l'altro; l'ultimo rilascio ferma la sorgente. Nessuna seconda sottoscrizione creata in CascadeServices dopo l'adozione del broker.
- [ ] Separare sottoscrizione di interesse gestita dall'host e connessione al provider: una connessione chiusa per inattività non impedisce al broker di risvegliare l'addon su un evento ammesso. Disabilitazione e revoca eliminano anche l'interesse. Il monitor resta attivo soltanto finché esiste una domanda autorizzata e viene contabilizzato.
- [ ] Migrare i tre provider e mantenere l'abilitazione per feature. Una dipendenza Bluetooth assente blocca Bluetooth senza rendere indisponibili avvisi di alimentazione e volume. Risorse/localizzazioni vengono incluse nel pacchetto, non recuperate da un percorso privato dell'host.
- [ ] Se i componenti ordinari non rappresentano un comportamento esistente, estendere lo schema pubblico con un componente limitato e testato oppure usare la scena remota di 03.4. Non introdurre una factory privata. Per le sequenze di immagini esistenti, valutare un componente pubblico imageSequence: asset già decodificati, massimo 48 fotogrammi a 96×96, durata 3 s, una riproduzione, arresto quando nascosto o con Reduce Motion; tutti i buffer contano nelle quote. Aggiornare schema, SDK, renderer e test insieme prima dell'uso.
- [ ] Eseguire SystemNoticeAddonTests, SharedSystemServiceTests, LiveActivityHostTests e NotchActivityLifetimeTests. Eseguire `/bin/zsh scripts/test-power.sh`, test-volume.sh, test-bluetooth.sh, test-bluetooth-presentation.sh e test-bluetooth-audio-route.sh dalla stessa cartella scripts con il relativo percorso completo. Verificare AirPods/altro hardware solo se presente e registrare i casi mancanti.
- [ ] Rimuovere le registrazioni dirette e gli adapter legacy ormai inutilizzati; restringere l'allowlist di 03.1. Build/riavvio, confronto visivo/accessibile e commit.

## Task 03.4 — Media e UI SwiftUI remota con durata controllata

**Files:** creare Addons/Media/Manifest.json, MediaProvider.swift, MediaExpandedScene.swift; CascadeKit/Sources/CascadeContracts/Presentation/RemoteSceneDescriptor.swift; Sources/CascadeRuntime/Presentation/RemoteSceneCoordinator.swift e Tests/CascadeRuntimeIntegrationTests/RemoteSceneLifecycleTests.swift, MediaAddonTests.swift sotto CascadeKit; CascadeKit/Sources/CascadeKit/Core/AddonPresentation/RemoteSceneContainer.swift; scripts/test-addon-scenes.sh. Modificare Cascade/Integrations/Media/, Audio/, CascadeServices.swift; migrare Cascade/Features/MediaLiveActivity.swift, MusicArtworkDecoder.swift, MusicPlaybackPresentation.swift, MusicProgressSlider.swift, AudioOutputPicker.swift e relativi helper quando necessari alla scena.

**Interfaces:** RemoteSceneDescriptor dichiara sceneID, PublicationID, versione compatibile e documento ordinario di fallback. `RemoteSceneCoordinator.open(_ descriptor: RemoteSceneDescriptor) async throws -> SceneSession`; `close(_ sessionID: UUID) async`. SceneSession contiene identità verificata e lease di presentazione; il bridge ospita soltanto un controller autenticato restituito dall'adapter di P0. Il messaggio di apertura include un token monouso associato a owner, pubblicazione e generazione, non un endpoint arbitrario fornito dalla UI.

- [ ] Scrivere RemoteSceneLifecycleTests: apertura/chiusura rapida, revoca durante mount, crash della scena, processo lento, risposta di una generazione precedente, resize, cambio display e focus. Al massimo una scena remota; quando nascosta il lease termina, eventuali risorse solo visive si rilasciano e resta il contenuto ordinario valido.
- [ ] Portare in produzione l'adapter dimostrato in 00.3, con isolamento per disponibilità API macOS e fallback. L'interfaccia avanzata usa davvero SwiftUI nel processo dell'estensione; nessun AnyView attraversa il canale. Se il trasporto richiede una vista remota distinta dal provider, entrambi i processi contano nel budget totale dell'addon.
- [ ] Registrare servizi pubblici media.metadata, media.playbackControl e audio.spectrum con scope distinti. Non esporre direttamente controller AppleScript, eventi privati o oggetti di cattura audio: il servizio offre operazioni specifiche autorizzate. Le API macOS utilizzate mantengono i vincoli di compatibilità/TCC della piattaforma.
- [ ] Migrare contenuto compatto, artwork, avanzamento e controlli al modello SDK; tempo di playback rappresentato con base temporale/revisione, senza messaggi per frame. Il renderer usa componenti pubblici per lo stato ordinario; la scena SwiftUI avanzata gestisce le interazioni che ne hanno bisogno, mantenendo un fallback utile.
- [ ] Collegare l'analisi audio a un lease esplicito della superficie visibile. Due consumatori compatibili condividono la cattura; nascondere l'ultima superficie arresta analisi e consegna dei campioni. La lettura degli eventi media ancora necessaria rimane una domanda separata: non collegare tutte le risorse a un unico booleano visible.
- [ ] Usare il profilo continuo inizialmente soltanto nei test di qualificazione, finché 04.3 non ne stabilisce limiti misurati. Frequenza campioni/UI e buffer hanno massimi già controllati nei test; nessuna esenzione del media player del team. Metadati, artwork e account mantengono scope e protezione su schermo bloccato.
- [ ] Eseguire RemoteSceneLifecycleTests, MediaAddonTests, `/bin/zsh scripts/test-addon-scenes.sh` e le regressioni scripts/test-now-playing.sh, test-audio-spectrum.sh, test-music-artwork.sh, test-music-progress.sh. Verificare manualmente VoiceOver, tastiera, menu, trascinamento del progresso, cambio uscita e Reduce Motion; riportare hardware/permessi mancanti.
- [ ] Rimuovere i bypass dei widget migrati e le voci residue della relativa allowlist. Eseguire check-addon-boundaries.sh, build/riavvio, rapporto P3 e commit. Se una funzione preesistente richiede ancora una via privilegiata privata, P3 non è conclusa: estendere il contratto comune e verificarlo.
