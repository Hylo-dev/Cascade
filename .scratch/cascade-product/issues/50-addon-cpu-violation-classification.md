# Classificare il nuovo consumo CPU oltre credito

ID: 50
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 49

## Question

Applicare il conteggio approvato agli intervalli prodotti dal coordinatore: una classificazione per addon e giro, distinguendo nuovo sforamento, assenza di nuovo sforamento e misura non disponibile. Conservare le garanzie sui dati incompleti e sul debito residuo. [Brief](../../codex-addon/20260921-cpu-violations/task-50-brief.md). Terra medium implementa; root e revisore indipendente verificano prima del collegamento alla salute.

## Answer

Classificazione interna consegnata da Terra medium, revisionata da root e Sol medium: PASS. Predicato sul nuovo intervallo CPU positivo che lascia saldo negativo, aggregato una volta per owner. Debito inattivo escluso; prove positive conservate anche con misure parziali; assenza di prove/errore persistente resta non disponibile. Nessun contatore duplicato.

76 test mirati in cinque suite PASS, inclusi cinque nuovi test, con red comportamentale e green. Root ha richiesto un’unica osservazione owner e una prova reale di rimborso/esaurimento credito. [Rapporto](../../codex-addon/20260921-cpu-violations/task-50-report.md), [revisione indipendente](../../codex-addon/20260921-cpu-violations/task-50-independent-review.md). Consegna complessiva dopo il collegamento alla salute.
