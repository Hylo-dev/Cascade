# Integrare Spotlight, notifiche e attività di macOS: fattibilità

Ricerca Wayfinder del 4 settembre 2026. Baseline da valutare: progetto con deployment macOS 14, distribuzione diretta e Homebrew. Questa nota documenta possibilità e limiti, senza scegliere il comportamento del prodotto. Sono stati letti documentazione Apple, SDK locale macOS 27.0 e sorgenti pubblici; non sono stati aperti database personali, intercettati eventi, modificati permessi o provati comportamenti sulla UI dell'utente.

Sorgenti fissati: Sapphire `e718d72feba61538a61ffc14e3abc32a9b4e35b9`; FineTune `2285279d36d3f8115c1c2d4aecd904f1bdf96a51`. La presenza di codice dimostra una tecnica implementata, non la sua affidabilità su ogni versione del sistema.

## Matrice di fattibilità

| Capacità | OS di riferimento | API e permessi | Evidenza e limite |
|---|---|---|---|
| Richiamare il vero Spotlight | macOS 14 e successivi | Scorciatoia di sistema; automazione eventualmente con Accessibilità | L'apertura interattiva è documentata; integrazione automatica da collaudare. |
| Spostare Spotlight sotto il notch | Ogni versione supportata | Accessibility pubblica, se `AXPosition` è modificabile; autorizzazione Accessibilità | Possibile esperimento, non contratto documentato di Spotlight. |
| Cambiare materiale, forma o ospitare Spotlight dentro Cascade | Nessuna API verificata | Eventuali meccanismi privati/non documentati | Non promettere controllo della UI di un altro processo. |
| Ricerca disegnata da Cascade | macOS 14; capacità aggiuntive da 15 | AppKit/SwiftUI, `NSMetadataQuery`, Core Spotlight | UI e ricerca di file possibili; parità funzionale completa non dimostrata. |
| Notifiche proprie | macOS 14+ | `UNUserNotificationCenter`, autorizzazione Notifiche | API pubblica limitata alla propria app/estensione. |
| Notifiche di app non integrate | Matrice 14/15/26/27 da provare | Accessibility oppure database/SPI privati; permessi distinti | Copertura universale non garantita; Accessibilità non equivale ad accesso al database. |
| Connessioni Bluetooth | macOS 14+ | IOBluetooth pubblico; CoreBluetooth e relativa autorizzazione quando usato | Rilevamento disponibile; verificare Classic, BLE, riattivazione e cambi profilo. |
| Batteria di ogni accessorio | Dipende da dispositivo e OS | GATT pubblico dove esposto; altrimenti cache/proprietà non documentate | Dato opzionale; nessuna fonte universale verificata. |
| Metadati e comandi multimediali globali | 14 e versioni successive con differenze | MediaRemote privato; adattatori per singole app | Funzione realizzabile in progetti esistenti, ma fragile e dipendente dai player. |
| Rilevamento audio/processi e cattura | Taps da macOS 14.2 | HAL/Core Audio pubblico; consenso registrazione audio per cattura | Attività audio non significa titolo disponibile né segnale udibile. |
| Vibrazione all'apertura | macOS 10.11+ | `NSHapticFeedbackManager`, hardware e preferenze utente | Richiesta pubblica; il sistema può sopprimerla. |
| Attività di iPhone nel notch | Menu bar di sistema da macOS 26 | ActivityKit/Continuity del sistema | Nessun contratto verificato per trasferire attività altrui nell'host Cascade. |

Le fonti e le condizioni delle righe sono dettagliate sotto. La distribuzione fuori Store non trasforma API private o archivi interni in interfacce supportate e non elimina i controlli del sistema.

## Spotlight: quattro capacità diverse

Apple documenta Comando-Spazio come comando per aprire e chiudere Spotlight. Per Cascade sono da verificare l'invocazione dell'app di sistema e, separatamente, la simulazione della scorciatoia: scorciatoie cambiate dall'utente, focus e stato già aperto possono alterare il risultato. Il metodo pubblico `NSWorkspace.showSearchResults(forQueryString:)` apre invece una finestra di ricerca **Finder**: non incorpora il pannello Spotlight. [Scorciatoie Apple](https://support.apple.com/en-gb/guide/mac-help/mh26783/mac), [NSWorkspace](https://developer.apple.com/documentation/appkit/nsworkspace/showsearchresults(forquerystring:)).

Accessibility consente di interrogare la UI di un processo e verificare se un attributo sia scrivibile. Questo offre un percorso sperimentale per il posizionamento, ma Apple non garantisce qui che la finestra di Spotlight esponga una posizione modificabile. Occorre controllare `AXUIElementIsAttributeSettable`, esito della modifica e comportamento nei successivi aggiornamenti. È necessario lo stato di client Accessibility autorizzato; l'API può anche restituire attributo non supportato o errore di comunicazione. [Attributi modificabili](https://developer.apple.com/documentation/applicationservices/1459972-axuielementisattributesettable), [Autorizzazione Accessibility](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions).

Non è stata individuata una API pubblica per sostituire il materiale di Spotlight, modificarne la gerarchia SwiftUI/AppKit o ospitarlo come contenuto di Cascade. Un allineamento di finestre separate, se funzionasse, non dimostrerebbe queste capacità. Si tratta di **assenza di un contratto documentato trovato**, non di una dimostrazione d'impossibilità assoluta.

Una ricerca propria può utilizzare `NSMetadataQuery` per metadati di file e volumi e disegnare liberamente il pannello. Core Spotlight permette inoltre di interrogare contenuti indicizzati dall'app; la documentazione introduce ricerca semantica da macOS 15. Questo non equivale ad avere tutte le fonti, azioni e capacità del vero Spotlight. La richiesta «identica» resta da scomporre in un confronto osservabile prima di stimare una replica. [Ricerca dei metadati](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/SpotlightQuery/Concepts/QueryingMetadata.html), [Interfaccia di ricerca Core Spotlight](https://developer.apple.com/documentation/corespotlight/building-a-search-interface-for-your-app).

## Notifiche di altre app

`UNUserNotificationCenter` gestisce notifiche della propria app o estensione. La relativa autorizzazione non offre un flusso delle notifiche ricevute da tutte le altre applicazioni. [Documentazione Apple](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter).

Un osservatore Accessibility riceve eventi degli elementi UI supportati dall'app osservata. Gli eventi AX non sono automaticamente i payload delle notifiche utente; inoltre l'oggetto Accessibility globale non supporta tali osservazioni. Leggere banner o Centro Notifiche tramite AX è quindi un candidato da prototipare con permesso Accessibilità, non un listener universale. Assenza di banner, raggruppamento, anteprime nascoste e Focus richiedono casi distinti. [AXObserverAddNotification](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification), [Impostazioni notifiche](https://support.apple.com/guide/mac-help/notifications-settings-mh40583/mac).

Sapphire usa un'altra tecnica: `NotificationManager` apre in sola lettura SQLite interno di Notification Center, interroga periodicamente `record` e decodifica un plist con chiavi interne. Il percorso previsto da Sequoia è `~/Library/Group Containers/group.com.apple.usernoted/db2/db`; sono presenti fallback storici sotto `DARWIN_USER_DIR`. Il polling predefinito è cinque secondi. Ciò dimostra l'accesso tentato ai record conservati, non l'intercettazione in tempo reale di ogni evento. Percorso, schema, conservazione e payload non costituiscono un'API Apple. [Sapphire: sorgente verificato](https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Services/Miscellaneous/NotificationManager.swift#L197).

Sapphire dispone anche di controlli Full Disk Access, con SPI TCC caricati dinamicamente e un fallback. Questo **non dimostra** quale permesso sia necessario e sufficiente per quello specifico archivio su ogni macOS. La verifica deve misurare accesso negato/concesso in un account di prova; nessuna lettura di dati reali è avvenuta durante questa ricerca. Restano da decidere, dopo le misure, copertura accettabile, duplicazione dei banner, conservazione e trattamento delle anteprime protette. [Sapphire: permessi](https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/App/PermissionsManager.swift#L137).

## Bluetooth e batteria

`IOBluetoothDevice.register(forConnectNotifications:selector:)` registra callback di connessione; la disconnessione si osserva sul dispositivo. Sapphire impiega effettivamente questo percorso. Per BLE, `retrieveConnectedPeripherals(withServices:)` filtra i dispositivi per servizi: non restituisce un inventario indiscriminato di tutti gli accessori. L'interazione CoreBluetooth richiede relativa autorizzazione e descrizione d'uso. [IOBluetooth](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/register(forconnectnotifications:selector:)), [CoreBluetooth](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/BestPracticesForInteractingWithARemotePeripheralDevice/BestPracticesForInteractingWithARemotePeripheralDevice.html), [Permessi Apple](https://developer.apple.com/documentation/technologyoverviews/device-sensors).

Sapphire combina lettura del Battery Service GATT, cache Bluetooth, proprietà specifiche e output di `system_profiler`. La disponibilità di batteria sinistra/destra/custodia dipende dalla fonte; i dati in cache possono essere vecchi. La connessione non deve pertanto essere interpretata come garanzia di batteria disponibile. Cambiare uscita audio e connettere un dispositivo sono anche eventi diversi, da correlare nella futura specifica. [Sapphire: batteria](https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Services/Bluetooth/BluetoothBatteryReader.swift), [Connessioni](https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Services/Bluetooth/BluetoothManager.swift).

## Media globali, browser e attività

`MPNowPlayingInfoCenter` pubblica informazioni sui media riprodotti dalla propria app: non è documentato come lettore globale. Anche il nuovo framework NowPlaying presentato a WWDC26, disponibile nel SDK da macOS 27 e documentato ancora beta, serve a pubblicare sessioni locali o di dispositivi remoti. Non risolve automaticamente la lettura delle sessioni altrui. [Media Player](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter), [NowPlaying](https://developer.apple.com/documentation/nowplaying).

Sapphire avvia `/usr/bin/perl` con `MediaRemoteAdapter.framework` per ricevere metadati e inviare comandi. L'autore dell'adattatore descrive questo meccanismo per il supporto anche dopo macOS 15.4, usando un binario di sistema con accesso a MediaRemote. È un percorso privato da sottoporre a verifica su ogni versione, non una garanzia Apple. Copertina, titolo, controlli e identificazione del player possono mancare; l'adattatore stesso documenta risultati nulli e metadati opzionali. [Sapphire: controller](https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Services/Music/NativeMediaController.swift#L134), [MediaRemote Adapter](https://github.com/ungive/mediaremote-adapter).

Core Audio offre invece process taps pubblici da macOS 14.2, con consenso alla registrazione dell'audio e `NSAudioCaptureUsageDescription` per la cattura. Le proprietà HAL distinguono I/O attivo e stream di uscita attivo; non certificano un segnale non silenzioso e non forniscono titolo o URL della scheda browser. FineTune osserva i processi audio e usa anche `responsibility_get_pid_responsible_for_pid`, privata, per ricondurre helper/XPC all'app responsabile. Browser, scheda, processo audio e sessione Now Playing devono restare identità distinte. [Taps Apple](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps), [Stato output](https://developer.apple.com/documentation/coreaudio/audiohardwareprocess/isrunningoutput), [FineTune: monitor](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Monitors/AudioProcessMonitor.swift#L88).

Le «live activities» di Cascade sono un modello del prodotto da specificare. ActivityKit non fornisce un elenco universale: `Activity.activities` riguarda le attività della propria app. Apple documenta l'arrivo delle attività **da iPhone** nella menu bar del Mac da Tahoe 26 tramite iPhone Mirroring; questo non autorizza un host terzo a trasferirle nel proprio notch. Nel SDK locale 27.0 `Activity` e `ActivityAttributes` restano marcati non disponibili per macOS. [Activity](https://developer.apple.com/documentation/activitykit/activity), [Continuity e Live Activities](https://support.apple.com/en-us/120684).

## Feedback aptico ed esperimenti necessari

AppKit offre feedback aptico pubblico dal 10.11. Si può richiedere un impulso sincronizzato con il rendering all'apertura. `defaultPerformer` tiene conto del dispositivo e delle preferenze; il commento ufficiale nel SDK specifica che il sistema può sopprimere la richiesta, ad esempio se il dito non tocca il trackpad. Non è quindi garantibile una vibrazione sempre percepibile dopo un hover. [NSHapticFeedbackManager](https://developer.apple.com/documentation/appkit/nshapticfeedbackmanager); verifica locale: `AppKit.framework/Headers/NSHapticFeedback.h`, righe 15–38, SDK macOS 27.0.

Prima delle decisioni di prodotto servono esperimenti circoscritti:

1. Spotlight: apertura, attributi AX e posizionamento su 14/15/26/27, più schermi, fullscreen, Spaces, apertura ripetuta e scorciatoia personalizzata. Confrontare una UI propria solo dopo aver misurato quella di sistema.
2. Notifiche: account di prova e notifiche sintetiche da app diverse; banner disabilitati, Focus, anteprime nascoste, gruppi, chiusura sessione, riavvio e revoca permessi. Misurare copertura, latenza e duplicati separatamente per AX e archivio.
3. Media: Safari/Chromium, più schede e player concorrenti, pause, stream senza metadati, contenuti protetti, cambio uscita e revoca consenso audio. Verificare 14.0 rispetto a 14.2 e versioni successive.
4. Dispositivi e aptica: cuffie Apple/non Apple, tastiera/mouse BLE, batteria assente o vecchia, sleep/wake, trackpad interno/esterno e mouse. Registrare stati «non disponibile» separatamente dagli errori.

Questi esperimenti chiariscono confini di supporto; nessuno è stato eseguito in questa ricerca documentale.
