# Notifica ExtensionFoundation e uscita osservata dal kernel

Verifica isolata di `AppExtensionProcess.Configuration.onInterruption`, configurata
prima dell'initializer e correlata a un nonce locale di avvio. Riusa host, provider,
firme, guardie e osservazione kqueue della fixture [Recovery](../Recovery/README.md).
Non cambia il launcher di Cascade.

```sh
python3 -m unittest discover -s Prototypes/AddonPlatform/Interruption -p 'test_*.py'
python3 Prototypes/AddonPlatform/Interruption/run_interruption.py --build-only
python3 Prototypes/AddonPlatform/Interruption/run_interruption.py --run /absolute/build/path
```

Cinque casi con host vivo: uscita volontaria del provider, crash del provider,
invalidazione con provider cooperativo, rilascio senza invalidazione esplicita
dell'AppExtensionProcess, invalidazione con callback del provider bloccato.
Nei due casi di rilascio i canali XPC e il listener vengono comunque invalidati.

La registrazione kernel avviene fra due risposte autenticate della stessa
incarnazione. I due segnali — callback e NOTE_EXIT — restano osservazioni distinte:
nessuna notifica da sola è una prova di uscita. La finestra dura sei secondi;
il cutoff precede un ultimo drain kernel e lo snapshot IPC. Un evento kernel
osservato nel drain finale dopo il cutoff produce UNKNOWN; le notifiche successive restano separate.
Il cleanup non entra nel risultato della finestra.

Il callback conserva soltanto un nonce, mai il processo o i canali. Le proprietà
forti dell'host e riferimenti deboli a canale, bootstrap, listener e delegate
consentono di verificare il rilascio visibile. `AppExtensionProcess` è uno struct:
non si pretende di osservare tutti i riferimenti interni del framework.

Guardie indipendenti: provider 25 s, host 35 s. Il runner si ferma a UNKNOWN o
cleanup incompleto. Il suo exit0 indica raccolta completa, **non** cinque stop
riusciti o ammissione del launcher. Nessuna prova pre-main.

[Rapporto](../../../docs/superpowers/verification/2026-09-24-addon-interruption.md).
