# Notch su più display — specifica per il piano

Data: 24 settembre 2026. Stato: requisiti ricevuti il 24 settembre; implementazione del piano autorizzata il 25 settembre. Le scelte proposte restano identificate come impostazioni iniziali reversibili.

## Risultato richiesto

Cascade mantiene una presenza compatta sul bordo superiore di ogni display collegato. Il focus decide dove mostrare le Live Activities solo quando l'utente sceglie quella modalità; non decide dove esiste il notch. Una sola superficie può essere aperta alla volta.

Requisiti espliciti dell'utente:

- Su display senza notch hardware sono disponibili **Notch** e **Dynamic Island**.
- A riposo entrambi sono una piccola sporgenza dal bordo superiore.
- Senza Live Activity, Dynamic Island si espande a goccia.
- Durante una Live Activity si conservano gli stessi elementi e interazioni del notch hardware, con uno spazio centrale più piccolo.
- L'«ombra», cioè la sagoma chiusa, resta su tutti gli schermi indipendentemente dal focus.
- È possibile aprire il notch su un solo schermo alla volta.
- Le Live Activities possono essere ripetute su tutti i display, seguire il focus oppure apparire sempre e solo su un display scelto.
- **Chiarimento confermato:** focus della finestra attiva; puntatore soltanto come fallback.

## Comportamento delle superfici

| Display/stato | Riposo senza attività | Attività compatta | Espansione |
| --- | --- | --- | --- |
| Con notch hardware | Sagoma allineata al taglio e alla calibrazione esistente | Layout attuale, spazio centrale legato al taglio | Comportamento attuale |
| Senza hardware, Notch | Piccola sporgenza ancorata al bordo | Layout attuale con separazione centrale ridotta | Pannello collegato al bordo |
| Senza hardware, Dynamic Island | Piccola sporgenza ancorata al bordo | Stessi elementi e separazione ridotta del Notch software | Senza Live Activity: corpo arrotondato sotto il bordo, collegato mediante collo a goccia; con Live Activity: espansione dell'attività già prevista dal renderer |

«Sempre» riguarda i display del desktop mentre Cascade è in esecuzione nella sessione sbloccata. Si conserva l'attuale esclusione dalla schermata di blocco. Fullscreen e cambi di Space non devono eliminare le sagome; Mission Control può chiudere la superficie espansa senza cancellare la presenza compatta.

La geometria di riposo, l'ingombro dei contenuti compatti e la riserva per il taglio hardware diventano misure distinte. Una sporgenza bassa non deve rendere illeggibili icone e testo delle attività. `hardwareNotchWidth` non deve più ricevere una larghezza software su un display senza taglio.

## Routing delle Live Activities

| Modalità | Destinazioni compatte | Se il focus cambia |
| --- | --- | --- |
| Tutti gli schermi | Tutti i display collegati | Nessuno spostamento |
| Segui il focus | Display della finestra attiva; fallback puntatore, poi display principale | Cambiano soltanto i contenuti dell'attività; le sagome restano |
| Schermo specifico | Solo il display scelto tramite identità persistente | Nessuno spostamento |

Il contenuto replicato ha la stessa identità, revisione, priorità, scadenza e stato privacy. Le viste possono adattarsi alle dimensioni locali, ma non diventano attività indipendenti. Chiudere/dismettere l'attività con il relativo comando agisce su tutte le copie; richiudere il pannello non conclude l'attività.

Un'attività espansa su un display non rimuove le copie compatte dagli altri display destinatari. Due attività conservano l'attuale disposizione: primaria e satellite della secondaria; il satellite resta compatto se l'altra superficie è aperta.

## Apertura e passaggio tra display

- Hover, clic e azione accessibile chiedono l'apertura sul display che li ha ricevuti, anche se il focus applicativo è altrove.
- La richiesta su B fa richiudere A e apre B solo quando A ha raggiunto lo stato chiuso. Nessun frame con due superfici espanse. Con Riduci movimento il passaggio è immediato.
- Durante il passaggio rimangono visibili le sagome di entrambi gli schermi. Richieste ulteriori aggiornano la destinazione: prevale l'ultima ancora valida.
- Il semplice cambio di finestra attiva non trasferisce un pannello aperto, impostazioni, popover o un trascinamento in corso.
- Un'interazione in corso con un controllo, un popover, le impostazioni o Spotlight trattiene il proprietario dell'apertura; una richiesta concorrente resta pendente solo finché il suo trigger è valido.
- Se il display aperto viene scollegato, si eliminano subito pannello, viste e interazioni di quel display. Gli altri rimangono compatti; nessuna apertura automatica altrove.

## Scelte proposte, distinte dai requisiti confermati

Queste scelte rendono eseguibile il piano e possono essere modificate in revisione:

1. **Stile per display senza hardware**, ricordato tramite UUID. Default: Notch. Vale anche per un display integrato senza taglio, non solo per quelli esterni. Se l'UUID non è disponibile, la scelta resta utilizzabile per il collegamento corrente tramite ID runtime, senza salvataggio persistente; viene cancellata alla disconnessione o all'arresto di Cascade e la riga spiega questa eccezione.
2. **Default Live Activities: Segui il focus.** L'impostazione è globale per le attività, non diversa per ogni provider.
3. **Display fisso assente:** nessuna copia su altri schermi; conservare la scelta e riprendere sul display alla riconnessione. Le sagome e i widget restano disponibili ovunque. È l'interpretazione letterale di «sempre e solo».
4. **Apertura su un display escluso dal routing:** mostra i widget, senza portare lì la Live Activity. In modalità Segui il focus un'attività già aperta rimane consultabile fino alla chiusura, anche se la copia compatta passa al nuovo display attivo. In modalità fissa non si concede questa eccezione su altri display. Un cambio esplicito di preferenza che esclude il display aperto richiude prima l'attività.
5. **Avvisi transitori:** mantengono la loro semantica e appaiono soltanto sul display attivo; non vengono replicati dall'impostazione delle Live Activities. Sopprimere gli avvisi durante qualsiasi espansione e blocco schermo come oggi, senza riprodurli dopo. Un avviso già visibile può seguire il focus mantenendo la scadenza originale.
6. **Misure iniziali da verificare visivamente:** sporgenza software 96 × 8 pt; altezza attività compatta 32 pt; spazio centrale software 24 pt; ali con misure/inset correnti. La sporgenza di riposo e il corpo attivo hanno dimensioni indipendenti. Nessun nuovo slider in questa tranche.
7. **Goccia:** il corpo rimane collegato alla sporgenza attraverso un collo durante l'apertura; non è una capsula permanentemente flottante. Profilo iniziale: collo 12 pt e corpo 8 pt sotto la sporgenza, dimensioni espanse del contenuto già limitate dal renderer. Calibrare questi valori nella verifica visiva senza alterare il contratto.

## Focus e identità dei display

Osservare la finestra focalizzata dell'app in primo piano, compresi cambio finestra e spostamento della stessa finestra fra display. Usare il display con la maggiore area d'intersezione con la finestra. In parità conservare il precedente se ancora candidato, poi usare un ordinamento stabile dei display.

Normalizzare esplicitamente le coordinate Accessibility e AppKit, anche per display a sinistra o sopra il principale. Se la finestra non è disponibile, i permessi Accessibility mancano o l'app non risponde, usare il puntatore; se anche questo non individua un display, usare il principale. Un errore non lascia valido il vecchio focus. Rileggere al cambio reale degli input, senza polling o chiamate AX nel percorso del mouse/animazione.

Usare snapshot e notifiche. Le letture AX avvengono su worker con timeout e generazioni, secondo il modello già presente nell'integrazione Spotlight. Callback tardivi di app/finestra precedenti vengono scartati. Non occorre un nuovo permesso Screen Recording; il fallback resta operativo senza Accessibility.

Il pannello non attivante non deve diventare origine del focus. Impostazioni e superfici ausiliarie di Cascade conservano l'ancora del display sul quale sono state aperte.

Identità persistente: riutilizzare la risoluzione UUID già impiegata da `NotchSizePreferences`. L'ID numerico CoreGraphics resta una chiave della sessione corrente. Un UUID non disponibile non va inventato né rimpiazzato con il nome del monitor: quel display funziona nella sessione ma non viene proposto come destinazione persistente. Display speculari producono una sola superficie per desktop logico, già ripetuta dal sistema sugli schermi fisici.

## Architettura scelta

Approcci considerati:

- **Consigliato: un coordinatore, una superficie per display, un host delle attività condiviso.** Riutilizza pannello, vista, molle e controller, rendendo il controller locale a un display. Richiede separare selezione dei contenuti e loro visibilità.
- Un engine completo per display: meno modifiche iniziali, ma duplica scadenze, attivazioni, contesti e avvisi. Incompatibile con il ciclo di vita attuale dei provider.
- Sagome passive su tutti i display e un solo pannello mobile: sufficiente per il riposo, ma la replica delle attività imporrebbe comunque un secondo percorso di rendering e interazione.

`NotchEngine` rimane la facciata pubblica. Un `NotchDisplayCoordinator` possiede inventario, focus, preferenze, host delle attività, host widget e apertura esclusiva. Ogni `NotchController` possiede soltanto pannello, vista, geometria, animazione e stato di interazione del suo display. Nessun controller locale decide di fermare provider condivisi.

`LiveActivityHost` conserva una sola raccolta e una sola scadenza. Pubblica separatamente selezione live compatta, avviso e attività scelta per l'espansione. Il coordinatore determina quali viste sono realmente visibili e consegna all'host l'unione delle identità visibili: `activate` una volta alla prima presentazione, `suspend` una volta dopo l'ultima. Le factory producono viste distinte per ciascuna superficie.

Mantenere gli SDK e i protocolli dei provider; nessun runtime addon per monitor. Verificare esplicitamente `SnapshotActivity` e `MediaLiveActivity`, che oggi trattengono un solo contesto di attivazione.

## Vincoli e accettazione

- macOS 14 minimo; Swift 6; AppKit/Core Animation per pannelli e morph, SwiftUI per contenuti.
- Nessuna nuova dipendenza o API privata per questa funzionalità.
- Un solo monitor globale del mouse; niente polling del focus o dei display.
- I display link si fermano a geometria stabile. Gli aggiornamenti di focus non ricreano pannelli.
- Privacy e accessibilità applicate a ogni copia prima delle factory sensibili.
- Calibrazioni hardware esistenti preservate; vecchie calibrazioni software non devono impedire la nuova piccola sporgenza. Con le misure software fisse di questa tranche, il comando di calibrazione è disponibile soltanto per un display con notch hardware; i dati precedenti restano conservati.
- Verificare più display, scale diverse, coordinate negative, mirroring, collegamento/scollegamento, chiusura del coperchio, blocco/sblocco e Riduci movimento.
- Fine implementazione: test pertinenti, build con `scripts/build-development.sh`, aggiornamento del collegamento `/Applications/Cascade.app`, riavvio e verifica del processo.

Piano associato: [implementazione multi-display](../plans/2026-09-24-multi-display-notch.md).
