# Broker XPC e addon ExtensionFoundation esterno — 24 settembre 2026

**Esito aggiornato: il broker raggiunge il monitor, ma non dispone del consenso osservato nell'app. Composizione non qualificata.** La prova successiva dell'agente principale trova il provider dalla GUI; dal broker vede un candidato non approvato e nessuna identità utilizzabile. Il costruttore moderno non rifiuta il target `.xpc`. Resta da trovare un percorso pubblico di consenso per quel contesto e da provare lancio e proprietà della durata. Il contenitore esterno `.app` con `.appex` rimane coerente con la specifica; questo rapporto non dimostra l'impossibilità generale del broker e non autorizza un launcher produttivo.

Indagine documentale delegata: fonti Apple, SDK pubblico locale e repository; questo ricercatore non ha eseguito build o fixture né modificato codice. La successiva prova nativa è stata eseguita dall'agente principale e il suo log è stato letto qui, distinguendolo dalle fonti documentali. La prima interrogazione al grafo MCP ha restituito progetto Cascade non indicizzato; la lettura locale è il fallback previsto.

## Domanda e confine della composizione

Il disegno candidato è:

```text
Cascade.app — XPC → broker fidato incluso in Cascade
                         │
                         └─ ExtensionFoundation → provider.appex
                                                   dentro un'altra app installata
```

Il broker contiene soltanto infrastruttura fidata; il codice dell'addon rimane nel processo dell'estensione. La [specifica, sezioni 4 e 8](../../superpowers/specs/2026-09-09-addon-runtime-design.md) ammette il contenitore standalone ed esclude il caricamento di codice addon nella GUI. La separazione qui disegnata rispetterebbe quel confine **se** discovery e lancio dal broker fossero supportati; non basta nominare XPC per ottenerli.

Le prove esistenti coprono due archi diversi:

| Arco | Evidenza locale | Cosa non dimostra |
| --- | --- | --- |
| App host → `.appex` esterna | [P0](../../superpowers/verification/2026-09-09-addon-runtime-P0.md): discovery, echo autenticato e processo separato; morte dell'host termina il provider nelle esecuzioni osservate | Hosting da `.xpc`, identità di un altro editore, macOS 14/15/26 |
| App → broker `.xpc` → worker `.xpc` incluso nel broker | [XPCBroker](../../superpowers/verification/2026-09-24-addon-xpc-broker.md): uscita ordinaria del broker termina il worker bloccato; altra catena resta disponibile | Worker `.appex` installato fuori dall'app e durata associata al broker anziché all'app radice |

Comporre quei risultati non costituisce una prova del terzo arco, broker → `.appex`. In particolare, trasferire al broker un endpoint creato dalla GUI non prova che il sistema trasferisca anche la proprietà della durata.

## Identità dell'host e dichiarazione dell'extension point

Apple descrive l'host come app: questa dichiara gli extension point e il sistema usa i metadati nel suo bundle per associare le estensioni. Con le API nuove, `EX_ENABLE_EXTENSION_POINT_GENERATION=YES` produce un file `.appext`; la documentazione ammette anche il file già preparato. Non dice che mettere gli stessi metadati in un bundle `.xpc` trasformi quel servizio in host. [Apple: aggiungere supporto](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app), [Definition](https://developer.apple.com/documentation/extensionfoundation/appextensionpoint/definition).

`AppExtensionPoint.Identifier(host:name:)` lega l'estensione al **bundle identifier dell'host** e al nome del suo punto. Non è un parametro per scegliere liberamente il processo a cui assegnare il lancio. [Apple: Identifier](https://developer.apple.com/documentation/extensionfoundation/appextensionpoint/identifier/init%28host%3Aname%3A%29).

L'SDK pubblico esaminato espone in `AppExtensionPoint.Error`:

- `hostMustBeApplicationOrAppExtension`;
- `hostMustHaveBundleIdentifier`;
- `hostMustDefineAppExtensionPoint(String)`;
- `invalidAppExtensionPoint` e `unspecifiedAppExtensionPointName`.

La pagina Apple dei codici qualifica il primo come target non supportato e il terzo come definizione fuori da un'app. **Lettura prudente:** sono possibili controlli sul contesto host, non una prova che ogni chiamata da `.xpc` li attivi. Il nome del primo caso, da solo, non autorizza ogni forma di hosting annidato; non specifica neppure come un servizio incorporato risolva l'identità dell'app che lo contiene. La prova successiva sotto **non ha ricevuto questi errori** costruendo il punto esistente e il monitor nel broker. [Apple: errori del punto](https://developer.apple.com/documentation/extensionfoundation/appextensionpoint/error/hostmusthavebundleidentifier); SDK, righe 84–116, riferimento sotto.

`ServiceType=Application` di XPC descrive la politica d'istanza del **servizio**, non una conversione del bundle in applicazione. Il manuale Apple distingue quel valore da `CFBundlePackageType=XPC!` e descrive un namespace dell'app per i servizi inclusi. Non va usato come prova che ExtensionFoundation accetti `.xpc` come host. Fonte: SDK `xpcservice.plist(5)`, righe 16–61.

Nel prototipo legacy [`Probe.appextensionpoint`](../../../Prototypes/AddonPlatform/Host/Probe.appextensionpoint) dichiara `hylo.Cascade.AddonProbe.provider` e `EXPresentsUserInterface=false`; il [progetto Xcode](../../../Prototypes/AddonPlatform/AddonPlatform.xcodeproj/project.pbxproj) lo copia in `Host.app/Contents/Extensions`. Il [plist del provider](../../../Prototypes/AddonPlatform/Provider/Info.plist) usa `EXAppExtensionAttributes/EXExtensionPointIdentifier`. `.appextensionpoint` è il formato manuale concretamente presente e provato qui; `.appext` è il nome descritto dalla documentazione corrente. Non si assume che rinominarli o copiarli in `.xpc` sia una migrazione equivalente.

La P0 ha inoltre registrato discovery vuota con un host di bundle/signing identity diversa. È evidenza pertinente al contesto di identità; non isola quale controllo abbia causato il rifiuto e non prova direttamente il caso broker.

## Fonte Apple direttamente pertinente alla composizione

Nel [thread Apple 846017](https://developer.apple.com/forums/thread/846017), consultato il 24 settembre 2026, Quinn di DTS risponde al caso preciso «app → estensione → ulteriori estensioni di sviluppatori terzi»: questa capacità non è abilitata; suggerisce una richiesta di miglioramento. Il thread distingue inoltre PluginKit, precedente, da ExtensionKit.

Questa risposta è una fonte primaria sul supporto del caso annidato, non un'affermazione generica secondo cui tutti i processi XPC sono vietati come chiamanti. Impedisce però di considerare **broker convertito in `.appex`** una soluzione già supportata. Il contrasto apparente con il nome `hostMustBeApplicationOrAppExtension` richiede chiarimento Apple sullo scope dell'API, non un'interpretazione permissiva ricavata dal solo enum.

Non è stata trovata una risposta Apple che confermi o neghi esattamente «servizio `.xpc` fidato nell'app, che opera per l'extension point dell'app contenente». Questo sottocaso resta la domanda aperta. Le ricerche hanno usato ExtensionFoundation, XPC service, host, bundle identifier e `.appextensionpoint`; non sono stati usati articoli di terzi come prova di supporto.

## API utilizzabili con minimo 14 e API 26

La seguente tabella deriva dalle annotazioni di disponibilità nell'**SDK 27.0**, non dall'esecuzione su quei sistemi né dalla lettura di un SDK storico 14.

| Funzione | Percorso compatibile con target 14 | API nuova |
| --- | --- | --- |
| Definizione del provider | `AppExtension`, `AppExtensionConfiguration.accept(connection:)`, disponibili da macOS 13 | `ConnectionHandler`, macOS 26 |
| Discovery | `AppExtensionIdentity.matching(appExtensionPointIDs:)`, da 13, deprecata in 26 | `AppExtensionPoint.Monitor`, macOS 26 |
| Extension point | Metadati manuali già usati dalla fixture | `AppExtensionPoint`, `Definition`, `Identifier`, `Scope`, macOS 26 |
| Binding sulla conformità `AppExtension` | Plist della fixture | Proprietà `extensionPoint` e alias di binding della conformità, macOS 26.2 |
| Processo | `AppExtensionProcess.Configuration` e initializer, da macOS 13 | Stesso tipo; nessun distinto proprietario/lifecycle owner pubblico selezionabile nella configurazione letta |
| Trasporto | `makeXPCConnection() -> NSXPCConnection`, da macOS 13 | `makeXPCSession()`, macOS 26 |
| Fine uso | `invalidate()`, da macOS 13 | Nessuna distinta API pubblica di force-stop in questa interfaccia |

`AppExtensionIdentity` è `Identifiable`, `Hashable`, `Sendable`; la sua superficie pubblica letta non espone un costruttore da bundle ID né conformità `Codable`/`NSSecureCoding`. Apple indica esplicitamente di ottenere le istanze dalla discovery. Quindi non è documentato un percorso «la GUI scopre, serializza l'identità e il broker la ricostruisce» mediante queste API. Passare una stringa identificativa non equivale a passare l'identità del sistema. [Apple: AppExtensionIdentity](https://developer.apple.com/documentation/extensionfoundation/appextensionidentity); SDK, righe 159–180 e 237–258.

Per estensioni esterne le API nuove richiedono `Scope(restriction: .none)`; il default le limita al bundle dell'app. Il sistema considera soltanto quelle approvate e abilitate; quelle distribuite separatamente sono inizialmente disabilitate. La presentazione documentata del browser avviene dall'app; non equivale a un'API per concedere consenso ad altri processi. [Apple: Scope](https://developer.apple.com/documentation/extensionfoundation/appextensionpoint/scope), [discovery](https://developer.apple.com/documentation/extensionfoundation/discovering-app-extensions-from-your-app), [Monitor](https://developer.apple.com/documentation/extensionfoundation/appextensionpoint/monitor).

## Firma, isolamento e durata non seguono automaticamente la discovery

La documentazione di `AppExtensionProcess` promette avvio separato, possibile riuso del processo e segnalazione dell'interruzione. Non specifica qui il caso del chiamante `.xpc` né un parametro per far diventare un broker il proprietario univoco. [Apple: AppExtensionProcess](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess).

La documentazione di `invalidate()` descrive l'uscita all'ultima connessione. La [P0 locale](../../superpowers/verification/2026-09-09-addon-runtime-P0.md) conserva un FAIL reale con provider non cooperativo dopo invalidazione e rilascio; il successo di discovery dal broker non lo annullerebbe. [Apple: invalidate](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/invalidate()).

La fixture provider conserva App Sandbox e Hardened Runtime, ma l'host P0 non è un servizio sandboxed. Il risultato XPCBroker, invece, riguarda servizi sandboxed dello stesso team. Non è quindi già verificata l'intersezione **broker sandboxed + estensione esterna + altro firmatario**. Fonti: [progetto P0](../../../Prototypes/AddonPlatform/AddonPlatform.xcodeproj/project.pbxproj), [entitlement provider](../../../Prototypes/AddonPlatform/Provider/Provider.entitlements), [rapporto XPCBroker](../../superpowers/verification/2026-09-24-addon-xpc-broker.md).

Il [protocollo P0](../../../Prototypes/AddonPlatform/Shared/ProbeMessage.swift) e il [provider](../../../Prototypes/AddonPlatform/Provider/ProbeProvider.swift) verificano inoltre il signing identifier della GUI (`hylo.Cascade.AddonProbe`). Un futuro broker avrebbe identità distinta: spostare il chiamante richiederebbe un contratto di autenticazione esplicito, senza rimuovere il controllo o dichiarare valido il PID riportato dall'addon. Questo è lavoro successivo alla discovery, non ragione per ampliarne ora la prova.

## Prova successiva di sola discovery, eseguita dall'agente principale

Fixture [`XPCDiscovery/Probe.swift`](../../../Prototypes/AddonPlatform/XPCDiscovery/Probe.swift), [builder](../../../Prototypes/AddonPlatform/XPCDiscovery/run_discovery.py), macOS 27.0 `26A5425a`, SDK 27.0, prodotti `probe-0s0ccy7h`. Fonte letta: [stdout.jsonl](/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeXPCDiscoveryProbe/probe-0s0ccy7h/stdout.jsonl), SHA-256 `3adcd8af672c4e621383816b4b41f13ad9ed9fd3025bd7c3e29da6b08e69ad48`.

| Contesto | Legacy | Monitor moderno | Errore di target |
| --- | --- | --- | --- |
| App `hylo.Cascade.AddonProbe`, PID 31795 | Provider `hylo.Cascade.AddonProbeContainer.Provider` | Stesso provider; disabled 0, unapproved 0 | Nessuno |
| Broker `hylo.Cascade.AddonProbe.DiscoveryBroker`, PID 31821 | Identità vuote | Identità vuote; disabled 0, unapproved 1 | Nessuno |

App e broker usano lo stesso punto; il file del punto è soltanto nell'app, non nel `.xpc`. Il canale con il broker è verificato e correla nonce/PID. Il builder mantiene firma e Hardened Runtime sui due componenti e App Sandbox sul servizio. Il sorgente non crea `AppExtensionProcess`.

**Fatto:** il broker completa `AppExtensionPoint(identifier:)` e `Monitor`, vede un conteggio non approvato, ma non ottiene identità utilizzabili. **Inferenza:** il consenso osservato per la GUI non è sufficiente per questo contesto broker. Il conteggio non espone l'identità del candidato, quindi non prova da solo che l'elemento sia esattamente quel provider; non dimostra neppure che un consenso successivo basterebbe al lancio. Apple definisce `unapprovedCount` come numero di voci non ancora abilitate, distinto da `disabledCount`. [Apple: Monitor.State](https://developer.apple.com/documentation/extensionfoundation/appextensionpoint/monitor/state-swift.struct).

## Consenso: superficie pubblica e prossima verifica minima

L'header pubblico `EXAppExtensionBrowserViewController.h` dichiara soltanto la sottoclasse `NSViewController`, senza proprietà, metodi o initializer specifici per scegliere un host. L'interfaccia Swift di ExtensionKit non ne aggiunge. Non risultano parametri pubblici `hostBundleIdentifier`, audit token, PID, monitor o extension point con cui la GUI possa presentare il browser **per conto del broker**. La configurazione di `EXHostViewController` riguarda una scena di un'estensione già identificata; è un altro tipo, non una configurazione del browser. [Apple: browser](https://developer.apple.com/documentation/extensionkit/exappextensionbrowserviewcontroller), [EXHostViewController.Configuration](https://developer.apple.com/documentation/extensionkit/exhostviewcontroller/configuration-swift.struct); SDK header, righe 20–41.

`Monitor` espone add/remove del punto e stato di sola lettura: nessun metodo di approvazione o sostituzione dell'identità host. `Scope(.none)` decide se ammettere pacchetti esterni, non chi presta il consenso. `Identifier(host:name:)` è un binding al punto, non una delega di identità per il chiamante. Queste distinzioni derivano dalle firme SDK e dalla documentazione già citata; aggiungere App Groups o copiare un bundle ID non è un meccanismo documentato di consenso ExtensionFoundation.

Apple prescrive la UI di sistema per approvare, abilitare e disabilitare le estensioni; documenta sia Impostazioni di Sistema sia il browser presentato nell'app. Il browser visualizza tutti i punti dell'app, usa UI fuori processo e non notifica direttamente le modifiche: si osserva il monitor. Questo non significa che il view controller possa essere trasferito via XPC mantenendo l'identità di chi lo ha creato. [Apple: visualizzare le estensioni](https://developer.apple.com/documentation/extensionkit/displaying-the-app-extensions-available-to-your-app).

**Browser presentato dal broker:** non è confermato dalle fonti correnti. La [guida Apple archiviata](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/DesigningDaemons.html), aggiornata nel 2016, classifica i servizi XPC come incapaci di presentare UI salvo il caso limitato IOSurface. La guida premette che sono pratiche raccomandate e che altri comportamenti possono esistere: non è una prova di impossibilità su macOS 27. Tuttavia non fornisce supporto positivo all'uso di `NSWindow` + browser dal servizio. L'eventuale prova limitata dell'agente principale distingue quindi **comportamento osservato** da **configurazione supportata**; deve mantenere identità, sandbox e firma e fermarsi se il browser è vuoto/non presentabile. Nessun risultato di tale prova UI era disponibile durante questo aggiornamento.

La prossima verifica già riconducibile a un'interfaccia pubblica è **ispezionare** Impostazioni di Sistema → Generali → Elementi login ed estensioni e il browser dell'app per vedere se esiste una voce che rappresenta senza ambiguità il broker e il provider della fixture. Apple documenta quel percorso, ma non promette una voce per host `.xpc`. [Apple Support: impostazioni estensioni](https://support.apple.com/en-ke/guide/mac-help/-mtusr003/mac). Non basta una voce omonima dell'app già approvata. Se il sistema espone davvero il contesto broker, il successivo esperimento minimo è il consenso esplicito dell'utente sulla sola fixture, seguito da una nuova discovery autenticata in entrambi i contesti, senza avviare il provider. Se la voce manca, registrare il limite senza `exctl`, database, KVC, selettori privati o riuso artificiale della firma GUI.

Un esito positivo di consenso/discovery richiederà comunque una prova distinta di avvio autenticato, verifica di quale morte termina il provider, stop della sola catena mentre l'app resta viva, avvio prima di `main`, isolamento tra addon, processi delegati, firma di editori diversi e matrice reale 14/15/26. Ospitare poi una scena remota nella GUI potrebbe aggiungere un altro utilizzatore del processo e cambiare l'ipotesi «unico client broker».

Domanda pronta per Apple, **non inviata**: “Can an Application-type XPC service embedded in a macOS app use that containing app's declared ExtensionFoundation extension point to discover and launch extensions installed in other apps? If so, which bundle identity and extension-point metadata location are required, and which process owns the extension's lifetime? Does the answer differ between the legacy macOS 13–15 discovery API and AppExtensionPoint.Monitor on macOS 26+? We need the extension to terminate when the broker exits while the GUI app remains alive, without loading third-party code into the GUI or weakening sandbox/signing.”

## Fonte SDK riproducibile e limiti della consegna

- SDK: `/Applications/Xcode-beta.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk`, versione `27.0`.
- Interfaccia: `System/Library/Frameworks/ExtensionFoundation.framework/Versions/A/Modules/ExtensionFoundation.swiftmodule/arm64e-apple-macos.swiftinterface`; Apple Swift 6.4, modulo ExtensionFoundation `289.2`.
- SHA-256 interfaccia: `5ba60922c99cefb52fa9ecc76318cbbb29469df28002961ec9142174586c0c31`.
- Manuale pubblico XPC: `usr/share/man/man5/xpcservice.plist.5` nello stesso SDK.
- Browser: `System/Library/Frameworks/ExtensionKit.framework/Versions/A/Headers/EXAppExtensionBrowserViewController.h`, SHA-256 `14cc045b05385db4b8d75fbb971365718f7ce470cae401698bda1bfa38281ca3`.

Nessuna API privata o binario disassemblato usato; l'unica nuova evidenza nativa qui riportata proviene dalla fixture dell'agente principale, non da un'esecuzione del ricercatore. Nessuna modifica ad ammissione C0, spec approvata, entitlement o codice del prodotto. L'eventuale riavvio conclusivo di Cascade appartiene all'intervento principale, non a questa ricerca delegata. Nessun messaggio inviato ad Apple.
