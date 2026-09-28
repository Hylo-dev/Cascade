# Conservare i destinatari CPU delle catene attive

ID: 58
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex-root
Blocked by: 57

## Question

Implementare un registro interno limitato di interessi canonici e destinatari transitivi per binding fisico. Conservare le catene esistite fra letture, evitando catene fantasma create da archi non contemporanei; deduplicare interessi e percorsi multipli. Linearizzare osservazioni e cambi di interesse senza confrontare clock diversi. Nessun timer, coda eventi illimitata o attivazione nativa. Sol medium implementa; root e revisione indipendente verificano prima del collegamento a broker/coordinatore/runtime.

## Answer

Registro limitato implementato da Sol medium, revisioni root e Sol indipendente PASS. Chiusure istantanee accumulate per binding, nessuna catena fantasma, osservazione sincronizzata e reset senza conti CPU. Nove test nuovi,29 test mirati/3 suite PASS; prova comportamentale negativa su catene ripristinata. [Evidenze](../../codex-addon/20260922-transitive-cpu/task-58-report.md). Collegamento a coordinatore e broker nei task dipendenti.
