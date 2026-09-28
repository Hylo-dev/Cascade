# Verifica delle osservazioni di processo — 18 settembre 2026

**PASS per lettura e riduzione limitate; C4 completo ancora parziale.** Aggiunti un lettore interno dell’API pubblica `proc_pid_rusage` v0 e un riduttore puro degli intervalli CPU. Identità osservata nello stesso record, contatori mancanti distinti da zero, conversione Mach con overflow controllato e memoria limitata a un campione precedente. Nessun polling, arresto, autenticazione o collegamento all’enforcement introdotto. [Contratto e limiti](../../architecture/addon-resource-observations.md).

## Verifiche

- 33 test mirati / 1 suite PASS, incluso un controllo dell’ABI che legge soltanto il processo di test già esistente. RED comportamentale verificato; due precedenti errori di compilazione conservati senza presentarli come RED comportamentale.
- Suite completa: **929 test / 85 suite PASS** — Runtime 611/49, Presentation 66/7, Kit 170/19, Contracts 65/8, Tool 17/2. Test UI eseguiti con accesso alla sessione grafica.
- Revisione indipendente Codex Sol high PASS nel perimetro. Due P3 di formulazione corretti: il test iniettato non osserva il flavor della chiamata nativa; documentati esplicitamente il confronto CPU indipendente ancora mancante e i limiti di riconoscimento di nuove esecuzioni della stessa immagine.
- Build Apple Development riuscita da snapshot locale di 415 file, firma deep/strict valida e collegamento /Applications/Cascade.app aggiornato. Chiusura normale e riavvio: PID 17941 → 25731, unico eseguibile atteso, stabilità di 5 secondi.

[Rapporto implementer](../../../.scratch/codex-addon/20260918-continuation/metrics-report.md), [revisione indipendente](../../../.scratch/codex-addon/20260918-continuation/metrics-independent-review.md), [audit suite](../../../.scratch/codex-addon/20260918-continuation/metrics-test-audit.json), [manifest build](../../../.scratch/codex-addon/20260918-continuation/metrics-build-snapshot-manifest.json), [build firmata](../../../.scratch/codex-addon/20260918-continuation/metrics-signed-build.log), [riavvio](../../../.scratch/codex-addon/20260918-continuation/metrics-restart-evidence.json).

Dopo suite e build, la sola differenza nei tre file implementativi è la correzione del commento del test da “PID/flavor” a “PID/order”; nessuna istruzione eseguibile è cambiata. Il manifest della build conserva correttamente il commento storico; l’addendum della revisione registra l’hash finale. Nessun test ripetuto per questo cambiamento puramente descrittivo. La differenza del commento ScaffoldWriter rilevata nell’audit del worker era già stata corretta e revisionata nella consegna precedente: [riconciliazione root](../../../.scratch/codex-addon/20260918-continuation/metrics-root-scope-reconciliation.json).

## Qualifiche mancanti

Le unità dei contatori sono sostenute dai sorgenti Apple e dai test sintetici, non da una calibrazione indipendente misurata. La prova ABI è avvenuta su arm64/macOS 27; macOS 14 e Intel non sono stati qualificati. Restano associazione autenticata addon/processo, campionamento comune e disarmo, integrazione con salute e soglie, misura degli sforamenti e arresto effettivamente osservato. Metriche o ESRCH non autorizzano da soli il rilascio delle riserve. Il gate C0d mantiene `exit 78`; nessuna qualifica del launcher o del controllo nativo completo.

## Aggiornamento successivo — calibrazione indipendente

La mancanza di calibrazione descritta sopra si riferisce alla consegna iniziale. La [prova indipendente successiva](2026-09-18-addon-process-cpu-calibration.md) ha verificato le unità con copie identiche di lettore/riduttore contro getrusage, con revisione PASS. Qualifica limitata a macOS27 arm64/self-process; nessun sorgente modificato e nessuna estensione a enforcement, macOS14/Intel o uscita gestita.
