# Osservare un provider durante lo startup

Fixture isolata: processo root → broker XPC sandboxed → estensione esterna.
Un osservatore separato autentica il provider prima che il canale applicativo sia
pronto, poi il runner registra l'uscita con kqueue e chiede una nuova challenge.
Soltanto dopo la conferma viene iniettato lo stop/crash. Nessun launcher produttivo.

Due varianti della stessa prova:

- `--build-only`: blocco dentro `AppExtension.init`.
- `--build-premain`: blocco in un costruttore C dell'immagine principale, prima
  dell'entry point dell'estensione. La guardia e l'UUID sono riusati dal codice Swift.
  Non copre l'intervallo fra creazione del processo e quel costruttore.

Il runner produce un bundle firmato e un osservatore in una directory DerivedData
univoca; poi `python3 run_startup.py --run PRODUCTS` esegue il controllo negativo,
lo sblocco verso il normale canale e quattro guasti: stop/crash broker, quit/crash root.
Arresto al primo risultato non PASS o cleanup incompleto. Deadline di misura 8 secondi;
le guardie indipendenti scadono più tardi e non possono produrre un PASS.

Il trasporto diagnostico usa messaggi Mach con audit trailer del kernel, requisito
firma leaf + identifier + CDHash della build esatta, percorso del bundle e nonce
nuovo dopo EV_RECEIPT. L'osservatore registra un nome univoco tramite la API pubblica
ma deprecata `bootstrap_register`; il solo provider di prova aggiunge il lookup
esatto a quel nome. App Sandbox resta attiva. Non è il profilo del prodotto e non
è una decisione sul futuro trasporto SDK. Il teardown verifica che il nome non
sia più risolvibile, senza cancellare servizi altrui.

L'iniziale tentativo AF_UNIX nel container non ha superato il bind: EPERM prima
di avviare il provider. Nessun grant TCC è stato modificato per aggirarlo.

Risultati, build, entitlements, hash, tentativi falliti e limiti sono conservati
in `docs/superpowers/verification/2026-09-25-addon-startup-observation.md`.
