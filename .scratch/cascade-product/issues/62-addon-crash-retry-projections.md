# Preparare domanda e ticket per i retry dopo crash

ID: 62
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex-root
Blocked by: 60

## Question

Esporre proiezioni interne limitate dei retry già emessi da AddonHealthStore e della domanda canonica non scaduta del broker. Aggiungere cancellazione dei soli retry preservando sessioni e storia. Sono supporti alla policy già approvata 1/5/30 secondi, senza timer, rilanci o nuova policy. Terra medium implementa; root e revisore verificano.

## Answer

Proiezioni interne implementate da Terra medium, revisioni root e Sol indipendente PASS. Quattro test mirati passati nella compilazione comune: ticket ordinati e limitati, cancellazione dei soli retry senza perdere sessioni/storia, domanda canonica non scaduta per provider verificato. Nessun rilancio o timer aggiunto. [Rapporto](../../codex-addon/20260922-transitive-cpu/task-62-report.md). L’esito meccanico del giro comune non approva il distinto task runtime61, ancora in revisione sul protocollo v1.4.
