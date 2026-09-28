# Applicare il rifiuto temporaneo dei nuovi lavori addon

ID: 53
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 52

## Question

Applicare la scelta approvata alle ammissioni del runtime: dopo nuovo sforamento rifiutare nuovo lavoro con esito di risorsa temporaneamente non disponibile, riaprendo soltanto da campione completo con credito positivo. Conservare debito/storia fra provider, recupero dei duplicati, lavori già ammessi e loro deadline; isolare gli addon e ricontrollare la policy attraverso le attese. Nessuna coda, replay, aritmetica CPU duplicata o attivazione nativa. Sol medium implementa; root e revisore indipendente verificano. [Brief](../../codex-addon/20260921-cpu-admission/task-53-brief.md).

## Answer

Completato da Sol medium e revisionato da root/Sol: PASS. Un insieme limitato di identità verificate blocca nuovo lavoro dopo lo sforamento e si riapre soltanto da credito strettamente positivo misurato. Le guardie si applicano alle nuove azioni e al provider dei nuovi job, con ricontrolli dopo le attese. Duplicati, lavoro già ammesso e riuso di sorgenti già avviate restano disponibili. Il broker rifiuta nuovi avvii prima del commit quando la CPU è già bloccata; la gara durante un commit conserva la semantica di esito indeterminato prevista dal protocollo.

Otto nuovi test;191 test mirati complessivi PASS (189/12suite più2/1suite). Hash congelati e log red/green conservati. [Rapporto](../../codex-addon/20260921-cpu-admission/task-53-report.md), [revisione indipendente](../../codex-addon/20260921-cpu-admission/task-53-independent-review.md). Suite completa/build/riavvio saranno verificati nella [consegna della tranche](../../../docs/superpowers/verification/2026-09-21-addon-cpu-admission.md), dopo il collegamento delle scadenze comuni. Nessuna attivazione nativa.
