# Sviluppare addon per Cascade

I contratti, i componenti dichiarativi e l'interfaccia `AddonProvider` sono disponibili nel package `CascadeKit`. Il runtime per avviare pacchetti esterni non è ancora abilitato: la [qualificazione del launcher](../superpowers/verification/2026-09-10-addon-launcher-decision.md) resta da completare per identità e arresto dei processi gestiti. Il [rischio del lavoro delegato](../superpowers/specs/2026-09-10-addon-control-policy.md) è stato accettato esplicitamente. Anche i widget del team dovranno usare questo percorso quando sarà qualificato.

## Validare un manifest

Dal checkout del progetto, con un toolchain compatibile con Swift tools 6.2:

```sh
swift run --package-path CascadeKit cascade-addon validate /percorso/Manifest.json
```

Il comando usa lo stesso validatore di `CascadeContracts`, legge al massimo 64 KiB più un byte di controllo e rifiuta directory, pipe e altri file non regolari. Non esegue codice o comandi contenuti nel manifest.

L'esito `0` conferma la validità del documento secondo i contratti attuali; `1` indica un file illeggibile o non valido, `2` argomenti errati. La validazione del manifest non verifica firma, autorizzazioni dell'utente, presenza dei servizi richiesti o ammissione del pacchetto nel runtime.

Il comando `cascade-addon init` genera un progetto sorgente con provider, manifest e test basati sui prodotti pubblici SDK: seguire la [guida iniziale](quickstart.md). Il formato distribuibile e il bootstrap nativo richiedono ancora la qualificazione del launcher.

## Contratti disponibili

- [Creare un progetto sorgente addon](quickstart.md)
- [Verificare un provider addon](testing.md)
- [Compatibilità del package e del protocollo](compatibility.md)
- [Prestazioni e contabilità delle risorse](performance.md)
- [Sviluppo sorgente e distribuzione](distribution.md)
- [Esempi sorgente indipendenti](examples.md)
- [Protocollo e messaggi](protocol.md)
- [Negoziazione e ammissione delle sessioni](sessions.md)
- [Dipendenze REQUIRES](requires.md)
- [Contenuti dichiarativi](content.md)
- [Luci nel vetro](../architecture/glass-lighting.md)
- [Ciclo di vita, code e azioni](lifecycle.md)
- [Autorizzazione e coordinamento dei comandi](actions.md)
- [Servizi condivisi e permessi del broker](services.md)
- [Checkpoint e migrazioni dello stato](storage.md)
- [Immagini, trasferimenti a messaggi e client SDK](assets.md)
- [Schema del manifest](manifest.schema.json)
- [Piano di completamento](../superpowers/plans/2026-09-10-addon-runtime-completion.md)

## Client immagini

`MessageAddonAssetClient` implementa importazione, condivisione e rilascio tramite
un `AddonAssetMessageChannel` iniettato. Il collegamento interno al runtime è
verificato con un bridge di test che usa codec, ImageIO e contabilità reali. La
negoziazione 1.2 richiede capacità host storage e asset; i messaggi asset usano schema 1.
Il canale deve essere legato a una connessione autenticata, consumare le receipt e
completare la pulizia fisica: il bridge di test non è un trasporto OS distribuibile né un bootstrap produttivo.

## Client storage

`MessageAddonStorageClient` implementa lettura, scrittura e rimozione su un canale a messaggi iniettato. Correlazione, cancellazione ed esiti incerti sono verificati anche contro il backend reale; il canale produttivo deve fornire autenticazione e pulizia fisica. La memoria esterna va ammessa prima della costruzione e codifica dei messaggi. Vedere [contratto e limiti](storage.md#concrete-sdk-message-client).
