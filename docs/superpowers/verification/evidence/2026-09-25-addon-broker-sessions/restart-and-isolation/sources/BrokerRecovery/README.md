# Broker XPC con provider esterno

Fixture app → broker XPC sandboxed incluso nell'app → provider sandboxed in un
contenitore esterno. Riusa protocollo, guardia e build del provider della prova
[Recovery](../Recovery/README.md). La discovery usa l'API disponibile da macOS 14;
la prova nativa consegnata è stata eseguita esclusivamente su macOS 27 beta.

```sh
python3 -m unittest discover -s Prototypes/AddonPlatform/BrokerRecovery -p 'test_*.py'
python3 Prototypes/AddonPlatform/BrokerRecovery/run_broker_recovery.py --build-only
python3 Prototypes/AddonPlatform/BrokerRecovery/run_broker_recovery.py --run /absolute/path/from/build
```

Tre scenari: uscita ordinaria del broker lasciando l'app responsiva; uscita normale
dell'app; crash dell'app. Il callback del provider rimane bloccato dopo una seconda
risposta autenticata. Prima dello stop, invalidare i riferimenti del provider non
lo termina nei due secondi osservati. Firma esatta, nonce, UUID per incarnazione,
percorso del bundle e kqueue consentono di attribuire le osservazioni. Le uscite per
guardia temporale non valgono come PASS e il cleanup non modifica il verdetto.

Il runner si ferma a UNKNOWN o cleanup incompleto. L'errore LaunchServices -10814
durante la rimozione di vecchie copie viene conservato: la successiva discovery
deve comunque trovare una sola identità e il percorso atteso deve autenticarsi.
Nessun cambio automatico dei permessi di sistema.

Non copre la fase prima dell'autenticazione, un broker completamente bloccato,
due addon contemporanei, un editore diverso o la semantica di riuso multi-host.
La nuova partenza senza chiudere l'app non è provata da questi tre casi.
Il gate di prodotto resta disabilitato.

[Rapporto e prove immutabili](../../../docs/superpowers/verification/2026-09-24-addon-global-recovery.md).
