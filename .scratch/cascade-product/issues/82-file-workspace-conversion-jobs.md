# Eseguire conversioni file in job recuperabili

ID: 82
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: open
Assignee: none
Blocked by: 77, 78, 81

## Question

Implementare il task 6 del [piano del ripiano file](../../../docs/superpowers/plans/2026-09-26-file-shelf.md): conversione reale fuori dal main actor con input autorizzati, formati chiusi, processo FFmpeg confinato/supervisionato, documenti nativi, progresso e job persistenti recuperabili. Accettazione: avvio ritorna job ID senza attendere conversione; input rinominati/sostituiti o non materializzati non diventano bersagli nuovi; nessuna interpolazione shell né accesso a file/URL referenziati dal media fuori grant; cancel/revoca/riavvio/quota gestiti; risultato atomico e cleanup dopo persistenza. Test mirati e prove di processo native, review root, commit. Dipende da percorso nativo, store e helper verificati; una simulazione di processo non soddisfa l'accettazione.
