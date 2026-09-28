# Multi-display Notch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans, or superpowers:subagent-driven-development if the user selects delegation. Steps use checkbox (`- [ ]`) syntax for tracking. Implementation authorized by the user on 25 September 2026; execute the linked Wayfinder tickets with subagents.

**Goal:** mantenere il notch su ogni display, permettere una sola apertura e distribuire le Live Activities secondo la preferenza dell'utente.

**Architecture:** un coordinatore globale possiede display, focus, routing e ciclo di vita dei contenuti; ogni display ha un controller di presentazione stabile. Rendering e animazioni esistenti vengono riutilizzati. Le copie delle attività condividono identità e sorgente ma hanno viste locali.

**Tech Stack:** Swift 6, macOS 14+, AppKit, Core Animation, SwiftUI, Swift Testing, Accessibility già usata dal progetto.

**Spec:** [2026-09-24-multi-display-notch-design.md](../specs/2026-09-24-multi-display-notch-design.md). Contiene i requisiti confermati e, separatamente, le scelte proposte per completare i casi non specificati.

**Stato:** piano preparato sul working tree del 24 settembre 2026; esecuzione autorizzata il 25 settembre e tracciata nella mappa Wayfinder. Focus confermato: finestra attiva, puntatore come fallback. Esecuzione consigliata in sequenza nello stesso contesto, poiché i task modificano lo stesso contratto fra host e controller.

## Global Constraints

- macOS 14 minimo; Swift 6; AppKit/Core Animation per pannelli e morph, SwiftUI per contenuti.
- Nessuna nuova dipendenza o API privata per questa funzionalità.
- Un solo monitor globale del mouse; niente polling del focus o dei display.
- I display link si fermano a geometria stabile. Gli aggiornamenti di focus non ricreano pannelli.
- Privacy e accessibilità applicate a ogni copia prima delle factory sensibili.
- Calibrazioni hardware esistenti preservate; vecchie calibrazioni software non devono impedire la nuova piccola sporgenza.
- Fine implementazione: test pertinenti, build con `scripts/build-development.sh`, aggiornamento del collegamento `/Applications/Cascade.app`, riavvio e verifica del processo.
- Il working tree contiene numerose modifiche preesistenti, anche nei file interessati. Prima dell'esecuzione acquisirne il diff; non ripristinarle, non includerle indiscriminatamente in commit e non partire da HEAD perdendo lo stato corrente.

## Review Focus

1. La finestra attiva cambia display senza cambiare app, mentre il puntatore resta fermo: il contenuto segue la finestra. Test del task 2.
2. Display fisso scollegato/ricollegato con ID numerico diverso: nessun trasferimento a un altro monitor; ripristino tramite UUID. Test del task 1 e task 7.
3. Apertura su A e copia compatta su B della stessa attività: nessuna doppia attivazione o sospensione prematura. Test del task 3.
4. Due richieste di apertura durante chiusura, trascinamento o callback tardiva: mai due pannelli aperti, ultima destinazione valida. Test del task 4.
5. Sporgenza di 8 pt e vecchia calibrazione di 220 × 32 pt su display senza hardware: contenuti leggibili, separazione di 24 pt, geometria visiva e hit test coincidenti. Test del task 5.

## Stato attuale verificato

Tutti i percorsi seguenti sono relativi alla radice del repository.

| Codice esistente | Conseguenza per la modifica |
| --- | --- |
| `CascadeKit/Sources/CascadeKit/Core/Engine/NotchEngine.swift` | Crea un solo pannello, controller, resolver e monitor. Diventa facciata del coordinatore. |
| `Core/Engine/NotchController.swift` sotto lo stesso modulo | Possiede `LiveActivityHost`, `WidgetHost`, resolver e monitor; `refreshActiveDisplay()` sposta il pannello. Separare orchestrazione globale e rendering locale. |
| `Core/Display/SafeAreaNotchDetector.swift` | Oggi segue il puntatore. Non rappresenta il focus richiesto. |
| `Core/Activities/LiveActivityHost.swift` | `isExpanded` sostituisce la selezione compatta e azzera la secondaria; `isVisible` è globale. Non basta condividere questa istanza fra controller senza modificare il contratto. |
| `Models/Configuration/NotchConfiguration.swift` | Fallback di 220 × 32 pt; un'unica misura usata per riposo e separazione. |
| `Core/Interaction/NotchSizePreferences.swift` | Già risolve identità UUID; riutilizzare questa logica. |
| `Extensions/CGPath+NotchDroplet.swift` | Unisce il satellite laterale alla sagoma; non implementa la nuova goccia verticale. Conservare il percorso esistente. |
| `Cascade/Features/Spotlight/SpotlightDropletLayout.swift` | Layout per campo nativo Spotlight; non usarlo come engine generico della nuova Dynamic Island. |
| `Cascade/Integrations/Spotlight/SpotlightAccessibilityMonitor.swift` | Modello locale di worker AX, generazioni e notifiche da seguire. |
| `Cascade/Features/MediaLiveActivity.swift` e `Core/AddonPresentation/SnapshotActivity.swift` | Conservano un solo contesto/permesso per attività; servono attivazioni condivise, non una per copia. |

Il grafo MCP non contiene un indice di Cascade; questa ricognizione usa il codice del working tree. I percorsi e le interfacce proposte sotto vanno ricontrollati prima di applicare il piano se il codice è cambiato nel frattempo.

## Task 1 — Identità, inventario e preferenze di routing

**Files:** creare `CascadeKit/Sources/CascadeKit/Models/Display/DisplayPresentationPreferences.swift`, `Core/Display/DisplayInventory.swift`, `Core/Display/ActivityDisplayRouting.swift` e `Tests/CascadeKitTests/ActivityDisplayRoutingTests.swift` sotto CascadeKit. Modificare `Core/Interaction/NotchSizePreferences.swift` solo per condividere la risoluzione UUID con l'inventario, senza cambiare le chiavi delle calibrazioni esistenti.

**Interfaces:** `DisplayIdentity` pubblico, `RawRepresentable`, `Hashable`, `Codable`, `Sendable`, con `rawValue: String` e `init(rawValue:)`. `DisplayPresentationPreferences` pubblico con `activityMode: LiveActivityDisplayMode` e `styles: [DisplayIdentity: ExternalNotchStyle]`. I modelli hanno inizializzatori pubblici espliciti.

```swift
public nonisolated enum ExternalNotchStyle: String, Codable, Sendable {
    case notch, dynamicIsland
}
public nonisolated enum LiveActivityDisplayMode: Codable, Equatable, Sendable {
    case allDisplays
    case focusedDisplay
    case fixedDisplay(DisplayIdentity)
}
// Internal pure routing function; no AppKit calls or preferences reads.
static func destinations(
    mode: LiveActivityDisplayMode,
    connected: Set<DisplayIdentity>,
    focused: DisplayIdentity?
) -> Set<DisplayIdentity>
```

- [x] Scrivere il test sotto, che inizialmente fallisce perché i tipi e il resolver non esistono.

```swift
@Test func fixedDisplayDoesNotFallBackWhenDisconnected() {
    let a = DisplayIdentity(rawValue: "A")
    let b = DisplayIdentity(rawValue: "B")
    #expect(ActivityDisplayRouting.destinations(
        mode: .fixedDisplay(a), connected: [b], focused: b
    ).isEmpty)
    #expect(ActivityDisplayRouting.destinations(
        mode: .fixedDisplay(a), connected: [a, b], focused: b
    ) == [a])
}
```

- [x] Eseguire `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path CascadeKit --filter ActivityDisplayRoutingTests`; osservare il fallimento iniziale.
- [x] Implementare `ActivityDisplayRouting.destinations`: tutti → `connected`; focus → singleton se presente in `connected`, altrimenti insieme vuoto; fisso → singleton dell'identità richiesta solo se collegata. La scelta del fallback del focus appartiene al task 2.
- [x] Implementare inventario iniettato dietro `DisplayInventoryProviding`: proprietà `displays: [DisplayInventoryEntry]`, callback `onChange`, metodi `start()` e `stop()`. `DisplayInventoryEntry` contiene `snapshot: ActiveDisplay`, `identity: DisplayIdentity?`, `name: String`. Pubblicare solo cambiamenti di topologia/geometria/scala; una superficie per display logico.
- [x] Usare un unico payload Codable `displayPresentationPreferencesV1` in UserDefaults; impostazione sconosciuta/corrotta → `.focusedDisplay`, stile mancante → `.notch`. Un record valido con UUID offline resta salvato. Trattare gli schermi senza UUID con ID di sessione nel coordinatore per modalità tutti/focus, senza renderli selezionabili come destinazione persistente.
- [x] Aggiungere prove di round-trip Codable, tutti/focus, nessun display, selezione sconosciuta e UUID stabile con nuovo ID numerico; rieseguire il filtro. I test devono controllare i risultati pubblici, non duplicare lo switch interno.
- [x] Registrare il diff della sola tranche; un eventuale commit deve includere soltanto gli hunk della funzionalità.

## Task 2 — Focus della finestra attiva e fallback

**Files:** creare `CascadeKit/Sources/CascadeKit/Core/Display/FocusedDisplayResolver.swift`, `FocusedWindowMonitor.swift`, `Tests/CascadeKitTests/FocusedDisplayResolverTests.swift`. Modificare `Core/Display/SafeAreaNotchDetector.swift`, `Core/Display/ActiveDisplayResolving.swift` e `Core/Events/MouseEventMonitor.swift` eliminando la sovrapposizione fra focus, inventario e puntatore.

**Interfaces:** `FocusedWindowMonitoring` espone `onChange: ((CGRect?) -> Void)?`, `start()` e `stop()`. Il frame pubblicato è già in coordinate globali AppKit. Il monitor concreto osserva l'app esterna in primo piano e la sua finestra; il resolver puro riceve solo valori.

```swift
nonisolated enum FocusedDisplayResolver {
    static func resolve(
        window: CGRect?, pointer: CGPoint,
        frames: [CGDirectDisplayID: CGRect],
        previous: CGDirectDisplayID?, main: CGDirectDisplayID?
    ) -> CGDirectDisplayID?
}
```

- [x] Aggiungere il test del conflitto finestra/puntatore.

```swift
@Test func focusedWindowWinsOverPointer() {
    let frames: [CGDirectDisplayID: CGRect] = [
        1: CGRect(x: 0, y: 0, width: 1000, height: 800),
        2: CGRect(x: -1000, y: 0, width: 1000, height: 800)
    ]
    #expect(FocusedDisplayResolver.resolve(
        window: CGRect(x: -900, y: 100, width: 600, height: 500),
        pointer: CGPoint(x: 500, y: 400), frames: frames,
        previous: 1, main: 1
    ) == 2)
    #expect(FocusedDisplayResolver.resolve(
        window: nil, pointer: CGPoint(x: 500, y: 400),
        frames: frames, previous: 2, main: 1
    ) == 1)
}
```

- [x] Eseguire il filtro `FocusedDisplayResolverTests` e verificare il fallimento iniziale.
- [x] Implementare intersezione massima, parità stabile, fallback puntatore → principale → primo ID ordinato. Scartare frame nulli, infiniti, vuoti o senza intersezione positiva.
- [x] Osservare cambio app, cambio finestra focalizzata, spostamento/ridimensionamento, minimizzazione e distruzione della finestra; rimuovere le sottoscrizioni precedenti. Accorpare gli eventi, eseguire letture AX sul worker e scartare risposte di generazioni superate. Alla revoca/assenza di Accessibility pubblicare `nil` e usare il fallback senza aprire dialoghi ripetuti.
- [x] Riutilizzare il percorso esistente di variazione permessi per riattivare il monitor quando il consenso cambia. Il puntatore viene sempre osservato per l'hover, ma aggiorna il display attivo soltanto se manca un frame focalizzato valido.
- [x] Testare separatamente conversione coordinate con monitor sopra/sotto/sinistra, area in parità, cambio finestra nella stessa app, spostamento senza mouse, callback tardivo e permesso revocato. Iniettare il trasporto AX nel monitor per queste prove, senza interrogare altre app nei test unitari.
- [x] Eseguire nuovamente i test; verificare su una finestra reale che trascinarla tra monitor cambi il risultato con puntatore poi fermo. Nessun timer periodico.

## Aggiornamento contratti dopo audit del 25 settembre

La visibilità nel task 3 usa `setVisibleActivities(_ activities: [any NotchActivity])`, con identità di istanza, al posto del solo insieme di ID riportato nella bozza sotto. La scelta espansa distingue esplicitamente nessuna attività, fallback e attività selezionata. Nel task 4 le richieste portano un token cancellabile e la chiusura una generazione: conta il termine reale del morph. Il satellite deve restare sulle copie compatte degli altri display; il layout del display già espanso resta quello esistente. Questi emendamenti prevalgono sui frammenti iniziali.

## Task 3 — Selezione condivisa e ciclo di vita delle attività

**Files:** modificare `CascadeKit/Sources/CascadeKit/Core/Activities/LiveActivityHost.swift`, `Tests/CascadeKitTests/LiveActivityHostTests.swift` e `Tests/CascadeKitTests/AddonPresentationTests.swift`. Aggiornare temporaneamente il controller singolo alla nuova interfaccia per mantenere la tranche compilabile.

**Interfaces:** il nuovo `ActivitySelection` interno contiene `primary`, `secondary`, `expanded` di tipo `(any NotchLiveActivity)?` e `notice: (any NotchTransientNotice)?`. `LiveActivityHost.selection` lo espone in sola lettura; `setExpanded(_:activityID:)` continua a scegliere l'attività aperta. Nuovo `setVisibleActivityIDs(_ ids: Set<String>)` governa l'attivazione effettiva all'interno della sessione visibile; `setVisible(false)` rimane riservato alla sospensione globale/blocco e non alla rimozione di una copia. `setVisible(true)` abilita la sessione ma attiva soltanto le identità dell'unione consegnata dal coordinatore.

- [x] Nello stesso file dei fixture `LiveFixture` esistenti, aggiungere il test seguente.

```swift
@Test @MainActor func copiesShareActivationUntilLastPresentationLeaves() {
    let host = LiveActivityHost()
    let music = LiveFixture("music")
    host.setVisible(true)
    host.present(music)
    host.setVisibleActivityIDs([music.id])
    host.setVisibleActivityIDs([music.id])
    #expect(music.activations == 1)
    host.setExpanded(true, activityID: music.id)
    #expect(host.selection.primary?.id == music.id)
    #expect(host.selection.expanded?.id == music.id)
    host.setVisibleActivityIDs([music.id])
    #expect(music.suspensions == 0)
    host.setVisibleActivityIDs([])
    #expect(music.suspensions == 1)
    host.stop()
}
```

- [x] Eseguire `swift test --package-path CascadeKit --filter LiveActivityHostTests` con il `DEVELOPER_DIR` del task 1 e registrare il fallimento iniziale.
- [x] Separare il calcolo di `ActivitySelection` dalla riconciliazione delle attivazioni. La selezione compatta non dipende da `isExpanded`; gli avvisi non cancellano la selezione live sottostante. L'espansione continua a eliminare e sopprimere gli avvisi secondo il contratto esistente.
- [x] Confrontare l'unione delle identità effettivamente visibili con le attivazioni correnti; a parità di ID confrontare anche l'istanza per sospendere quella sostituita. `setVisibleActivityIDs` non deve emettere ricorsivamente `onChange` a ogni applicazione della stessa proiezione.
- [x] Mantenere un solo scheduler delle scadenze. Conservare priorità, due sorgenti distinte, fallback espanso, invalidazione per revisione e revoca dei vecchi contesti. Un'attività esclusa da tutte le presentazioni conserva metadati/scadenza ma non risorse di vista.
- [x] Aggiungere prove per primaria/secondaria compatte mentre una è espansa, aggiornamento unico osservato da due copie, scadenza mentre espansa, rimozione di una copia senza sospensione, sostituzione d'istanza con stesso ID e sospensione al blocco. Con `SnapshotActivity`, l'azione rimane valida finché c'è una presentazione e viene revocata dopo l'ultima; non creare un provider per display.
- [x] Rieseguire `LiveActivityHostTests` e `AddonPresentationTests`; adeguare le vecchie aspettative solo dove il nuovo contratto richiede la selezione compatta persistente.

## Task 4 — Pannelli permanenti e apertura esclusiva

**Files:** creare `CascadeKit/Sources/CascadeKit/Core/Engine/NotchDisplayCoordinator.swift` e `Tests/CascadeKitTests/NotchDisplayCoordinatorTests.swift`. Modificare `Core/Engine/NotchEngine.swift`, `Core/Engine/NotchController.swift`, `Core/Events/EventMonitoring.swift` e `Tests/CascadeKitTests/NotchControllerTests.swift`.

**Interfaces:** `NotchDisplayCoordinator` ha `start()`, `stop()`, `updatePreferences(_:)`, `requestExpansion(on: CGDirectDisplayID, activityID: String?)`, `requestCollapse(on:)`, `didFinishCollapse(on:)` e `expandedDisplayID: CGDirectDisplayID?`. Il controller locale riceve `updateDisplay(_ display: ActiveDisplay)` e `applyPresentation(_:)`; emette richieste di apertura/chiusura e fine animazione. `DisplayPresentation` contiene i riferimenti ai contenuti locali `primary`, `secondary`, `notice`, `expanded`, `showsWidgets: Bool` e lo stile risolto. Le attività usano i tipi del task 3.

- [x] Costruire fixture del coordinatore con inventario finto, focus finto e superfici registranti conformi a `NotchDisplayPresenting`. Questo protocollo espone i metodi locali sopra, `close(animated:)`, `stop()` e callback di fine chiusura. Registrare pannelli creati, frame, contenuti visibili e sequenza delle transizioni.
- [x] Scrivere la prova sequenziale: collegare A/B → due superfici; aprire A → proprietario A; richiedere B → A in chiusura e B ancora compatto; notificare `didFinishCollapse(on: A)` → proprietario B; entrambe le superfici esistono ancora. La prova deve controllare ogni transizione, non solo il risultato finale.
- [x] Eseguire il filtro `NotchDisplayCoordinatorTests`, verificando il fallimento prima dell'implementazione.
- [x] Spostare inventario, focus, monitor, host attività e host widget al coordinatore. Ogni controller rimane ancorato al proprio display; il focus non chiama più `layoutPanel` sui pannelli esistenti. L'aggiornamento della geometria del display può chiamarlo. La configurazione prodotto mantiene sempre visibile il chrome software: il vecchio flag `drawsChromeWithoutHardwareNotch` non può spegnere le sagome previste dalla nuova modalità.
- [x] Implementare passaggio di proprietà secondo questa sequenza; il completamento dell'animazione è un evento del controller, non un ritardo numerico.

```text
requestExpansion(B):
  if un'interazione trattiene A: conserva B finché il trigger resta valido
  else if A esiste ed è diverso da B:
    pending = B; invalida i controlli aperti di A; chiedi chiusura di A
  else: assegna B e presenta il contenuto consentito dal routing
didFinishCollapse(A):
  libera A e le sue viste espanse
  se pending è ancora collegato e il trigger è valido: apri pending
  altrimenti: tutti compatti
```

- [x] Calcolare una `DisplayPresentation` per superficie: attività solo sui destinatari; avviso solo sul display attivo; contenuto espanso solo sul proprietario. Rimuovere le viste/interazioni uscenti, comunicare all'host l'unione degli ID della nuova presentazione e delle viste ancora in animazione, quindi costruire le nuove viste. `activate` deve precedere le factory: `SnapshotActivity` cattura il permesso d'azione durante la costruzione della vista. A fine animazione ridurre nuovamente l'unione. Il cambio di focus tra due copie della stessa attività non deve produrre un insieme vuoto intermedio.
- [x] I controller in chiusura possono rimuovere le loro viste, ma non chiamano `activityHost.stop()`, `setVisible(false)` o `setPresentationSuppressed` globali. La soppressione durante un morph è locale. `WidgetHost` ha un solo proprietario espanso; svuotare/revocare la vecchia vista prima di montarla sul nuovo display.
- [x] Instradare il movimento del puntatore al display sotto il puntatore e al precedente/attuale proprietario per generare l'uscita; non fare hit test su ogni schermo a ogni evento. Il pulsante rilasciato raggiunge sempre il controller che possiede il trascinamento.
- [x] Testare tutti/focus/fisso senza ricreazione di finestre, A→B→C rapido, uscita del puntatore da B prima della chiusura di A, rimozione di A/B durante la transizione, popover/drag/impostazioni, blocco/sblocco, stop e Riduci movimento. `stop()` rimuove tutte le finestre e ferma una sola volta servizi condivisi.
- [x] Rieseguire i test del coordinatore e del controller. Non modificare gli algoritmi delle molle o le priorità dei provider in questo task.

## Task 5 — Notch software e Dynamic Island a goccia

**Files:** creare `CascadeKit/Sources/CascadeKit/Models/Geometry/SoftwareNotchMetrics.swift`, `Extensions/CGPath+SoftwareNotchDroplet.swift`, `Tests/CascadeKitTests/SoftwareNotchGeometryTests.swift`. Modificare `Models/Geometry/NotchGeometry.swift`, `Models/Configuration/NotchConfiguration.swift`, `Core/Engine/NotchController.swift`, `Components/NotchHostView.swift`, `Models/Configuration/NotchActivityViewContext.swift` e `Cascade/Features/MediaLiveActivity.swift`.

**Interfaces:** `SoftwareNotchMetrics` espone `restingSize`, `compactHeight`, `compactCenterGap`, `neckWidth`, `bodyOffset`. Nuova geometria a goccia verticale separata da `CGPath.notchDroplet`, che resta il satellite delle attività.

```swift
nonisolated struct SoftwareNotchMetrics {
    let restingSize = CGSize(width: 96, height: 8)
    let compactHeight: CGFloat = 32
    let compactCenterGap: CGFloat = 24
    let neckWidth: CGFloat = 12
    let bodyOffset: CGFloat = 8
}
```

- [x] Scrivere prove sulle tre misure indipendenti e sulla larghezza centrale. Per hardware finto di 200 pt la riserva rimane 200; per software è 24 con identiche dimensioni dei contenuti laterali. Verificare entrambi gli stili a riposo con bounding box 96 × 8 comprensiva dei raccordi, senza sommare accidentalmente i raggi esterni.
- [x] Eseguire `SoftwareNotchGeometryTests` prima della nuova implementazione e osservare il fallimento.
- [x] Sostituire gli usi indistinti di `restingSize` nel controller: trigger di riposo usa la sporgenza; layout compatto usa altezza e separazione per attività; contenuto espanso usa riserva hardware reale o zero. Aggiornare anche satellite, pulsante impostazioni, inset e calcolo del canvas.
- [x] Passare `hardwareNotchWidth: 0` sul software, preservando il valore calibrato hardware dove esiste. Correggere il fallback `?? 200` in `MediaLiveActivity` se necessario affinché un'esplicita assenza di hardware non generi il vecchio vuoto centrale. Non ridurre icone/font per ottenere uno spazio centrale più piccolo.
- [x] Per Dynamic Island senza attività interpolare la sporgenza verso corpo e collo verticali; Notch usa la forma collegata al bordo. Durante Live Activity usare lo stesso layout e percorso delle attività per entrambi gli stili. Un `expandedFallback` privo di sessione live usa la goccia.
- [x] Far consumare lo stesso path a fill, glass, bordi, maschera, accessibilità e hit testing. Conservare il renderer del satellite e il percorso Spotlight. La sporgenza superiore resta presente anche quando il corpo della goccia scende.
- [x] Applicare le vecchie calibrazioni solo all'hardware per questa nuova modalità software; conservare i dati salvati. Non fare migrazioni distruttive. Il controllo dimensioni non deve imporre alla nuova sporgenza il vecchio minimo di 16 pt.
- [x] Testare path finito e contenuto nel canvas a progressi 0/0.5/1, frame iniziale/finale, interruzione del morph, cambio stile da aperto, arrivo/fine attività durante la goccia, scale 1×/2× e display stretto. Nessun frame con contenuto fuori maschera, path/hit test divergenti o sporgenza assente.
- [x] Eseguire `SoftwareNotchGeometryTests`, `NotchGeometryTests`, `ContinuousNotchPathTests`, `NotchHostViewTests`, `NotchSizeCalibrationTests` e `NotchControllerTests`. Confrontare visivamente i valori iniziali della specifica; eventuali ritocchi aggiornano anche la specifica.

## Task 6 — Impostazioni e superfici ausiliarie

**Files:** modificare `Cascade/CascadeServices.swift`, `Cascade/Features/Settings/CascadeSettingsView.swift`, `Cascade/Features/Settings/CascadeSettingsWindowController.swift`, `Cascade/Integrations/Spotlight/SpotlightCoordinator.swift`, `CascadeKit/Sources/CascadeKit/Core/Engine/NotchEngine.swift`, `CascadeTests/SettingsTests.swift`.

**Interfaces:** l'engine espone `setDisplayPreferences(_ preferences: DisplayPresentationPreferences)`, elenco descrittivo dei display e callback dei suoi cambiamenti. `CascadeServices` persiste le preferenze del task 1 e fornisce binding alla UI; nessuna doppia cache autorevole. `expandedFrame` e `onExpandedFrameChanged` descrivono il proprietario dell'apertura, non il display che ha appena ricevuto focus.

- [x] Aggiungere casi di ricerca `.displayStyle` e `.activityDisplays` e relativi test prima della UI: termini «schermo», «display», «notch», «Dynamic Island» e «attività» trovano i controlli reali.
- [x] Implementare nella pagina Appearance una sezione Schermi: righe con nome del display e scelta Notch/Dynamic Island solo quando manca il taglio hardware. Per hardware mostrare il comportamento fisico senza un selettore inapplicabile.
- [x] Aggiungere «Mostra Live Activities» con tre opzioni: «Tutti gli schermi», «Segui il focus», «Schermo specifico». Il selettore del monitor appare solo per la terza; il monitor offline rimane elencato come scollegato. Testo di aiuto spiega focus e fallback e che la sagoma rimane su tutti gli schermi.
- [x] Applicare le preferenze immediatamente, senza riavvio, con normalizzazione al caricamento. Il cambio stile richiude la superficie interessata prima di cambiare geometria; non interrompe le attività sulle altre superfici.
- [x] Ancorare impostazioni, calibrazione e Spotlight al display di invocazione/apertura. Sostituire la selezione autonoma del puntatore in `SpotlightCoordinator` con un'ancora fornita dai servizi: display aperto se presente, altrimenti display attivo risolto dal task 2. Il suo eventuale focus non deve trasferire l'ancora.
- [x] Conservare l'arbitraggio unico anche per Spotlight: le altre sagome rimangono, una seconda espansione aspetta la chiusura della superficie esterna. Se il display scompare, annullare il raccordo e usare il ripristino nativo già previsto, senza spostare finestre indiscriminatamente.
- [x] Verificare persistenza e ricerca con `SettingsTests`; aggiungere prova per impostazioni aperte su B mentre il focus esterno passa su A, scelta fissa offline e display omonimi con UUID diversi. Usare etichette accessibili che distinguano le righe omonime.

## Task 7 — Verifica integrata, documentazione e build

**Files:** aggiornare `docs/architecture/live-activity-contracts.md`; creare `docs/superpowers/verification/2026-09-24-multi-display-notch.md` al momento dell'esecuzione, registrando ambiente effettivo e prove. Non dichiarare già eseguite le verifiche elencate qui.

- [x] Eseguire tutti i test CascadeKit una volta conclusi i task: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path CascadeKit`.
- [x] Eseguire test app con `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Cascade.xcodeproj -scheme Cascade -configuration Debug -destination 'platform=macOS' -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/CascadeDevelopment" test -only-testing:CascadeTests/SettingsTests`.
- [x] Verificare la seguente matrice su monitor reali quando disponibili, registrando come non verificata ogni combinazione non disponibile. I fake dimostrano routing/stato, non stacking nativo dei pannelli.

| Prova | Risultato richiesto |
| --- | --- |
| Hardware + esterno, nessuna attività | Due sagome permanenti; esterno selezionabile nei due stili |
| Due schermi senza hardware | Stili indipendenti, stessa semantica delle attività |
| Tutti, due attività, apertura su A | Copie compatte su B; una sola superficie aperta |
| Focus della finestra su A, mouse su B | Attività compatta su A; hover su B può aprire i widget |
| Spostamento finestra/cambio finestra nella stessa app | Attività segue il nuovo display; pannelli non si spostano |
| Specifico B; scollegamento/riconnessione B | Nessuna copia su A; ritorno su B con stessa revisione valida |
| A aperto, richiesta B, poi C | Chiusura A prima di nuova apertura; ultima richiesta valida |
| Arrivo/scadenza Live Activity durante morph | Sagoma sempre presente, contenuti coerenti, nessuna attività risuscitata |
| Lock/unlock, stop/start, coperchio chiuso | Nessuna finestra orfana, servizi rilasciati, inventario aggiornato |
| Fullscreen, Spaces, Mission Control, mirroring | Presenza compatta sul desktop pertinente; nessuna duplicazione di pannelli logici |
| Riduci movimento/trasparenza, VoiceOver | Geometria finale corretta, stessa esclusività, contenuti sensibili protetti |
| Impostazioni, popover, Spotlight | Ancora stabile e unica interazione aperta |

- [ ] Qualificazione nativa delle risorse a riposo: conteggio di display link e TimelineView tramite profiling non eseguito. **Parte automatica completata:** tre copie condividono una sola attivazione/scadenza, il focus non rialloca pannelli e i test di morph/lock/Riduci movimento passano. Il limite di profiling è dichiarato nel verbale e accettato come confine della consegna locale, senza affermare una misura nativa inesistente.
- [x] Aggiornare i contratti architetturali: sagome permanenti, selezione compatta indipendente dall'espansione, ciclo di vita condiviso, significato degli avvisi e misure software.
- [x] Eseguire `scripts/build-development.sh`. Solo dopo successo verificare il target di `/Applications/Cascade.app`, terminare l'istanza precedente, riaprire quel percorso e verificare processo/eseguibile della nuova istanza.
- [x] Nel rapporto finale distinguere test automatici, prove reali, combinazioni non disponibili e risultati del riavvio. Non considerare la sola build una verifica multi-monitor.

**Esito di consegna, 26 settembre 2026:** implementazione e revisioni concluse; build firmata e riavvio verificati. Suite Settings 17/17; full package finale eseguito, exit 1 con i timeout confrontati con baseline nel [verbale](../verification/2026-09-24-multi-display-notch.md). Le prove fisiche non disponibili e il profiling non eseguito restano esplicitamente non qualificati.

## Criterio di completamento

Tutti i requisiti della specifica hanno un task: presenza e apertura → task 4; stile/goccia/geometria → task 5; modalità e persistenza → task 1 e 6; focus confermato → task 2; copia senza duplicazione dei provider → task 3; qualificazione e riavvio → task 7. Il lavoro è completato solo dopo verifica delle transizioni e della replica, non dopo la sola aggiunta dei selettori.
