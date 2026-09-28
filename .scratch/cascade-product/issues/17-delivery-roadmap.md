# Ordinare i rilasci e definire i criteri di completamento

ID: 17
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: open
Assignee: none
Blocked by: 06, 08, 09, 10, 11, 12, 13, 14, 15, 16, 18

## Question

Come dividere il prodotto concordato in rilasci verificabili, preservando la modularità come obiettivo principale? Stabilire contenuto del primo rilascio, prova end-to-end con un'estensione sviluppata fuori dall'host, dipendenze, gate di fattibilità, matrice hardware/OS, distribuzione firmata/notarizzata e percorso Homebrew. Il risultato prepara specifiche implementabili per sottosistemi; non deve introdurre date o stime prive di informazioni sul team.

## Avanzamento del 9 settembre 2026

Disponibile il [piano esecutivo del sottosistema addon](../../../docs/superpowers/plans/2026-09-09-addon-runtime.md), richiesto dall'utente: P0 piattaforma, P1 contratti/SDK, P2 runtime/risorse, P3 adozione da parte dei widget Cascade, P4 distribuzione/qualificazione. Include dipendenze, file, interfacce, test comportamentali, misure e criteri di uscita; tutti i task implementativi sono da eseguire.

Il ticket globale rimane aperto: questa sequenza non decide il rilascio di tutte le altre funzioni, date, notarizzazione pubblica o Homebrew. L'uso del sistema comune per ogni futuro widget del team è invece un vincolo approvato della roadmap.

## Riallineamento del 14 settembre 2026

Il sottosistema addon è ora seguito dal [piano di completamento corrente](../../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md), che integra il piano P0–P4 storico. L'ultima [consegna verificata](../../../docs/superpowers/verification/2026-09-14-addon-asset-chunks.md) registra 795 test seriali in 80 suite, 400 input identici, revisione approvata, build firmata e avvio della versione aggiornata. Questi numeri descrivono la verifica del codice integrato, non una percentuale di prodotto completato.

Restano il trasporto nativo e la qualificazione del launcher, il collegamento del trasferimento asset al canale autenticato, i client concreti e il collegamento al ciclo dell'app, Clock/FocusTimer sul percorso comune, la migrazione degli altri widget e le prove di packaging/distribuzione e compatibilità. La scelta dei blocchi è nel [ticket dedicato](21-asset-transfer.md); frame e assemblatore interno sono implementati, mentre il percorso runtime/SDK resta da collegare. Le decisioni di rilascio globali e le relative dipendenze restano aperte.
