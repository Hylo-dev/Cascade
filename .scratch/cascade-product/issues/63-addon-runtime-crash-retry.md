# Collegare i retry dopo crash alla scadenza comune

ID: 63
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 61, 62

## Question

Comporre la policy di crash già approvata nel runtime interno: causa di uscita fornita dall'host, sessione di salute anche prima delle metriche, domanda canonica corrente, consumo una sola volta e attese di 1/5/30 secondi nella coda comune. Stop/disable/wake annullano retry; nessun replay di comandi incerti o avvio nativo. Sol medium implementa con fake adapter, root e revisore verificano. Analisi preliminare in [audit](../../codex-addon/20260922-transitive-cpu/post61-crash-audit.md).

## Answer

Runtime puro implementato e revisionato PASS da root e Sol indipendente. Sessione pre-metrica al handoff, uscita inattesa classificata dall’host, domanda canonica corrente, ticket1/5/30secondi e quarantena al quarto crash con domanda. La decisione di crash usa la pulizia comune; i controlli della domanda e il consumo dovuto condividono l’ammissione, con verifica anche dopo le riserve. Retry senza domanda rimossi, rifiuti precedenti al handoff rimborsati, handoff rifiutato consumato senza replay. Stop/disable/wake annullano anche decisioni sospese. CPU delegata durante retry usa solo il ticket esatto.

[Report worker](../../codex-addon/20260922-transitive-cpu/task-63-report.md), [revisione indipendente](../../codex-addon/20260922-transitive-cpu/task-63-independent-review.md):230 test mirati/20 suite PASS. Suite completa root **1.209 test/113 suite PASS**, [log](../../codex-addon/20260922-transitive-cpu/package-tests.log). Sette hash finali verificati. Nessuna attivazione o qualifica nativa. La [verifica della tranche](../../../docs/superpowers/verification/2026-09-22-addon-transitive-cpu.md) conserva build firmata e avvio aggiornato verificati da497 input identici.
