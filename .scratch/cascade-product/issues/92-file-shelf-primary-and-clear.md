# Rendere il ripiano la pagina principale e semplificarne le carte

ID: 92
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: open
Assignee: none
Blocked by: 89

## Question

Attuare la richiesta esplicita dell'utente nella pagina locale del [ripiano approvato](../../../docs/superpowers/specs/2026-09-26-file-shelf-design.md): quando contiene almeno una voce, il ripiano si apre automaticamente e resta aperto come pagina principale finché non è vuoto, al posto della pagina Orologio. Aggiungere **Svuota** sotto **Converti** sia nel mazzo sia nell'elenco: rimuove tutti i riferimenti dal ripiano e lascia intatti gli originali esterni. Le carte mostrano solo icona e nome, senza sfondo; ventaglio e transizione verso l'elenco restano animati.

Accettazione: stato occupato ripristinato dopo riavvio e svuotamento esplicito riportano la pagina principale alla selezione ordinaria soltanto quando l'ultima voce esce; azione Svuota disponibile nei due modi, nessuna cancellazione degli originali; icone/nomi leggibili, VoiceOver e Riduci movimento coerenti, animazioni del mazzo/elenco preservate. Test mirati e review root, poi build firmata e prova nel notch reale. Nessuna disponibilità simulata di Converti, nessuna modifica al launcher addon o alle quote/grant.

## Avanzamento — implementazione verificata, prova manuale pendente

La parte app/renderer è stata revisionata dal root: sette test app e un test renderer passati. L'integrazione finale è in `5d852e7`; review root dei dodici file di codice e correzioni di ownership asincrona, cache pagina e preview concluse. Test app firmati indipendenti 7/7 (`root-shelf-clear-app-tests.log`), suite SwiftPM 1.443/1.443 (`root-receiver-persistent-tests.log`) e build firmata exit 0 (`root-receiver-persistent-build.log`). I test verificano che Svuota conservi gli originali; il manifest conserva una voce dopo il riavvio al PID 74874. Screenshot CUA della finestra ricevente trasparente non prova la resa del ripiano: pagina principale, Svuota, carte e animazioni attendono conferma manuale dell'utente sulla build finale. Ticket aperto/non assegnato per QA nativa, distinto dalla [regressione del drag in ingresso](91-file-shelf-native-drop-regression.md).
