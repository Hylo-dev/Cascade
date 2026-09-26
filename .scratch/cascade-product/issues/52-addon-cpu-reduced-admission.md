# Definire la riduzione dei nuovi lavori dopo uno sforamento CPU

ID: 52
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 51

## Question

Dopo una violazione moderata e prima della quarantena, quale riduzione concreta deve applicare l’host ai nuovi lavori event-driven?

## Contesto

La specifica richiede «riduzione delle concessioni e richiesta di rilascio», mentre `AddonHealthStore` conserva gli incidenti e restituisce `keep` per i primi due, `quarantine` al terzo in cinque minuti. Il valore `keep` non costituisce già un’implementazione della riduzione richiesta. La policy attuale ammette al massimo un job per addon: ridurre soltanto il parallelismo a uno non cambierebbe nulla.

Il credito e il conteggio degli sforamenti sono definiti. Mancano la condizione per riaprire le ammissioni dopo una violazione e il comportamento visibile delle richieste nel frattempo. È una scelta sul funzionamento del prodotto: un’azione dell’utente può dover attendere o ricevere una risposta di risorsa temporaneamente non disponibile.

## Alternative concrete

1. **Rifiutare nuovo lavoro finché il debito è ripagato (raccomandazione).** Dopo una violazione, nuovi job e azioni che richiedono lavoro del provider ricevono subito un esito temporaneamente non disponibile; nessuna coda aggiuntiva o replay automatico. Lavoro già ammesso mantiene le deadline previste. Il credito deve tornare positivo prima di riaprire; non serve ricostituire tutti i 100 ms. Con 50 ms di debito e nessun altro consumo, il recupero richiede circa dieci secondi. La terza violazione mantiene la quarantena già approvata.
2. **Attendere il ripristino dell’intero credito.** Stesso rifiuto temporaneo, ma si riapre soltanto quando sono disponibili tutti i 100 ms. Con 50 ms di debito e nessun altro consumo, il recupero richiede trenta secondi. Offre più margine al primo lavoro successivo, con attese più lunghe.

Un campione sconosciuto o un errore contabile non autorizzano la riapertura; il profilo richiede comunque misure affidabili e arresto qualificato. Questa scelta non cambia quote, conteggio degli incidenti, quarantena per versione, deadline del lavoro già ammesso o blocco del launcher. Stato dichiarativo già pubblicato e riserve fisiche mantengono i propri cicli di vita.

Completare e verificare la composizione osservativa già autorizzata prima di presentare la scelta. Nessuna di queste politiche viene implementata prima della risposta dell’utente.

## Answer

Il 21 settembre 2026 l’utente sceglie **1**: rifiutare immediatamente i nuovi lavori event-driven e le nuove azioni che richiedono lavoro del provider dopo uno sforamento, finché una misura completa e attendibile dimostra credito strettamente positivo. Nessuna coda aggiuntiva o replay automatico; non occorre ricostituire tutti i 100 ms. Campioni mancanti/errori non riaprono. Il lavoro già ammesso conserva le scadenze e i propri percorsi di completamento. Quarantena per versione e launcher bloccato restano invariati. L’implementazione è affidata al ticket [Applicare il rifiuto temporaneo dei nuovi lavori addon](53-addon-cpu-admission.md).
