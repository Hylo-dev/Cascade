# Prova isolata della durata di un servizio XPC

Fixture fissa, separata da Cascade. Non carica addon e non abilita il launcher.
Misura quattro casi: uscita cooperativa, cancellazione della connessione con client vivo,
uscita ordinaria del client e morte del client tramite SIGKILL.

Il servizio Application è incluso nel bundle del client, firmato con Hardened Runtime
e App Sandbox. Il client verifica i messaggi ricevuti mediante requisito di firma e
`SecCodeCreateWithXPCMessage`. Il protocollo contiene soltanto dati sintetici.
Il caso non cooperativo trattiene il callback in `pause()`, senza consumo attivo di CPU.

L'osservatore registra `EVFILT_PROC/NOTE_EXIT/NOTE_EXITSTATUS` dopo un primo messaggio
autenticato e conferma l'incarnazione con un secondo messaggio. Non manda segnali al
PID del servizio. La finestra misurata dura due secondi; un allarme autonomo nel servizio
limita l'esperimento a otto secondi da main. Questo allarme è solo una guardia della
fixture: non prova alcuna garanzia prima di main o con codice addon arbitrario.
L'uscita durante la pulizia resta separata dal risultato misurato.

## Riproduzione locale

Richiede macOS, Xcode-beta e l'identità Apple Development indicata in `run_probe.py`.
Le build vengono create in una cartella univoca sotto DerivedData, senza registrare
LaunchAgent o modificare `/Applications/Cascade.app`.

```sh
python3 -m unittest discover -s Prototypes/AddonPlatform/XPCLifetime -p 'test_*.py'
python3 Prototypes/AddonPlatform/XPCLifetime/run_probe.py --build-only
python3 Prototypes/AddonPlatform/XPCLifetime/run_probe.py --run /percorso/products/stampato
```

Codici del runner: 0 tutti PASS; 1 almeno un risultato negativo valido; 2 osservazione
incompleta/UNKNOWN o pulizia non confermata. Un FAIL non è una prova di impossibilità
generale di XPC. Tutti i risultati conservano `launcherAdmitted: false`.

La [prima misurazione](../../../docs/superpowers/verification/2026-09-24-addon-xpc-lifetime.md)
registra tre PASS e un FAIL: la cancellazione della connessione non ha fermato il
servizio durante la finestra osservata; la successiva uscita del client lo ha fermato.
