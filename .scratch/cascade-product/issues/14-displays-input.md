# Definire monitor, focus e interazioni del notch

ID: 14
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 04, 07

## Question

Su più display Cascade segue il puntatore, resta su un display scelto o mostra più notch? Concordare profili per display e comportamento con scaling, risoluzione, menu bar, fullscreen, Spaces, Mission Control, lock, sleep e riconnessione. Definire anche il passaggio tra overlay senza focus, widget cliccabili, drag e ricerca/impostazioni digitabili: hit testing, click esterni, Esc e ripristino del focus precedente.

## Answer

Decisioni raccolte nella conversazione del 24–25 settembre: sagoma compatta permanente su ogni display, una sola apertura, Notch/Dynamic Island sui display senza hardware, stessa Live Activity con spazio centrale software ridotto; distribuzione tutti/focus/display fisso. Focus della finestra attiva, puntatore soltanto come fallback, confermato esplicitamente. La richiesta del 25 settembre autorizza mappa, ticket ed esecuzione del piano.

La [specifica](../../../docs/superpowers/specs/2026-09-24-multi-display-notch-design.md) registra casi limite e impostazioni iniziali reversibili; il [piano](../../../docs/superpowers/plans/2026-09-24-multi-display-notch.md) articola implementazione e verifica. Questa chiusura registra la decisione; non dichiara implementazione o qualifica multi-monitor già completate. Comportamenti di tastiera, trascinamento, Spaces e focus ausiliario esistenti sono preservati e ricontrollati nelle prove di integrazione.
