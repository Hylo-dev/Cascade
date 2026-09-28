# Collegare il credito CPU alle osservazioni comuni

ID: 48
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 47

## Question

Associare esplicitamente i binding osservati all’addon event-driven e conservare il conto nel coordinatore esistente, condiviso fra processi e riavvii provider. Addebitare ogni intervallo prodotto internamente una sola volta; distinguere osservazioni incomplete e fallimenti contabili. [Brief](../../codex-addon/20260920-cpu-credit/task-48-brief.md), [revisione del disegno](../../codex-addon/20260920-cpu-credit/ownership-design-review.md). Sol medium implementa; root revisiona. Nessun timer, sanzione o percorso nativo aggiuntivo.

## Answer

Collegamento interno implementato da Sol medium, rivisto da root e da un secondo Sol medium: PASS. Conti limitati per identità verificata, condivisi fra processi, conservati dopo unregister/uscita/riavvio provider/wake. Gli intervalli appena ridotti sono addebitati nello stesso actor; risultato finale per owner distinto fra completo, incompleto e errore persistente, senza saldo nei due ultimi casi.

71 test mirati in quattro suite PASS, inclusi 12 nuovi test del collegamento; replay root completo: 1.122 test in 99 suite PASS. [Rapporto worker](../../codex-addon/20260920-cpu-credit/task-48-report.md), [revisione indipendente](../../codex-addon/20260920-cpu-credit/task-48-independent-review.md), [consegna e limiti](../../../docs/superpowers/verification/2026-09-20-addon-cpu-credit.md). Nessun collegamento a sanzioni o launcher.
