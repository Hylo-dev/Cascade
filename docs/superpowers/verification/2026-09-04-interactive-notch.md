# Verifica del notch interattivo

Branch: `codex/interactive-notch`. Ambiente: macOS 27.0 beta, Xcode 27 beta,
deployment target macOS 14. Build locale Debug con firma ad hoc verificata.

## Implementazione

- Aptica AppKit `.alignment` richiesta all'ingresso accettato in hover, prima
  dell'apertura. Preferenza disattivabile; nessun impulso sugli eventi automatici.
- Superfici compatte ed estese per Live Activities, controlli SwiftUI interattivi,
  maschera coincidente con la sagoma e coda transitoria limitata a otto elementi.
  Gli avvisi durano quattro secondi e restituiscono spazio all'attività persistente.
- Monitor Classic Bluetooth tramite callback IOBluetooth. Baseline iniziale
  silenziosa, deduplicazione e ricostruzione dopo wake; nessuna discovery o polling.
- Tentativo selettivo di chiusura dei banner nativi tramite Accessibilità,
  correlato a un collegamento reale recente. Osserva soltanto Control Center.
  Una finestra non riconosciuta non viene chiusa. L'anteprima non arma il servizio.
- Contratto `NowPlayingProviding`, snapshot immutabili, capacità dei comandi e
  contenuti musicali compatti/estesi. Provider dimostrativo esplicito senza audio;
  collegamento a player reali ancora da implementare.

Nessuna nuova dipendenza esterna. BoringNotch è stato esaminato come riferimento;
non è stato copiato codice. Gli snapshot consultati non contengono un monitor
Bluetooth o un override nativo riutilizzabile.

## Verifiche automatiche

- Package CascadeKit: **47 test in 10 suite, tutti superati**, per geometria, molle, hover, routing
  degli eventi, lifecycle, priorità delle attività e snapshot musicali.
- `scripts/test-bluetooth.sh`: 10 verifiche monitor e 13 verifiche di riconoscimento
  selettivo dei banner. I test del monitor non simulano un collegamento hardware.
- Build completa `xcodebuild` Debug con firma locale ad hoc: riuscita; `codesign --verify --deep --strict` superato.
- Integrazioni Bluetooth verificate con Swift 6 e isolamento predefinito MainActor.
- `git diff --check`: nessun errore.

La revisione indipendente conclusiva non ha rilevato altri difetti nel perimetro
esaminato. Sei test di regressione aggiunti in revisione verificano widget coperti
da un'attività, animazioni a schermo bloccato, eliminazione degli avvisi ricevuti
durante il blocco, hover sulle estensioni compatte, durata del trascinamento e
assenza di segmenti del puntatore obsoleti dopo stop/start. Il campionamento del
puntatore su pressione/rilascio del mouse supera il limite di frequenza usato
per i soli movimenti. La build finale successiva alle correzioni è riuscita.

Totale: **70 verifiche automatiche superate** (47 package + 10 monitor + 13 policy).

Comandi ripetibili:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-notch-module-cache SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cascade-notch-module-cache /Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift test --package-path CascadeKit --scratch-path /private/tmp/cascade-notch-build --disable-sandbox
scripts/test-bluetooth.sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -project Cascade.xcodeproj -scheme Cascade -configuration Debug -derivedDataPath /private/tmp/cascade-notch-derived CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
git diff --check
```

## Limiti verificati

**L'override nativo non è ancora convalidato sul dispositivo.** Il sistema espone
stringhe e componenti compatibili con l'approccio scelto, ma non è stato possibile
confermare l'albero Accessibilità di un banner reale. Lo stato «monitoraggio
attivo» conferma soltanto la registrazione dell'osservatore. Non dimostra che un
banner sia stato chiuso. La chiusura avviene dopo la comparsa e può lasciare un
breve lampo; non è una soppressione preventiva.

Il riconoscimento richiede nome esatto del dispositivo, testo di collegamento
localizzato dal sistema, finestra compatta non modale e un solo controllo di
chiusura esplicito. Richieste di associazione, codici, input, altre azioni,
finestre troncate o non riconosciute sono escluse. La verifica su macOS 14–26 e
sulle altre lingue resta necessaria. Dopo un riavvio di Control Center si può
riattivare l'osservatore aprendo il menu o usando «Riprova».

IOBluetooth copre i dispositivi Classic esposti dal framework; non garantisce
gli accessori esclusivamente BLE. Le letture dei record Bluetooth già presenti
sono sincrone sul main actor: non interrogano il dispositivo remoto, ma il loro
costo reale resta da misurare. Le letture AX potenzialmente bloccanti sono su un
worker e hanno limiti di tempo, finestre e nodi.

L'architettura evita timer ricorrenti per Bluetooth e metadati. Il progresso
musicale ha un aggiornamento visivo al secondo soltanto durante riproduzione
nella vista estesa. Queste proprietà non sostituiscono una misura energetica.

## Verifica manuale ancora da eseguire

La revisione automatica delle autorizzazioni aveva richiesto consenso esplicito
all'esecuzione della build locale. L'utente ha poi autorizzato avvio e riavvio.
Nessun aggiramento del blocco è stato tentato. Accessibilità non risulta ancora
abilitata per una prova attendibile del servizio.

Il primo controllo del solo bundle identifier aveva avviato una precedente build
rossa nella DerivedData di Xcode. La verifica successiva del percorso del processo
e dei crash report ha identificato un crash reale della build nuova: IOBluetooth
invoca il selector di connessione sulla propria `coordinatorQueue`, anche durante
la registrazione iniziale. Il selector isolato MainActor causava un assertion trap
in Swift 6. La compilazione non rilevava questa violazione dinamica; il precedente
harness del monitor usava Swift 5. È necessaria una regressione che eserciti la
callback Objective-C da un thread in background con le stesse impostazioni Swift 6
dell'app, seguita da avvio verificato del percorso esatto e del menu aggiornato.

1. Avviare la build, entrare nel notch dal corpo centrale e dalle estensioni
   compatte: un impulso all'ingresso, nessuno durante la permanenza.
2. Abilitare l'anteprima musicale dal menu; verificare play/pausa, precedente,
   successivo e il passaggio da compatto a esteso. Non viene riprodotto audio.
3. Provare un avviso Bluetooth durante la musica e verificarne il ritorno dopo
   quattro secondi. Una pagina già aperta deve mantenere i controlli correnti.
4. Collegare e scollegare un accessorio reale; verificare nome, stato, assenza di
   duplicati e nessun avviso per connessioni già presenti all'avvio.
5. Abilitare esplicitamente Accessibilità dal menu e riaprire il menu. Ripetere
   un collegamento che produce un banner nativo; verificare con Accessibility
   Inspector il riconoscimento e la chiusura effettiva prima di dichiarare supporto.
6. Verificare che associazione, passkey e altre notifiche restino intatte;
   disattivare la sostituzione e controllare che non avvengano chiusure tardive.
7. Provare click nella barra dei menu fuori sagoma e trascinamento di un controllo
   oltre il bordo, lock/unlock, sleep/wake, Mission Control e cambio display.
8. Misurare CPU/energia a riposo e con vista estesa usando Instruments o Activity
   Monitor; ripetere con Riduci movimento attivo.

Build: `/private/tmp/cascade-notch-derived/Build/Products/Debug/Cascade.app`.

## Esito della correzione e del riavvio

Il monitor ora riceve le callback tramite un osservatore non isolato e inoltra
soltanto metadati copiati al MainActor in modo asincrono. Identità della sessione,
token ed epoca della baseline escludono callback obsolete dopo stop/start e wake.
Nessun lock resta acquisito durante chiamate al framework o dispatch. Il test del
selector Objective-C da background gira con Swift 6; il test dell'epoca impedisce
a una callback già accodata di modificare la nuova baseline. Revisione mirata
conclusa senza altri blocchi.

Avvio della build esatta verificato: il processo esegue
`/private/tmp/cascade-notch-derived/Build/Products/Debug/Cascade.app/Contents/MacOS/Cascade`.
Il menu effettivo contiene «Feedback aptico in hover», «Avvisi Bluetooth»,
«Consenti Accessibilità…», «Anteprima Live Activity musicale» e «Prova avviso
Bluetooth». L'istanza precedente nella DerivedData di Xcode è stata chiusa.
L'override nativo rimane da convalidare dopo concessione esplicita di Accessibilità
e collegamento reale; l'avvio riuscito non dimostra la chiusura di un banner.
