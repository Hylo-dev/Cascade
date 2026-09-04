# Caricare widget SwiftUI esterni: meccanismi e limiti

Ricerca del 4 settembre 2026. Contesto: Cascade distribuita fuori App Store, anche tramite Homebrew; integrazioni indipendenti scritte in SwiftUI, possibilmente importabili o installabili in una cartella. Questo rapporto accerta le alternative e lascia aperta la scelta del formato. Fonti: documentazione Apple/Swift e checkout locale; nessun prototipo eseguito.

## Risultato

L'estensibilità desiderata è tecnicamente plausibile. Esistono due percorsi distinti per UI SwiftUI arbitraria: caricare codice binario nel processo di Cascade, oppure ospitare UI remota con le API pubbliche ExtensionKit. `import` e conformità a un protocollo, da soli, non rendono un widget rilevabile da un'altra applicazione. La decisione dipende soprattutto da isolamento, installazione, compatibilità macOS e libertà dell'interfaccia.

## Punto di partenza verificato

[`NotchWidget`](../../../CascadeKit/Sources/CascadeKit/Core/Widgets/NotchWidget.swift) è già pubblico, `@MainActor`, con identità, tipo, ingombro, `makeContentView() -> AnyView`, `activate` e `suspend`. [`WidgetHost`](../../../CascadeKit/Sources/CascadeKit/Core/Widgets/WidgetHost.swift) conserva istanze nel processo e chiama direttamente i widget. [`CascadeApp`](../../../Cascade/CascadeApp.swift) registra manualmente `ClockWidget`; non c'è ancora un meccanismo di scoperta esterna in questi percorsi.

[`CascadeKit/Package.swift`](../../../CascadeKit/Package.swift) dichiara macOS 14, Swift tools 6.2 e una libreria senza tipo di linkage esplicito. Il [progetto Xcode](../../../Cascade.xcodeproj/project.pbxproj) usa macOS 14, Hardened Runtime attivo e App Sandbox disattivata. Sono impostazioni del sorgente, non verifiche della firma di un'app distribuita. Inoltre, l'host sospende tutti i widget quando il notch è chiuso: l'attività compatta continuativa dovrà avere un ciclo di vita esplicitamente definito.

## Matrice delle alternative

| Alternativa | Aggiunta indipendente | UI SwiftUI | Confine di esecuzione | Questione determinante |
| --- | --- | --- | --- | --- |
| Package Swift/`import` nella build di Cascade | Richiede nuova build dell'host | Completa | Processo Cascade | Adatto a moduli incorporati; non soddisfa da solo l'installazione autonoma. |
| Bundle/framework binario da cartella | Sì, con loader e contratto stabile | Completa, in processo | Nessun isolamento dal widget | Firma, compatibilità ABI, crash e blocchi ricadono sull'host. |
| App contenitore con estensione ExtensionKit | Sì, tramite registrazione del sistema | Scene SwiftUI remote | Processo dell'estensione | Abilitazione utente; percorso macOS 14/15 da provare. |
| Provider esterno con messaggi/dati dichiarativi | Sì, con protocollo IPC | Rendering SwiftUI di Cascade | Logica separabile | Libertà limitata ai componenti/layout descritti dal contratto. |

La matrice sintetizza i fatti seguenti; la quarta alternativa è una **proposta architetturale**, non un formato già presente nel repository.

## Import, binari e identità dei tipi

**Fatti.** `import` rende disponibili simboli di un modulo nel sorgente; SwiftPM produce artefatti di build e può scegliere collegamento statico o dinamico. Non definisce una ricerca runtime delle app installate. Impostare `.dynamic` è una scelta di linkage, non un sistema di plugin. [Swift: import](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/declarations/), [SwiftPM: prodotti](https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html).

`Bundle.load()` carica codice eseguibile in un programma già in esecuzione. Apple documenta bundle anche fuori dall'app e accesso alla principal class; leggere `principalClass` può già caricare codice. Una cartella deve quindi contenere artefatti compilati, risorse e metadati compatibili, non semplicemente file Swift da interpretare. Un'interfaccia di importazione è realizzabile sopra questo meccanismo. [Bundle.load](https://developer.apple.com/documentation/foundation/bundle/load()), [Loading Bundles](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/LoadingCode/Tasks/LoadingBundles.html).

Swift distingue stabilità ABI, stabilità del modulo e library evolution. Per librerie binarie aggiornate indipendentemente, `BUILD_LIBRARY_FOR_DISTRIBUTION` abilita le ultime due; non rende compatibile qualunque modifica all'SDK. [Library Evolution](https://www.swift.org/blog/library-evolution/).

**Implicazione da prototipare.** Host e plugin devono concordare identità del modulo/protocollo, simboli esportati, factory e versione ABI. Una copia incorporata separatamente di CascadeKit non va assunta equivalente a un unico SDK condiviso; vanno verificati cast, conformità e aggiornamenti. Il runtime identifica i tipi tramite metadata e descrittori di protocollo, non tramite una semplice uguaglianza di nomi. `AnyView` cancella il tipo concreto della vista, ma non costituisce un formato IPC. [Swift: Type Metadata](https://github.com/swiftlang/swift/blob/main/docs/ABI/TypeMetadata.rst).

## Firma e disponibilità reale

**Fatto.** Con Hardened Runtime, library validation ammette normalmente codice firmato Apple o con lo stesso Team ID dell'eseguibile. Per plugin di sviluppatori diversi Apple indica `com.apple.security.cs.disable-library-validation`; disattivarlo comporta controlli Gatekeeper aggiuntivi. Distribuzione diretta e Homebrew non eliminano questo vincolo. [Disable Library Validation](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation).

**Conseguenza.** Firma e autenticità non sono isolamento: codice correttamente firmato può comunque contenere bug o comportamenti indesiderati. Verifica del produttore, consenso all'attivazione e sandbox rispondono a problemi diversi. Apple descrive la firma come attestazione dell'origine; la separazione di processo riduce invece l'impatto dei guasti. [Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html), [Designing Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/DesigningDaemons.html).

## UI remota pubblica e installazione

**Fatti.** ExtensionKit documenta `PrimitiveAppExtensionScene` per produrre UI e `EXHostViewController` per ospitarla, anche tramite `NSViewControllerRepresentable` in SwiftUI. L'host tratta il contenuto come opaco; può connettersi alla scena via XPC. Quindi UI remota non significa necessariamente API private. Non occorre presumere che viste SwiftUI siano serializzabili o affidarsi a classi remote non documentate. [Including extension-based UI](https://developer.apple.com/documentation/extensionkit/including-extension-based-ui-in-your-interface).

Un extension point con `Scope(restriction: .none)` ammette estensioni esterne all'host; il default le limita al suo bundle. L'estensione viene distribuita dentro un'app contenitore, con identificatore dell'extension point e SDK dell'host. È un modello coerente con «la propria app aggiunge il widget»; la documentazione non stabilisce un equivalente al caricamento di una `.appex` sciolta da qualunque cartella. [Scope](https://developer.apple.com/documentation/extensionfoundation/appextensionpoint/scope), [Building an app extension](https://developer.apple.com/documentation/extensionfoundation/building-an-app-extension-to-support-a-host-app).

Le estensioni distribuite separatamente sono disabilitate inizialmente: il proprietario del dispositivo le abilita mediante interfaccia di sistema, disponibile anche dentro l'app con `EXAppExtensionBrowserViewController`. La scoperta può aggiornarsi all'installazione/rimozione delle app, ma «automatico» non può significare attivazione senza questo passaggio. La documentazione permette contributi esterni; firma e attivazione con due Team ID diversi restano una prova di distribuzione da fare. [Discovery](https://developer.apple.com/documentation/extensionfoundation/discovering-app-extensions-from-your-app), [Extension browser](https://developer.apple.com/documentation/extensionkit/displaying-the-app-extensions-available-to-your-app).

**Disponibilità verificata nell'SDK Apple locale macOS 27.0:** `EXHostViewController`, `PrimitiveAppExtensionScene` e discovery legacy risalgono a macOS 13; `AppExtensionPoint`, `Scope` e `Monitor` richiedono macOS 26. Alcune nuove API di binding richiedono 26.2. Le dichiarazioni sono in `ExtensionKit.framework/Headers/EXHostViewController.h` e nelle interfacce Swift di ExtensionKit/ExtensionFoundation sotto `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/`.

Apple conferma che la generazione programmatica del file `.appext` arriva con macOS 26 e che file precedenti restano utilizzabili. La disponibilità delle classi dal 13 **non prova da sola** il funzionamento completo su Sonoma: manifest manuale, discovery legacy, firma e registrazione devono essere verificati su 14/15. [Adding extension support](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app).

## Isolamento: ciò che è garantito e ciò che manca

Nel modello corrente, un widget che blocca `makeContentView` o `activate` blocca il MainActor di Cascade; `suspend` è cooperativo, non un limite imposto dal sistema. Mettere soltanto il lavoro audio o la logica in XPC lascia la UI arbitraria nel processo host.

ExtensionFoundation esegue l'estensione separatamente e segnala interruzioni; ExtensionKit segnala disattivazioni. Questo contiene il crash del processo remoto, ma non garantisce che Cascade resti reattiva se aspetta risposte sincrone, decodifica payload eccessivi o gestisce male il riavvio. Invalidare una connessione non termina necessariamente il processo quando esistono altre connessioni. [Extension lifecycle](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app), [Synchronous XPC](https://developer.apple.com/documentation/foundation/nsxpcconnection/synchronousremoteobjectproxywitherrorhandler(_:)).

L'attributo `EnhancedSecurity` impone ulteriori restrizioni e richiede configurazione dedicata: il relativo helper **non può presentare UI**. Non va quindi promesso contemporaneamente come sandbox massima e contenitore universale di SwiftUI remota. [Enhanced Security helpers](https://developer.apple.com/documentation/xcode/creating-enhanced-security-helper-extensions).

## Prove necessarie prima della decisione

1. Due app firmate da sviluppatori diversi: discovery, approvazione, aggiornamento e rimozione dell'estensione; matrice macOS 14/15/26.
2. Scena remota nel pannello del notch: resize, trasparenza, focus, menu, drag/drop, accessibilità e più istanze; misurare apertura e memoria.
3. Crash, blocco del main thread remoto e risposta IPC assente: verificare che hover/chiusura e altri widget continuino, con placeholder e ripristino controllato.
4. Se resta candidata la cartella binaria: SDK vecchio/nuovo, compilatori diversi, architetture supportate, library validation, caricamento fallito e aggiornamento senza presumere unload sicuro.

Decisioni ancora umane: priorità fra cartella e app integrata, versione minima macOS, fiducia nel codice esterno, UI arbitraria versus contratto dichiarativo. Nessuna di queste scelte è risolta da questo rapporto.
