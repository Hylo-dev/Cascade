# Intermediario XPC per addon — prototipo isolato

La fixture misura due catene indipendenti:

```text
XPCBrokerProbe.app
 ├─ BrokerA.xpc → WorkerA.xpc (incluso nel bundle BrokerA)
 └─ BrokerB.xpc → WorkerB.xpc (incluso nel bundle BrokerB)
```

L'app simula Cascade. Broker e worker sono processi XPC Application con App Sandbox,
Hardened Runtime e firma Apple Development. Non esegue addon reali e non viene collegata
a Cascade. Il broker rimane fidato e disponibile mentre il worker trattiene il callback
in `pause()`. Lo stop chiede al broker di uscire; il runner misura se macOS termina
anche il worker, senza inviargli segnali.

Quattro casi: stop A, self-SIGKILL A, uscita ordinaria app, self-SIGKILL app. Nei primi due
il runner richiede un nuovo ping della stessa catena B dopo la finestra misurata.
Negli altri due entrambi i worker trattengono il callback e devono uscire tutti e quattro
i processi XPC. Ogni caso usa incarnazioni nuove. La finestra è due secondi;
broker/worker hanno una guardia SIGALRM di dodici secondi da main, esclusa dai PASS.

Il root autentica il broker, che autentica e riferisce la risposta del worker.
È una catena di fiducia fra fixture fisse, non una prova di identità di addon arbitrari.
Il runner registra gli eventi kernel dopo il primo messaggio, conferma UUID/PID/deadline
con un secondo, e separa misura da pulizia. Riusa `Output` dalla precedente prova
XPCLifetime senza cambiarla.

## Riproduzione

Richiede macOS e Xcode-beta con l'identità di firma presente in `XPCLifetime/run_probe.py`.

```sh
python3 -m unittest discover -s Prototypes/AddonPlatform/XPCBroker -p 'test_*.py'
python3 Prototypes/AddonPlatform/XPCBroker/run_broker_probe.py --build-only nested
python3 Prototypes/AddonPlatform/XPCBroker/run_broker_probe.py --run /percorso/stampato
```

Il runner verifica gli hash di sorgenti e binari prima dell'avvio. Exit 0: tutti PASS;
1: risultato negativo valido; 2: evidenza incompleta. La variante di packaging `siblings`
è preparata come alternativa alla discovery annidata, ma non è stata eseguita né qualificata.
Non rilanciare la stessa cartella di prodotti se si vogliono conservare i log precedenti.

`SignalCheck.c` è il riproduttore distinto della gara fra `raise(SIGKILL)` e `_exit`
su una coda dispatch: confronta `immediate-exit` e `wait-signal`, con guardia di due secondi.

[Rapporto e risultati](../../../docs/superpowers/verification/2026-09-24-addon-xpc-broker.md):
quattro PASS dopo la correzione della simulazione di crash. Nessuna ammissione del launcher,
nessuna prova prima di main o su pacchetti esterni.

## Callback di controllo bloccato

La [prova successiva](../../../docs/superpowers/verification/2026-09-24-addon-xpc-broker-blocked.md)
aggiunge `hold-both`, che trattiene sia il callback del worker sia quello del broker.

```sh
python3 Prototypes/AddonPlatform/XPCBroker/run_broker_probe.py --build-only nested
python3 Prototypes/AddonPlatform/XPCBroker/run_broker_probe.py --run-blocked /percorso/prima/build
python3 Prototypes/AddonPlatform/XPCBroker/run_broker_probe.py --build-only nested
python3 Prototypes/AddonPlatform/XPCBroker/run_broker_probe.py --run-control /percorso/seconda/build
```

Il primo ciclo registra due FAIL validi (stop e cancel) e un PASS (morte app), quindi
restituisce 1. Il secondo ciclo autentica un secondo canale verso la stessa incarnazione
del broker prima dello stop: PASS. Non prova recupero da blocco dell'intero processo.

## Tutti i canali di comando bloccati

`--run-frozen PRODUCTS` esegue stop sul secondo canale, uscita normale root e crash
root dopo `hold-all`. Il primo fallisce, gli altri passano nelle prove registrate.
Non è una sospensione di tutto il processo: listener/risposte/segnali restano attivi.
Il cleanup del primo caso osserva anche un ritardo di circa cinque secondi per A;
non usare il PASS host-normal come promessa di latenza per ogni sequenza.
[Risultati e limiti](../../../docs/superpowers/verification/2026-09-24-addon-xpc-frontier.md).
