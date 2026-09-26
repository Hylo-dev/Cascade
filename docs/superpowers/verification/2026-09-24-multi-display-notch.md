# Verifica del notch multi-display

Esecuzione: 25–26 settembre 2026. Ambito: [specifica](../specs/2026-09-24-multi-display-notch-design.md), [piano](../plans/2026-09-24-multi-display-notch.md) e [contratti attuali](../../architecture/live-activity-contracts.md).

## Ambiente e confini

Host osservato: macOS 27.0, build 26A5425a; Xcode 27.0, build 27A5252f, selezionato tramite `/Applications/Xcode-beta.app/Contents/Developer`. Il deployment target macOS 14 non dimostra compatibilità runtime su macOS 14, non disponibile in questa sessione. Inventario fisico: solo Color LCD integrato, principale e online, mirroring disattivato. Nessun display esterno disponibile.

I test Swift Package usano `/private/tmp/cascade-multidisplay-build`, cache `/private/tmp/cascade-clang-cache` e `/private/tmp/cascade-swiftpm-cache`. La prima build baseline in `.build` dentro iCloud era bloccata dalla firma/resource fork; lo scratch esterno evita quella condizione. Il working tree `codex/interactive-notch` resta senza commit e conserva le modifiche Addon concorrenti. Le snapshot per task, anziché HEAD, definiscono i diff revisionati.

Il probe AppKit pubblico eseguito dal controller vede `screens=0 main=nil` nel sandbox e `screens=1 main=Built-in Retina Display` nella sessione grafica con escalation. Questo giustifica l'ambiente dei test nativi, senza qualificare il comportamento multi-monitor.

## Test automatici

### Lifecycle e scadenza su tre display

`NotchDisplayCoordinatorTests.threeDisplayCopiesShareOneLifecycleAndExpiry` usa tre superfici finte, l'host reale condiviso e il suo clock iniettato. Verifica tre factory dopo una sola attivazione, tutte le copie della stessa istanza, passaggi tutti → focus → tutti senza nuove superfici né sospensione intermedia, quindi una riconciliazione di scadenza che svuota ogni copia con una sola sospensione. Una seconda riconciliazione non cambia proiezioni o conteggi.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cascade-swiftpm-cache \
swift test --disable-sandbox --package-path CascadeKit \
  --scratch-path /private/tmp/cascade-multidisplay-build \
  --filter 'NotchDisplayCoordinatorTests|LiveActivityHostTests'
```

Risultato: **exit 0, 82 test in 2 suite passati**. Log: `/private/tmp/task-7-covering-tests.log`. È una verifica del comportamento già implementato: nessun RED artificiale e nessuna modifica al codice di produzione.

La lettura di `Core/Activities/LiveActivityHost.swift` conferma un unico campo `deadlineTask`: `scheduleExpiration()` sceglie la prossima scadenza/stale date, cancella il task precedente quando cambia il termine e richiama `expireNotices()`. Il test invoca direttamente la riconciliazione col clock avanzato: non conta risvegli reali del sistema né dimostra un profilo energetico.

### Integrazione finale

La baseline precedente alle modifiche, fuori iCloud, è **exit 1**: 1.222 test, 16 issue runtime Addon e un timeout/assertion `controlDragKeepsExpandedContentAliveUntilMouseUp` nel controller. Log completo: `/private/tmp/cascade-multidisplay-baseline-clean.log`; elenco esatto conservato in `baseline-test-issues.txt` nel dossier SDD. I conteggi delle issue non equivalgono al numero di test falliti.

**Full-package finale dopo la correzione della revisione complessiva: exit 1, 1.325 test su cinque target**, log `/private/tmp/cascade-multidisplay-final-package-after-review.log`. Eseguito dal controller nella sessione grafica: nessun crash da `NSScreen` assente. I rerun diagnostici isolati descritti sotto non cambiano questo esito del run completo. Il precedente run integrato, prima di questa correzione, aveva 1.323 test e sette issue totali (`/private/tmp/cascade-multidisplay-final-package.log`); resta evidenza storica separata.

| Target/gruppo | Esito finale | Confronto con la baseline |
| --- | --- | --- |
| Runtime Addon | 832 test; 19 issue | 13 issue ripetono casi della baseline; altre 6 appartengono a `brokerPublicationWaitsForTheBlockedPhysicalObservation`, che passava nella baseline. Questo secondo caso passa isolato; causa esatta non dimostrata. |
| Addon | 112 test passati | Nessun fallimento |
| CascadeKit | 272/273 passati; un'issue in `controlDragKeepsExpandedContentAliveUntilMouseUp` | Stessa assertion `fixture.controller.state == .closed` della baseline (ora riga 1385, prima 1012). Ricorrenza dello stesso sintomo; non rende verde la suite. |
| Altri target | 91 + 17 test passati | Nessun fallimento |

Le sei issue del caso broker sono registrate in `ServiceBrokerCPUAttributionTests.swift` alle righe 314 e 286: un `Acquisition task did not start` e cinque `Observation release timed out`. Non sono sei test distinti. Il test usa `DispatchSemaphore` con timeout di due secondi dentro lavoro asincrono. La suite isolata `ServiceBrokerCPUAttributionTests` passa **8/8, exit 0, 0,032 s**, log `/private/tmp/cascade-multidisplay-final-runtime-isolation.log`. Anche il controller isolato passa **1/1, exit 0, suite 0,344 s**, log `/private/tmp/cascade-multidisplay-final-drag-isolation.log`.

Il controller ha confrontato byte per byte con la snapshot baseline `Package.swift`, il test ServiceBroker e i quattro moduli runtime (61 file), contracts (58), presentation (6), SDK (14): identici, senza file aggiunti/rimossi. Il target runtime non dipende da CascadeKit/app. Il fallimento runtime è quindi **nuovo nel run, in moduli immutati, non riprodotto isolatamente**. Contesa/scheduling è una spiegazione plausibile, non una causalità dimostrata. Non sono stati modificati quei moduli/test né indebolite asserzioni per ottenere il verde. Il run completo resta exit 1.

**Settings finali: 17/17 passati, exit 0, TEST EXECUTE SUCCEEDED**, log `/private/tmp/cascade-multidisplay-final-settings-prebuilt.log`. Il controller ha eseguito nella sessione grafica il bundle finale già compilato e firmato Apple Development durante le due regressioni del fix round 3:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project Cascade.xcodeproj -scheme Cascade \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/cascade-task6-fix3-derived \
  test-without-building -only-testing:CascadeTests/SettingsTests
```

Questo test runtime finale sostituisce l'evidenza parziale precedente di 15 test pre-fix e due regressioni finali. Non ricompila il bundle e non costituisce la build finale di consegna. I timeout di approvazione dei tentativi precedenti impedivano il lancio dei comandi: non erano rifiuti di sicurezza né errori di compilazione/firma.

Le verifiche precedenti costituiscono evidenza circoscritta: Task 5, 103 test/6 suite di geometria e transizioni; Task 6, 44 test del coordinatore e copertura Spotlight riportata nel dossier. Non si sommano questi conteggi alle suite finali, perché si sovrappongono. La revisione finale Task 6 è PASS/PASS dopo tre correzioni scoped.

### Correzione conclusiva della transizione fra istanze

La revisione complessiva ha riprodotto una sostituzione della stessa attività A→B nella quale A era ancora montata ma non ancora registrata come uscente. La union precedente poteva sospenderla e revocarne l’eligibilità troppo presto. Ora il controller espone le radici correnti e uscenti; il coordinatore riconcilia il lifecycle prima delle factory e nuovamente dopo l’applicazione. L’applicazione identica durante il ritorno alla sagoma compatta è idempotente.

Le due regressioni col controller reale partono da A effettivamente montata, senza predisporre artificialmente la retention: animazione e Riduci movimento passano 2/2 dopo il RED registrato. La prova aggiornata del coordinatore passa 1/1 e controlla attivazione prima della factory e un solo rilascio finale. Log: `/private/tmp/final-fix-red-mounted-handoff.log`, `/private/tmp/final-fix-green-mounted-handoff.log`, `/private/tmp/final-fix-green-coordinator-handoff.log`. Il run pertinente di 172 test ha unicamente la stessa failure di trascinamento documentata (`/private/tmp/final-fix-covering-tests.log`); il successivo full-package sopra verifica il sorgente integrato corretto. Nessuna asserzione è stata indebolita.

I 17 Settings test verificano il sorgente finale di impostazioni/Spotlight, rimasto invariato durante questa correzione al controller/coordinatore; la correzione al nucleo è coperta dai nuovi test e dal nuovo run completo. La revisione scoped conclusiva è **PASS/PASS**, con finding I1 risolto e nessuna regressione causata dal fix rilevata (`final-rereview-1.md`). La build aggiornata è riuscita e la verifica nativa disponibile è riportata sotto.

## Matrice di verifica fisica

I fake provano routing, selezione, ownership e lifecycle; non provano stacking di finestre AppKit, desktop effettivamente visibile o comportamento hardware. Il PNG prodotto dal percorso reale di rendering `software-notch-comparison.png` è stato ispezionato con esito PASS per entrambi gli stili a riposo, metà e piena apertura, con/senza attività. Rimane evidenza geometrica sintetica.

| Prova richiesta | Evidenza disponibile | Stato nativo |
| --- | --- | --- |
| Hardware + esterno, nessuna attività, due stili | Inventari finti e PNG del renderer | Non verificato: esterno assente |
| Due schermi senza taglio fisico, stili indipendenti | Routing/stili e geometria sintetici | Non verificato: hardware assente |
| Tutti, due attività, apertura su A e copie su B | Test coordinatore/host, selezione compatta separata | Non verificato su display fisici multipli |
| Focus finestra A, mouse B, apertura locale widget | Resolver e routing con input iniettati | Non verificato su display fisici multipli |
| Movimento/cambio finestra nella stessa app | Monitor/resolver e pannelli finti stabili | Non verificato su display fisici multipli |
| Specifico B, disconnessione/riconnessione UUID | Test inventario/routing | Non verificato: esterno assente |
| A aperto, richiesta B poi C, annullamento hover | Test di handoff/generazioni/richiesta ancora valida | Non verificato su tre display fisici |
| Arrivo/scadenza durante morph | Test transizioni e nuovo test expiry condivisa | Non verificato durante morph nativo |
| Lock/unlock e stop/start | Test di lifecycle, invalidazione e ordine di cleanup; quit/relaunch reale completato | Riavvio verificato; lock/unlock nativo non esercitato |
| Coperchio chiuso | Nessuna prova fisica | Non verificato |
| Fullscreen, Spaces, Mission Control | Nessuna sessione nativa esercitata | Non verificato |
| Mirroring | Topologia sintetica normalizzata | Non verificato: mirroring fisico assente |
| Riduci movimento/trasparenza, VoiceOver | Test geometria; path condiviso per fallback visivo | Funzionamento nativo/accessibilità non verificato |
| Impostazioni, popover, Spotlight | Test ownership/ancora; Settings firmati; UI Impostazioni provata sul display integrato | Multi-display non verificato; Spotlight nativo non qualificato per impedimento dello strumento |

## Risorse a riposo e consegna dell'app

Il test a tre display dimostra una sola attivazione e sospensione del provider, senza riallocazione delle superfici al cambio del focus. Il sorgente del controller arresta il morph e l'host possiede uno scheduler condiviso. Il progresso musicale usa `TimelineView` nella vista estesa durante playback non stale; la validità delle radici è coperta dai test host/controller. **Profiling nativo non eseguito**: non è stato misurato il numero di display link o TimelineView attivi a riposo, né CPU, memoria o wakeup. La lettura del sorgente non sostituisce questa misura.

**Build finale e riavvio: completati il 26 settembre.** `scripts/build-development.sh` sul sorgente corretto ha terminato con exit 0 e `BUILD SUCCEEDED`; log `/private/tmp/cascade-multidisplay-final-build-after-review.log`. Il controllo dei confini Addon e la firma deep/strict sono riusciti. Firma Apple Development, team `A6A5HQL6K4`, bundle `hylo.Cascade`. Il collegamento `/Applications/Cascade.app` punta alla build canonica `/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeDevelopment/Build/Products/Debug/Cascade.app`.

L’istanza osservata prima del riavvio aveva PID `14174`. Cascade è stata chiusa, riaperta e infine avviata con la propria opzione `--open-settings` per la prova UI. Il processo finale verificato ha PID **39220** e usa esattamente `CascadeDevelopment/Build/Products/Debug/Cascade.app/Contents/MacOS/Cascade`; una lettura finale del collegamento conferma la stessa destinazione. Nessun codice dell’app è cambiato dopo questa build.

Sul display integrato la sagoma hardware chiusa è visibile. Nella finestra nativa Appearance sono presenti la riga Built-in Retina Display con stato “Notch hardware” e i tre controlli Live Activities. Sono stati selezionati “Tutti gli schermi” e “Schermo specifico”; quest’ultimo mostra il selettore con nome e UUID del display integrato. È stata ripristinata e verificata la preferenza iniziale **Segui il focus**. Le ricerche “Dynamic Island” e “activity” restituiscono i controlli pertinenti. Impostazioni resta utilizzabile e si chiude regolarmente. Queste osservazioni qualificano solo il display disponibile, non routing o stacking fisico multi-monitor.

La prova nativa Spotlight non è stata completata. Dopo il comando di apertura, CUA non ha potuto aprire/osservare `com.apple.Spotlight`: LaunchServices/RBS ha restituito `Launch failed` (RBS code 5, errore POSIX 162); l’inventario disponibile allo strumento non esponeva Spotlight/Campo. Non sono stati osservati apertura, digitazione e chiusura del campo nativo, quindi non se ne dichiara il successo né si attribuisce l’impedimento al codice Cascade. I test di stato e integrazione restano l’evidenza disponibile.

La build e il riavvio riusciti non qualificano da soli il multi-monitor. Profiling, VoiceOver, preferenze di accessibilità native, lock/unlock, Spaces/fullscreen e runtime macOS 14 rimangono nei limiti dichiarati sopra.

## Evidenze conservate

Il dossier locale `.superpowers/sdd/2026-09-24-multi-display-notch/` contiene `final-verification-results.md`, `progress.md` con i rulings, report/review per task, snapshot sorgente e `software-notch-comparison.png`. I percorsi `/private/tmp` identificano i log effettivamente prodotti su questo host e non sono artefatti portabili garantiti. Le osservazioni finali del controller sono integrate sopra; le combinazioni non eseguite restano esplicitamente non qualificate.
