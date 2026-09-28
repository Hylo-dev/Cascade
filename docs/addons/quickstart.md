# Creare un progetto sorgente addon

`cascade-addon init` prepara un progetto Swift basato sui prodotti pubblici `CascadeAddonSDK` e `CascadeContracts`. Il risultato è un progetto sorgente con provider, manifest e test: non è ancora un bundle installabile e non avvia processi addon dentro Cascade.

## Generazione

Indicare il percorso del package SDK e un identificatore scelto dallo sviluppatore:

```sh
CASCADE_SDK="/percorso/Cascade/CascadeKit"
ADDON_ID="com.example.mywidget"

swift run --package-path "$CASCADE_SDK" cascade-addon init \
  --name MyWidget \
  --identifier "$ADDON_ID" \
  --destination "$PWD/MyWidget" \
  --sdk-path "$CASCADE_SDK"
```

Sostituire l’identificatore d’esempio con quello del proprio progetto. Il comando non assegna un editore verificato, una firma o un certificato. La destinazione deve essere nuova e la cartella padre deve già esistere: anche una directory vuota o un collegamento simbolico già presente viene rifiutato.

Il progetto dichiara esplicitamente la dipendenza dal package SDK locale indicato. Non introduce un repository remoto inventato e non incorpora sorgenti privati del motore del notch. Se il package SDK viene spostato, aggiornare la dipendenza in `Package.swift`.

## Verifica

```sh
swift run --package-path "$CASCADE_SDK" cascade-addon validate "$PWD/MyWidget/Manifest.json"
swift test --package-path "$PWD/MyWidget"
```

La generazione non esegue automaticamente questi comandi. La validazione conferma sintassi e contratti del manifest; la build e i test verificano l’uso delle API pubbliche. Nessuno dei tre passaggi qualifica firma, identità del processo, installazione, autorizzazioni o trasporto nativo.

## Provider generato

Il provider implementa `AddonProvider`. Produce una pubblicazione widget per una richiesta `refresh` con identità assegnata dall’host e mantiene una revisione crescente nella propria istanza. Risponde a `stop` senza pubblicare nuovo contenuto e rifiuta esplicitamente gli eventi non implementati.

Il documento di contenuto viene costruito con i valori pubblici di `CascadeContracts`; il rendering rimane nell’host. Il modello generato non sostituisce il ripristino della revisione e dello stato necessario a un provider riavviato, né implementa un ciclo di ricezione IPC.

Per proseguire: [contenuti](content.md), [ciclo di vita e azioni](lifecycle.md), [servizi e permessi](services.md), [storage](storage.md), [client immagini](assets.md). La distribuzione nativa richiede il percorso di bootstrap e launcher qualificato previsto dal [piano addon](../superpowers/plans/2026-09-10-addon-runtime-completion.md).
