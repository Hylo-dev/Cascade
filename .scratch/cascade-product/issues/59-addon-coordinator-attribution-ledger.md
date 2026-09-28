# Collegare il registro delle catene alle misure CPU

ID: 59
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex-root
Blocked by: 58

## Question

Collegare lo stesso registro verificato al coordinatore, linearizzando ogni lettura/riduzione con i destinatari esatti e restituendone la provenienza. Preflight dei conti prima delle letture, registrazione e disarmo atomici, reset wake senza azzerare debito. Sol medium implementa; root e revisore verificano.

## Answer

Collegamento implementato da Sol medium; root e revisore indipendente senza rilievi sul codice congelato.49 test mirati/5 suite PASS. Il coordinatore preammette il dominio limitato, legge/riduce sotto il lock della singola osservazione, conserva destinatari esatti anche sui dati mancanti e mantiene aritmetica/debito precedenti. Lifecycle binding e wake sincronizzati con il registro; input manuale separato dalla modalità canonica. [Rapporto](../../codex-addon/20260922-transitive-cpu/task-59-report.md).
