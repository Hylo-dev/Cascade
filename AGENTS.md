# Completamento del lavoro

- Al termine di ogni intervento sul progetto, prima della risposta finale, chiudi Cascade e rilanciala senza chiedere un'ulteriore conferma.
- Se hai modificato il codice dell'app, completa prima la build e riavvia la versione aggiornata solo se la compilazione riesce.
- Verifica che l'app sia effettivamente ripartita. Se un impedimento blocca la build o il riavvio, dichiaralo nella risposta finale.
- A ogni build riuscita aggiorna `/Applications/Cascade.app` affinché punti alla build appena compilata. Lo schema Xcode condiviso e `scripts/build-development.sh` eseguono `scripts/update-application-link.sh`; se usi un altro comando di build, esegui lo stesso script sul relativo `.app` prima del riavvio.
