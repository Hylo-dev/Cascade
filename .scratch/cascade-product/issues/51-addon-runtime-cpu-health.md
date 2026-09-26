# Collegare gli sforamenti CPU alla salute del runtime

ID: 51
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 50

## Question

Comporre nel runtime il coordinatore delle misure e lo store di salute esistente, con binding host esplicito, sessioni legate all’incarnazione del processo e consumo dei soli batch richiesti internamente. Registrare una violazione moderata per owner quando il classificatore la prova; rifiutare risultati obsoleti dopo attese e conservare la cronologia fra riavvii. [Brief](../../codex-addon/20260921-cpu-violations/task-51-brief.md), [disegno verificato](../../codex-addon/20260921-cpu-violations/health-integration-design.md). Sol medium implementa, root e revisore indipendente verificano. Integrazione interna e test con adapter finto, senza attivazione nativa o liberazione di riserve basata sulle metriche.

## Answer

Completato il 21 settembre 2026 da Sol medium, con revisione root e indipendente PASS. Il runtime possiede coordinatore e store di salute, registra binding soltanto per l’incarnazione corrente, ricontrolla identità/sessione dopo le attese e registra incidenti soltanto dai propri campioni. Stop e uscita revocano l’autorità; la pulizia comune distacca le misure senza liberare riserve fisiche. Debito e cronologia sopravvivono al riavvio del provider. Corretta in revisione la pulizia dei binding fermati per deadline e verificato il riuso senza cancellazioni tardive.

Otto nuovi test di integrazione; 100 test mirati complessivi (98 in sette suite più due in una suite trasporto) e 1.135 test package in 101 suite PASS. La quarantena è registrata nello stato interno: attivazione nell’app, binding nativo, deadline comune e sanzioni restano separati. La prossima [scelta sulla riduzione dei nuovi lavori](52-addon-cpu-reduced-admission.md) è necessaria prima dell’enforcement. [Rapporto](../../codex-addon/20260921-cpu-violations/task-51-report.md), [revisione indipendente](../../codex-addon/20260921-cpu-violations/task-51-independent-review.md), [verifica e consegna](../../../docs/superpowers/verification/2026-09-21-addon-cpu-violations.md).
