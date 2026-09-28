# Collegare gli interessi canonici alla contabilità CPU

ID: 60
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex-root
Blocked by: 58

## Question

Agganciare il registro condiviso ai commit di nuovi interessi e alle rimozioni canoniche del broker, conservando interessi oltre disconnect/exit. Validazione prima del commit, rollback senza perdite e controllo interno sui nuovi interessi dei consumatori a quota chiusa. Terra medium implementa; root e revisore verificano.

## Answer

Collegamento minimale implementato da Terra medium, root e revisore indipendente senza rilievi sul codice congelato.39 test/3 suite PASS. Commit canonici e registro condividono il punto di linearizzazione senza sospensioni; rimozioni/rollback esatti, interessi preservati oltre disconnect/exit. Consumatori in pausa possono riusare interessi esistenti, ma non crearne di nuovi. Test rafforzati per distinguere storia di intervallo da interesse ancora attivo. [Rapporto](../../codex-addon/20260922-transitive-cpu/task-60-report.md).
