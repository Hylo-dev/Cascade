# Compatibilità degli addon

## Package e ambiente verificato

Il package SDK e il progetto generato dichiarano `swift-tools-version: 6.2` e macOS 14; i target pubblici `CascadeContracts`, `CascadePresentation` e `CascadeAddonSDK` usano il modo linguaggio Swift 6. Queste dichiarazioni non sono una matrice di piattaforme collaudate. Le verifiche documentate del 18 settembre usano Apple Swift 6.4 su macOS 27 arm64: non qualificano l’esecuzione su macOS 14 o Intel. Vedere le [prove dei contratti consegnati](../superpowers/verification/2026-09-18-addon-service-subscription-frames.md) e la [calibrazione CPU](../superpowers/verification/2026-09-18-addon-process-cpu-calibration.md).

Per un provider indipendente usare i prodotti `CascadeAddonSDK` e `CascadeContracts`; `CascadePresentation` è una dipendenza pubblica dell’SDK e offre i componenti dichiarativi. `CascadeRuntime`, `CascadeKit` e i sorgenti dell’app appartengono all’host: la loro presenza fra i prodotti SwiftPM non li rende dipendenze del percorso addon pubblico. La [guida ai test](testing.md) precisa questo confine. Una build sorgente riuscita non dimostra stabilità ABI, compatibilità fra binari compilati con toolchain differenti o parità nativa bundled/external.

## Manifest, protocollo e contenuti

Validare il manifest contro lo [schema pubblico](manifest.schema.json) e il [contratto](protocol.md). Versione del package, versione di un servizio, versione del manifest, minor del protocollo e schema del contenuto hanno ruoli distinti; non vanno dedotti l’uno dall’altro. `REQUIRES` esprime compatibilità e dipendenze, senza autenticare il provider o concedere permessi.

La negoziazione host parte da protocollo 1.0 e sceglie l’intersezione fra offerta del provider, requisito del manifest e capacità realmente collegate:

| Minor cumulativo | Capacità host necessaria |
| --- | --- |
| 1.1 | Dispatch storage per chiave |
| 1.2 | Storage più adapter capace di trasferire asset |
| 1.3 | Capacità precedenti più assembly interno completo delle invocazioni di servizio, handler, ambiente compatibile e capacità prenotate |
| 1.4 | Capacità precedenti più handler completo di controlli/sorgenti/eventi, adapter di sottoscrizione, ambiente compatibile e capacità massime prepagate |

Un’offerta o un profilo sintattico non abilita queste capacità. Il default resta 1.0 e i percorsi legacy fino a 1.3 sono preservati; assembly incompleti mantengono il livello precedente. Le connessioni complete 1.3/1.4 compongono sessione di pubblicazione e broker con una generazione canonica comune, senza riscrivere Grant. Il client pubblico `TransportServiceClient` implementa invoke/subscribe/unsubscribe insieme tramite un canale iniettato; l’host mantiene l’autorità e il refresh non rinnova la scadenza dell’interesse. Vedere [sessioni](sessions.md), [servizi](services.md), la [prova storica della sintassi 1.4](../superpowers/verification/2026-09-18-addon-service-subscription-frames.md) e il [riferimento alla consegna host e SDK completo](../superpowers/verification/2026-09-18-addon-service-subscriptions-host-sdk.md), con i relativi limiti di verifica. Questa composizione non qualifica adapter/bootstrap nativo, C0d, macOS 14 o Intel.

Gli schemi contenuto 1 e 2 vengono concordati separatamente. Schema 2 richiede supporto anche senza luci; non si può eliminare il campo delle luci per reinterpretare il documento come schema 1. Il controllo comprende tutte le rappresentazioni e le voci future della timeline. I [contenuti](content.md) descrivono componenti, limiti e comportamento del renderer.

## Cosa prova un esempio sorgente

Generazione, validazione e test del provider verificano contratti e uso delle API pubbliche. Non provano installazione, identità firmata, trasporto autenticato, arresto reale o ammissione nativa. Il percorso SDK locale è esplicito e richiede una nuova verifica quando si cambia baseline; seguire [quickstart](quickstart.md), [test](testing.md) e [distribuzione](distribution.md).
