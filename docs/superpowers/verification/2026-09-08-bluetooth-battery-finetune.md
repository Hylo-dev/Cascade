# Batteria Bluetooth, AirPods e diagnosi volume

8 settembre 2026. Richiesta: carica circolare sul lato destro dell'avviso,
AirPods rotanti e verifica dell'override volume confrontando FineTune.

## Diagnosi riprodotta

FineTune 1.9.0 (38) è in esecuzione con `mediaKeyControlEnabled: true` e HUD
Tahoe. L'elenco pubblico `CGGetEventTapList` mostra il suo tap HID abilitato
per i soli eventi systemDefined. Non mostra un tap volume di Cascade.

I log TCC del processo Cascade 61596 riportano `result: false` per
`kTCCServiceAccessibility`. Dopo build e riavvio, il processo 65586 conferma
`Volume routing status: permissionRequired`. La causa accertata dell'assenza
del filtro è il permesso negato alla build attuale; non è dimostrato che
FineTune stia sottraendo eventi a un tap Cascade già autorizzato.

Il codice FineTune esaminato è il commit
`2285279d36d3f8115c1c2d4aecd904f1bdf96a51`:
[MediaKeyMonitor](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Keys/MediaKeyMonitor.swift).
Consuma i tasti con un tap HID e modifica il volume tramite il proprio
backend, poi presenta il suo HUD. Non disabilita globalmente l'OSD macOS.
Cascade conserva la propria implementazione CoreAudio e la propria coda;
non sono state copiate sorgenti GPL né modificate preferenze FineTune.

## Implementazione

- Batteria privata IOBluetooth con firme runtime verificate, fallback IORegistry
  attribuito tramite indirizzo esatto. I dati non disponibili restano ignoti;
  la cache persistente fornisce solo identità del modello, mai carica storica.
- Lettura alla connessione fuori dal main actor, con al massimo un retry.
  Cancellazione e identità dell'evento impediscono aggiornamenti obsoleti.
- Carica circolare con valore e label accessibile; minimo degli auricolari noti,
  custodia separata. Gli zero ambigui delle API private sono ignoti; gli zero
  espliciti del registry sono conservati.
- AirPods e Pro: geometria 3D originale, atlanti precalcolati, un giro di tre
  secondi nel compositor. Movimento ridotto statico, teardown e cancellazione
  del caricamento quando la vista si nasconde. AirPods Max usa il simbolo.
- `updateNotice` aggiorna solo un avviso esistente con identità/sorgente uguali
  e revisione maggiore, senza prolungare la scadenza o modificarne la priorità.
  L'integrazione arma l'override Bluetooth soltanto per l'evento iniziale.
- Corretto il crash `addressString` IUO in disconnessione, riprodotto prima
  della correzione. I callback nil sono protetti e il token conserva l'identità
  quando il framework ha già eliminato i dati del dispositivo.
- Volume: recupero limitato del tap dopo disabilitazione del sistema, rinnovo
  dopo sleep/sessione, nuova verifica del permesso al ritorno nell'app/menu.
  I repeat di mute non ripetono scritture, letture o avvisi.

## Verifiche eseguite

- 85 test CascadeKit, 12 suite: `/private/tmp/cascade-airpods-kit-tests.log`.
- 37 controlli volume Swift 6 con warning come errori:
  `/private/tmp/cascade-airpods-volume-tests.log`. La regressione del mute
  tenuto premuto falliva prima del fix (`cascade-volume-red.log`).
- Harness Bluetooth e 13 controlli policy legacy passati:
  `/private/tmp/cascade-airpods-bluetooth-tests.log`.
- Build Debug completa e `codesign --verify --deep --strict` riusciti:
  `/private/tmp/cascade-airpods-app-build.log`. Unico warning della build:
  estrazione metadata AppIntents saltata perché non usati.
- App aggiornata avviata tramite CUA dal percorso
  `/private/tmp/cascade-airpods-derived/Build/Products/Debug/Cascade.app`.

- Test grafico delle factory e del ciclo animazione superato:
  `zsh scripts/test-bluetooth-presentation.sh /private/tmp/cascade-airpods-derived/Build/Products/Debug`.
  Controllati durata di tre secondi, nessun riavvio all’arricchimento, Movimento
  ridotto, cancellazione rapida e rilascio delle risorse. Render reale delle
  factory: `/private/tmp/cascade-bluetooth-presentation/notices.png`.
  Il render verifica i contenuti, non una nuova connessione Bluetooth reale.

## Confini della verifica

Il probe Bluetooth non aveva dispositivi connessi; batteria e riconoscimento
sono verificati tramite runtime, parser e fixture, non attraverso una nuova
connessione hardware. L'anteprima nel menu usa valori dichiaratamente sintetici.

L'override effettivo del volume richiede ancora di concedere Accessibilità a
questa build dal sistema e provare tasti reali. Il test in un processo CLI già
autorizzato non dimostra il permesso dell'app. Nessun certificato di sviluppo
valido è disponibile: la build è firmata ad hoc e una ricompilazione può
richiedere una nuova autorizzazione macOS.

Non sono state chiuse app audio né cambiati volume, impostazioni FineTune o
permessi di sistema. Se FineTune reinstalla un proprio tap prima di Cascade,
la priorità fra le due app va verificata sul gesto reale; non viene introdotto
un ciclo di reinstallazione dei tap in competizione.

Fonti per i metadati: runtime Apple installato e
`IOBluetoothUI.framework/Resources/AssetPaths.plist`,
[Hammerspoon battery](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/battery/libbattery.m),
[implementazione ESPHome AirPods](https://github.com/myhomeiot/esphome-components/blob/main/examples/ble_gateway/airpods.yaml).
