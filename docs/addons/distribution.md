# Preparare la distribuzione di un addon

## Percorso consegnato: sviluppo sorgente locale

`cascade-addon init` genera una libreria SwiftPM con provider, manifest e test. Il progetto dipende dal percorso SDK locale indicato esplicitamente; non include un eseguibile, un installer o un repository remoto dell’SDK. Se il percorso cambia, aggiornare la dipendenza in `Package.swift` e verificare di nuovo il progetto. I comandi reali di generazione e validazione sono nel [quickstart](quickstart.md); la [guida ai test](testing.md) descrive la build indipendente.

`cascade-addon validate` controlla sintassi e contratti del manifest. Non autentica l’editore, verifica una firma, installa un addon o concede autorizzazioni. L’identificatore scelto dallo sviluppatore e l’entry point dichiarato non costituiscono identità verificata o bootstrap del processo. Anche la firma verificata della build di Cascade nei rapporti di consegna riguarda l’app host, non un addon distribuibile.

Gli esempi [StandaloneFocus](../superpowers/verification/2026-09-18-standalone-focus-source.md) e [ServiceConsumer](../superpowers/verification/2026-09-18-service-consumer-source.md) hanno prove di build e test sorgente indipendenti. Restano librerie sorgente: non sono addon installati, contenitori firmati o prove di parità nativa fra addon del team ed esterni.

## App sorgente e dipendenze

`sourceApp.required: false` non introduce una dipendenza globale dall’app sorgente. Un `REQUIRES` alla radice condiziona l’intero addon; quello di una feature condiziona soltanto quella feature. Una funzione che richiede l’app sorgente può risultare indisponibile senza bloccare una funzione autonoma. Questo è comportamento del resolver; non prova da solo lo scenario nativo con app mai installata.

Nel modello di risoluzione, `installed` richiede presenza verificabile nel catalogo host; `running` richiede anche un’app in esecuzione. La risoluzione non installa software, non apre app e non chiede permessi. `bundledLibraries` è inventario di codice incluso, mentre un servizio esterno richiede risoluzione e autorizzazione. Versione del servizio e versione del package restano distinte. Vedere [REQUIRES](requires.md), [protocollo](protocol.md) e [servizi](services.md).

## Confine del rilascio nativo

Il [piano di completamento](../superpowers/plans/2026-09-10-addon-runtime-completion.md) mantiene aperti launcher qualificato, packaging e ammissione nativa, catalogo esterno con installazione/aggiornamento, parità bundled/external e qualificazione delle scene remote. Le guide sorgente non definiscono un nuovo formato di distribuzione, una policy di firma o un comando di installazione.

Prima di considerare un artefatto distribuibile servono le verifiche native previste dal piano: identità e digest autorevoli, trasporto autenticato, permessi, lifecycle e risorse, aggiornamento e recupero. Non si può sostituire questo percorso copiando o spostando un bundle registrato, oppure attribuendogli credenziali di esempio. Le [compatibilità](compatibility.md) e le [prestazioni](performance.md) documentano ciò che la baseline permette di verificare oggi; C11/C12 completi restano aperti.
