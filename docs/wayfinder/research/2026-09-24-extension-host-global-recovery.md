# ExtensionFoundation: recupero globale e lifetime prima di main

Ricerca documentale del 24 settembre 2026. Sole fonti Apple e SDK pubblico locale; nessuna compilazione, esecuzione nativa, terminazione o modifica dei permessi.

Aggiornamento successivo: l'utente esclude il contatto con Apple. La
[ricerca nelle fonti pubbliche](2026-09-24-extension-startup-documentation.md)
approfondisce il contratto senza dipendere da una richiesta di supporto. Le prove
positive successive sono nel [rapporto di recupero](../../superpowers/verification/2026-09-24-addon-global-recovery.md).

## Esito operativo

La policy [native-addon-global-recovery](../../superpowers/specs/2026-09-10-addon-control-policy.md#recupero-globale-di-emergenza--decisione-del-24-settembre-2026) consente il riavvio globale come ultima risorsa, ma conserva uscita verificata dell'incarnazione, assenza di orfani anche prima di main e divieto di ripartire con la vecchia catena di stato ignoto. Le fonti consultate **non bastano ancora a qualificare questo intero percorso** per un addon esterno. Documentano avvio, riuso e rilascio del processo, senza precisare la garanzia alla morte dell'host durante startup/dyld. Non è una conclusione di impossibilità generale.

## Contratto pubblico trovato

| Aspetto | Contratto e limite |
| --- | --- |
| Creazione | `AppExtensionProcess` riusa un processo esistente oppure ne crea uno. L'istanza è restituita quando l'estensione è avviata e pronta per XPC; non è un handle consegnato prima dello startup. [Tipo](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess), [inizializzatore asincrono](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/init(configuration:)-38zf). |
| Rilascio | `invalidate()` termina il processo se quell'oggetto rappresenta l'ultima connessione. Con più connessioni il processo resta vivo fino alla chiusura dell'ultima. Il metodo non restituisce una ricevuta di uscita né documenta un termine massimo. [Metodo](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/invalidate()), [guida](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app). |
| Morte dell'host | La guida documenta l'invalidazione automatica quando non si conserva il riferimento. Non specifica separatamente uscita normale, crash dell'host e richiesta di avvio ancora pendente, né l'inizio dell'obbligo di cleanup prima di main. Equiparare queste situazioni è un'inferenza da qualificare. [Guida](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app). |
| Riuso | Non è lecito assumere un processo nuovo per ogni costruzione. Le pagine citate non delimitano il riuso tra distinti host/client, né promettono esclusività. Un secondo osservatore che ottiene un proprio `AppExtensionProcess` può aggiungere una connessione e alterare proprio la condizione “ultima connessione”. [Tipo](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess), [guida](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app). |

L'inizializzatore asincrono documenta esecuzione dello startup prima del ritorno e possibile sospensione successiva senza connessione XPC. Non documenta che cancellare la Swift `Task` uccida un processo già creato o completi il cleanup. [Inizializzatore](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/init(configuration:)-38zf).

## Osservazione: tre momenti distinti

1. **Dopo startup, prima del primo messaggio applicativo:** esiste `Configuration.onInterruption`, configurata già nella richiesta di avvio. La documentazione non richiede un primo messaggio applicativo riuscito. È una notifica pubblica di perdita del processo associato; può essere correlata localmente alla propria richiesta. La pagina della proprietà parla di uscita inattesa, l'overview di uscita per qualunque ragione: non estendere senza verifica la consegna al proprio `invalidate()`. [Proprietà](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/configuration/oninterruption), [overview](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess).
2. **Callback bloccato:** `onInterruption` non documenta coda, termine di consegna o indipendenza da una coda bloccata. Il distinto `NSXPCConnection.interruptionHandler` usa la stessa coda degli altri handler. La pagina web descrive un ordine dopo gli altri callback, ma l'header pubblico SDK 27 specifica che l'ordine non è garantito: non basare il controllo su quell'ordine. Rimane il problema di una coda bloccata, distinto dalla morte del processo. L'invalidazione della connessione non basta da sola a provare l'uscita. [Foundation](https://developer.apple.com/documentation/foundation/nsxpcconnection/interruptionhandler), [header SDK 27](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Foundation.framework/Versions/C/Headers/NSXPCConnection.h:104>).
3. **Dalla creazione fino allo startup:** nell'interfaccia pubblica esaminata non compare un PID/token/handle d'incarnazione anticipato, un osservatore di uscita trasferibile o un'API per attendere quell'uscita da un altro processo. `AppExtensionIdentity` identifica l'estensione, non una sua esecuzione. `onInterruption: () -> Void` non consegna identità o stato d'uscita e il suo host morto non può registrarne l'esecuzione. [SDK 27, interfaccia pubblica, righe 160–178 e 237–258](</Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/ExtensionFoundation.framework/Versions/A/Modules/ExtensionFoundation.swiftmodule/arm64e-apple-macos.swiftinterface:237>).

Il terzo punto è l'esito circoscritto dell'inventario di queste API; non esclude ogni possibile soluzione pubblica macOS.

## Prove disponibili e prossimo passo

Il [P0](../../superpowers/verification/2026-09-09-addon-runtime-P0.md) registra uscita dopo chiusura normale dell'host e dopo SIGKILL dell'host con worker non cooperativo, nella fixture su macOS 27 beta. Il flusso era già arrivato all'autenticazione XPC. Non prova morte dell'host durante dyld, initializer in sospeso, altro editore o altri sistemi operativi; il medesimo P0 registra anche mancato arresto selettivo tramite invalidazione.

**Non è stato individuato un esperimento completo, finito e sicuro per il gate pre-main con le sole interfacce esaminate.** Manca prima dell'avvio un osservatore autentico dell'incarnazione, indipendente dall'host destinato a morire, che non mantenga vivo il provider. Un marker in un costruttore C esplorerebbe il tratto prima di main dopo l'esecuzione di quel costruttore; non coprirebbe creazione → primo initializer. Un handshake seguito da spin esplorerebbe una fase ancora successiva. Non chiamare tali prove “copertura dalla nascita”.

Il prossimo avanzamento utile richiede un contratto Apple o un'API pubblica verificabile che chiarisca: cleanup su host-death anche con avvio pendente; confini del riuso fra client; osservazione dell'uscita della specifica incarnazione senza una connessione che la trattenga. Questi sono i prerequisiti per definire poi una prova finita; non è stata inviata alcuna richiesta ad Apple. Intanto il packaging esterno e la qualificazione dopo startup possono proseguire, mantenendo il gate complessivo non superato, senza autorizzare il riavvio con catena ignota.
