# Definire a chi attribuire la memoria osservata dei servizi

ID: 64
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 63

## Question

Il footprint RAM di un processo che offre un servizio condiviso deve influire soltanto sulla salute dell’addon proprietario, oppure anche su quella dei suoi consumatori diretti e indiretti?

## Contesto

Le decisioni [CPU conservativa](55-addon-delegated-cpu-attribution.md) e [catene attive](57-addon-transitive-cpu-attribution.md) riguardano lavoro consumato durante un intervallo. La RAM osservata è invece una quantità residente corrente: include runtime, librerie e cache condivise, senza misura della memoria causata da una singola richiesta. Il lettore espone il footprint ma il coordinatore non lo classifica ancora. [Ricognizione delle fonti](../../codex-addon/20260922-transitive-cpu/post63-memory-audit.md).

## Alternative

1. **Solo addon proprietario del processo (consigliata).** La RAM di B influisce su B anche se A ne usa un servizio. Ogni processo è osservato una sola volta; non si copia il suo footprint nei consumatori. Corrisponde alla misura fisica disponibile ed evita di sanzionare A per librerie e cache di B usate anche da altri. Non impedisce da sola di trasferire al servizio una richiesta che aumenta la memoria: restano necessarie quote delle risorse controllate dal broker.
2. **Anche consumatori attivi, come per la CPU.** La RAM di B viene considerata anche per A e per gli antenati attivi, deduplicando identità/processo. Contrasta lo spostamento dei costi verso i servizi, ma può limitare o sanzionare un addon per memoria residente che non ha causato. Il totale fisico globale resta contato una volta.

Questa scelta riguarda esclusivamente l’attribuzione. I64/96MiB del provider e128/192MiB della UI restano candidati: soglie effettive, somma provider/scena e conteggio degli episodi richiedono un contratto successivo prima dell’enforcement. Nessuna opzione riapre il launcher o trasforma il runtime puro in una garanzia nativa. Nessuna implementazione RAM è autorizzata dalla sola ricognizione.

## Answer

Scelta utente: **1 — solo addon proprietario del processo.** Un footprint osservato
appartiene esclusivamente all'identità verificata del processo fisico misurato. Non è
copiato a consumer diretti o transitivi di servizi, anche se l'interesse broker è
canonico e attivo. La misura fisica e il totale globale restano contati una volta.

Questa risoluzione non approva soglie, aggregazione provider+UI, conteggio degli
episodi, quarantena o azione di arresto; 64/96 MiB provider e 128/192 MiB UI restano
candidati. Il gate di identità, lettura e arresto nativo rimane chiuso.

Documentazione aggiornata da Terra medium e revisionata da root; nessun sorgente modificato. [Verifica della decisione e riavvio](../../codex-addon/20260922-memory-owner/verification.md).
