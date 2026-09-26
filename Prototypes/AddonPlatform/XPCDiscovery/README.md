# Discovery dal broker XPC — fixture diagnostica

Confronta la ricerca dell'addon esterno P0 nell'app e nel broker sandboxed.
Non costruisce AppExtensionProcess, non carica addon e non qualifica un launcher.
Campiona API legacy e Monitor moderno per due secondi.

Richiede Xcode-beta, il certificato fissato nello script e contenitore P0 registrato.
Non cambia l'abilitazione. Prima di interpretare un confronto negativo, l'app deve
trovare `hylo.Cascade.AddonProbeContainer.Provider`.

```sh
python3 Prototypes/AddonPlatform/XPCDiscovery/run_discovery.py --build-only
python3 Prototypes/AddonPlatform/XPCDiscovery/run_discovery.py --run /percorso/stampato
```

Exit 0 indica solo risposta autenticata. Leggere legacy/modern/disabled/unapproved
di entrambi i chiamanti. Il runner verifica hash e salva log/manifest in una nuova
cartella DerivedData a ogni build. Non ripetere un comando nella stessa cartella
se si vogliono preservare i log.

`--run-browser` crea il browser Apple dal broker per ispezione manuale, uscita host
60 s dopo la risposta e guardia 90 s. Non è consenso qualificato. Richiede desktop
sbloccato: prima esecuzione non ispezionabile, nessuna modifica dei permessi.

[Risultati](../../../docs/superpowers/verification/2026-09-24-addon-xpc-frontier.md):
app trova provider, broker nessuna identità e un elemento non approvato.
