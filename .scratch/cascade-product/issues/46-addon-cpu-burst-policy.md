# Chiarire come il burst CPU consuma il budget addon

ID: 46
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 45

## Question

Prima di collegare le osservazioni CPU alle violazioni, come convivono i candidati «50 ms su finestra mobile di 10 s» e «burst iniziale 100 ms/job»? Il credito iniziale deve consumare un budget dell’addon che non si ricarica con nuovi job/processi, oppure deve essere aggiuntivo per ogni job ammesso dall’host?

## Contesto

La [specifica approvata](../../../docs/superpowers/specs/2026-09-09-addon-runtime-design.md) e il [piano C4](../../../docs/superpowers/plans/2026-09-09-addon-runtime-02-execution.md) nominano entrambi i valori ma non definiscono la loro precedenza, esenzione o accumulo. Il lettore, riduttore e coordinatore consegnano osservazioni; AddonHealthStore accetta violazioni già classificate, senza definire il budget CPU. Anche la [ricognizione del 18 settembre](../../codex-addon/20260918-continuation/addon-remaining-work-audit.md) aveva lasciato esplicitamente aperta la definizione degli intervalli/burst. Un job da 80 ms sarebbe entro il burst ma oltre la finestra ordinaria da 50 ms: la classificazione non può essere ricavata dai due numeri da soli. Riavviare molti job non deve diventare implicitamente una deroga alle quote.

## Alternative concrete da decidere

1. **Credito condiviso dell’addon (raccomandazione):** capacità iniziale 100 ms, recupero di 5 ms di CPU per secondo trascorso; ogni lavoro consuma lo stesso credito, conservato fra job e riavvii del provider. La specifica passerebbe esplicitamente da finestra mobile rigida a budget ricaricabile: consente lo spunto ma limita il consumo sostenuto. Il credito non si rigenera semplicemente creando un job.
2. **Burst aggiuntivo per ogni job:** mantenere 100 ms aggiuntivi per job host ammesso e 50 ms/10 s per il restante lavoro. Occorre inoltre fissare un limite cumulativo ai burst/frequenza dei job; senza questo limite non si può dedurre un tetto sostenuto per addon.

Sono politiche diverse, non dettagli intercambiabili d’implementazione. Nessuna è applicata dal presente ticket. La scelta vale solo per gli addon event-driven; profili continui UI/audio, attribuzione dei servizi condivisi e qualifica nativa rimangono distinti. Non si modifica né riapre il blocco del launcher.

L’utente ha richiesto di fermare l’esecuzione a una scelta progettuale necessaria. Completare e verificare l’incremento del coordinatore già in corso, poi presentare questo punto; nessun worker implementa la policy prima della risposta.

## Answer — decisione dell’utente, 20 settembre 2026

L’utente sceglie «la consigliata»: credito comune per addon con capacità iniziale 100 ms e ricarica 5 ms CPU/secondo monotono. Nuovi job e riavvii del provider non ricreano il credito. Questo sostituisce esplicitamente la precedente finestra mobile rigida 50 ms/10 s e il burst aggiuntivo 100 ms/job.

La decisione riguarda gli addon event-driven. Non concede una deroga ai profili UI/audio continui, non risolve attribuzione dei servizi condivisi o la verifica nativa, non apre il launcher. Le alternative sopra sono storiche: la prima è ora approvata.
