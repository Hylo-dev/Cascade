# Recupero globale di un'estensione esterna

Fixture separata da Cascade: app firmata → provider ExtensionFoundation sandboxed
in un contenitore `.app` esterno. Il provider risponde, poi trattiene il callback.
L'invalidazione viene osservata con host vivo; soltanto dopo si provoca l'uscita
normale o il crash dell'host. Una nuova catena parte **solo dopo** le uscite della
vecchia, con una nuova identità di processo confermata.

```sh
python3 -m unittest discover -s Prototypes/AddonPlatform/Recovery -p 'test_*.py'
python3 Prototypes/AddonPlatform/Recovery/run_recovery.py --build-only
python3 Prototypes/AddonPlatform/Recovery/run_recovery.py --run /absolute/path/from/build
```

Richiede macOS, Xcode e la specifica identità di sviluppo della fixture.
Build e firme sono in una nuova directory DerivedData. Il runner verifica gli hash,
registra l'uscita via kqueue tra due risposte autenticate e distingue misurazione e
cleanup. Le guardie SIGALRM iniziano nel codice della fixture: non sono una soluzione
pre-main. Il controllo dedicato verifica anche SIGALRM ereditato bloccato.

La registrazione riguarda soltanto le copie del contenitore di prova con firma e
identità fissate. Il runner non abilita permessi di sistema. L'errore LaunchServices
-10814 su copie già rimosse viene conservato come nella prova broker; la discovery
deve comunque essere univoca e il percorso deve autenticarsi. Le esecuzioni
consegnate conservano i propri sorgenti e manifest precedenti a questa correzione.

Il profilo opzionale `build(broker_provider=True)` è riservato alla composizione
[BrokerRecovery](../BrokerRecovery/README.md): il provider accetta il broker esatto
al posto dell'host diretto. Non amplia il requisito di firma.

[Risultati e limiti](../../../docs/superpowers/verification/2026-09-24-addon-global-recovery.md).
Nessun adapter di prodotto o ammissione del launcher.
