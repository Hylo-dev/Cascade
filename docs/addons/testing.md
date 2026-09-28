# Verificare un provider addon

Un provider sorgente può essere verificato senza avviare un processo addon dentro Cascade. Queste prove controllano il comportamento del provider e l’uso dei contratti pubblici; la qualificazione dell’addon installato richiede anche il percorso nativo dell’host.

## Progetto indipendente

La [guida iniziale](quickstart.md) mostra come generare un package con provider, manifest e test. Eseguire la build da una copia esterna al checkout, indicando esplicitamente il package SDK. Il progetto deve dipendere dai prodotti `CascadeAddonSDK` e `CascadeContracts`; le loro dipendenze pubbliche sono risolte da SwiftPM. Un import di `CascadeRuntime`, `CascadeKit` o sorgenti privati dell’app introduce una dipendenza dall’host e non dimostra l’indipendenza dell’addon.

Validare il manifest con `cascade-addon validate` ed eseguire `swift test` nel progetto generato. La validazione del manifest non esegue il provider e non verifica firma, autorizzazioni o identità del processo. La successiva build valuta il `Package.swift` scelto dallo sviluppatore: il percorso SDK va quindi trattato come una dipendenza di codice esplicita.

## Casi da coprire

- Usare identità di pubblicazione assegnate dall’host e verificare il rifiuto di un owner o di una sessione estranei. L’identificatore nel manifest non costituisce autenticazione.
- Verificare schema, contenuto, durata finita, revisioni crescenti e roundtrip dei valori restituiti. Un countdown dichiarativo non richiede un task del provider che pubblichi ogni secondo.
- Correlare ogni risposta a un’azione con il suo `requestID`; coprire input errati, scadenze, revisione osservata obsoleta e richieste duplicate. Pubblicare uno stato aggiornato non sostituisce la completion dell’azione.
- Per provider persistenti, distruggere e ricreare l’istanza usando storage condiviso e una nuova generazione del contesto. Verificare revisioni, dati corrotti, errori di lettura/scrittura e risultati di commit incerti. Non trasformare un errore di lettura in assenza di dati.
- Durante gli `await`, provare una seconda richiesta, la cancellazione e lo stop. L’isolamento dell’actor da solo non rende indivisibile una sequenza di lettura, modifica e scrittura.
- Usare client di capacità che falliscono esplicitamente quando la fixture non deve invocarli. Un servizio finto che restituisce sempre successo può nascondere una dipendenza non prevista.

Un clock iniettato rende riproducibili scadenze e ripristino. Non sostituire le prove di concorrenza con ritardi arbitrari: controllare esplicitamente i punti in cui una scrittura o una risposta rimane sospesa.

## Limiti delle prove del provider

I test unitari non dimostrano l’ammissione del pacchetto, l’identità dell’editore, la revoca di una connessione OS, le quote del processo, l’uscita dopo la morte del supervisore o la parità bundled/external. Anche una scrittura riuscita non dimostra che l’host abbia ammesso il successivo output: persistenza e pubblicazione non costituiscono una transazione unica dell’API pubblica.

Per queste proprietà servono le prove di integrazione e piattaforma descritte nel [piano addon](../superpowers/plans/2026-09-10-addon-runtime-completion.md), usando lo stesso percorso di ammissione previsto per addon del team e di terze parti. Il gate del launcher nativo rimane distinto dai test dei package sorgente.

## Confini dell’SDK e degli esempi

Lo script ufficiale `scripts/build-development.sh` esegue obbligatoriamente il controllo prima di Xcode: una violazione o l’assenza del verificatore interrompe il percorso prima di compilazione, firma e aggiornamento di Applications. Usa lo stesso DEVELOPER_DIR e passa la root esplicita del checkout, inclusi gli esempi. Questa garanzia riguarda lo script ufficiale; le invocazioni dirette di Xcode sono separate. La [verifica della build protetta](../superpowers/verification/2026-09-18-addon-required-sdk-build-check.md) distingue fixture negative e build firmata positiva.

Per eseguirlo separatamente, dal checkout usare `scripts/check-addon-boundaries.sh`. Il controllo valuta i manifest fidati di CascadeKit, StandaloneFocus, ServiceConsumer e StandaloneClock con il toolchain Xcode selezionato, verifica le dipendenze dei target, ricava da `swift package describe` i sorgenti selezionati dal toolchain e analizza gli import Swift effettivi, inclusi i rami condizionali. I prodotti pubblici ammessi sono CascadeAddonSDK, CascadeContracts e CascadePresentation. Sono rifiutati dipendenze/import privati dell’host, accessi @testable/@_spi all’SDK e generazione tramite plugin o macro nel profilo sorgente verificato. I test degli esempi possono usare @testable sui propri target.

`--json` include hash dei sorgenti/manifest, comandi di valutazione e versione del compilatore; `--root /percorso/checkout` seleziona un’altra copia dei quattro package. Il comando usa cache temporanee proprie e le elimina al termine. Richiede Python3 e un Xcode con SwiftParser/SwiftSyntax nel toolchain; DEVELOPER_DIR permette di selezionarlo. I manifest vengono eseguiti da SwiftPM e devono essere fidati. Questo profilo richiede il solo Package.swift: la presenza di manifest Package@swift versionati causa un errore esplicito.

`--test` esegue i test del controllo e compila il parser reale. Le prove complete del comando richiedono CASCADE_BOUNDARY_FIXTURE_ROOT puntato a una copia sorgente minima e immutabile con CascadeKit e i tre esempi; se manca, questi casi vengono segnalati come saltati. Non indicare un checkout contenente build/cache o altre grandi directory: i test copiano la fixture per introdurre difetti controllati.

Il risultato riguarda import e grafo statici nella valutazione scelta dei manifest. Non sostituisce la compilazione dei provider, non espande macro, non certifica ambienti alternativi del manifest o caricamento dinamico e non dimostra parità, isolamento o ammissione nativi.
