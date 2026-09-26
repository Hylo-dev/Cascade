# Applicare la CPU delegata alle ammissioni e alla salute addon

ID: 61
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 59, 60

## Question

Comporre registro, broker e coordinatore nel runtime interno. Validare provenienza delle letture e autorità del consumatore anche senza processo, registrare salute senza cancellare storia, applicare pausa ai nuovi lavori del consumatore e preservare lavori già ammessi. Gestire stale/wake/disable/exit e completezza, con test end-to-end e consegna firmata. Nessuna attivazione nativa.

## Answer

Composizione interna implementata e revisionata da root e Sol indipendente: provenienza dei contributori, consumatori senza processo, pausa delle nuove ammissioni e conservazione del lavoro accettato. Corretto l’ordine di acquisizione prima del lancio e mantenuto l’ack v1.4 dopo commit seguito da esito indeterminato. 152 test mirati/15 suite e suite completa **1.195 test/112 suite PASS**. Il controllo completo ha richiesto soltanto aggiornare tre valori esatti per la riserva aggiuntiva di4KiB, conservando la verifica del rimborso. [Report](../../codex-addon/20260922-transitive-cpu/task-61-report.md), [revisione indipendente](../../codex-addon/20260922-transitive-cpu/task-61-independent-review.md), [suite completa](../../codex-addon/20260922-transitive-cpu/package-tests-before-retry-fixed.log). Build firmata e avvio aggiornato sono verificati nella [consegna finale](../../../docs/superpowers/verification/2026-09-22-addon-transitive-cpu.md); launcher nativo invariato.
