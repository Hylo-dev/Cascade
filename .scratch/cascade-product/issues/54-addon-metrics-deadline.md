# Collegare le misure addon alla scadenza comune

ID: 54
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 53

## Question

Comporre il deadline del coordinatore delle metriche con i quattro aggregati esistenti del runtime, servendolo dal ciclo deadline comune senza timer autonomi. Disarmare senza righe, preservare la cadenza massima1Hz e i campioni espliciti; offrire un hook interno di risveglio che interrompa la continuità delle misure senza azzerare credito o ammissioni. Verificare cambio dell’owner contabile dei deadline e contesa con campioni in corso, evitando risvegli ripetuti senza progresso. Nessun collegamento all’app o launcher. [Ricognizione](../../codex-addon/20260921-cpu-admission/deadline-followon-audit.md).

[Brief esecutivo](../../codex-addon/20260921-cpu-admission/task-54-brief.md). Terra medium implementa; root e Sol revisionano.

Il lavoro delegato è diviso senza sovrapporre file: Terra medium implementa runtime e test delle scadenze; Sol medium prepara il solo file di test delle interleaving wake, più complesse. Un unico scratch di test viene ceduto esplicitamente fra worker. Root e un distinto Sol medium eseguono la revisione finale.


## Answer

Completato il 21 settembre 2026 nel runtime interno. Un quinto identificatore aggregato compone la cadenza delle metriche senza timer; scadenze e pulizia precedono il campionamento. Il cambio owner conserva i vincoli della coda. Un solo token wake pendente rende obsolete le letture interrotte, conserva debito e ammissioni e trattiene un secondo risveglio durante il reset. Dieci nuovi test; run mirato finale118 test, suite completa1.153 test/104 suite PASS. Terra medium implementa produzione e scadenze ordinarie, Sol medium le prove concorrenti; root e Sol indipendente: PASS. Il tentativo iniziale con comando errato non è contato fra le verifiche. [Revisione finale](../../codex-addon/20260921-cpu-admission/task-54-independent-review.md), [consegna ed evidenze](../../../docs/superpowers/verification/2026-09-21-addon-cpu-admission.md). Nessuna attivazione del launcher o del collegamento macOS.
