# Definire notifiche di altre app e avvisi dei dispositivi

ID: 11
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: open
Assignee: none
Blocked by: 02, 04, 08

## Question

Con quali limiti di copertura e modalità di consenso Cascade presenta notifiche delle app non integrate, requisito confermato dall'utente? Decidere duplicazione o sostituzione dei banner di sistema, azioni e apertura dell'app sorgente, cronologia, filtri per app, contenuti sensibili, Focus e lock screen. Distinguere notifica ricevuta da un'altra app, evento Bluetooth rilevato e notifica emessa da un'estensione; scegliere un fallback esplicito dove la ricerca dimostra limiti.

La ricerca ha individuato polling su un archivio privato in Sapphire: prima di adottare quel percorso, verificare copertura e permessi in un account di prova e affrontare il conflitto con il vincolo del progetto contro polling e wakeup inutili. Il requisito dell'utente non autorizza a dichiarare universale una cattura parziale, né ad allentare implicitamente il vincolo sulle risorse.
