# Sapphire e FineTune: glass, audio e limiti verificati

Ricerca del 4 settembre 2026 per la decisione **Valutare glass e audio dai sorgenti di Sapphire e FineTune**. È una lettura statica: nessuna app scaricata è stata eseguita, nessuna compatibilità è stata misurata. Snapshot: [Sapphire, commit e718d72f][s-commit] e [FineTune, commit 2285279d][f-commit]. I comportamenti descritti come fatti sono implementati nei sorgenti; le proposte per Cascade sono esplicitamente inferenze da validare.

## Il glass di Sapphire

**Fatto.** Nel notch, `notchBackground` abilita il percorso glass soltanto con `#available(macOS 26.0, *)` e `appearance.usesLiquidGlass`. Compone `LiquidGlassShapeFill` sulla sagoma attiva, con blending dietro la finestra e apparenza scura, più un riempimento configurabile per colore/gradiente e opacità. Sui sistemi precedenti usa un eventuale `NSVisualEffectView` con materiale HUD, riempimento e clipping della sagoma. Quindi il risultato su macOS 14 non è lo stesso renderer glass usato su 26. [Implementazione del notch][s-background]

**Fatto.** Il wrapper SwiftUI/AppKit costruisce dinamicamente `NSGlassEffectView` tramite `NSClassFromString`. Se la classe manca ripiega su `NSVisualEffectView`. Per il glass, oltre a proprietà pubbliche quali stile, tinta e raggio, invoca selettori interni: `_variant`, `_interactionState`, `_adaptiveAppearance`, `_contentLensing`, `_scrimState`, `_subduedState`. L'intensità sceglie materiali/varianti e parametri. Il codice configura la finestra trasparente, applica una maschera `CAShapeLayer`, cerca ricorsivamente layer denominati `CABackdropLayer`, imposta `windowServerAware=true` e `scale=1`, e usa KVO per mantenerli. Non è soltanto una superficie SwiftUI semitrasparente. [Wrapper completo][s-glass]

**Inferenza per Cascade.** La direzione visiva è riutilizzabile come riferimento, ma copiare il meccanismo interno introduce dipendenza da dettagli non documentati. Il prototipo deve confrontare API pubblica `NSGlassEffectView` su macOS 26 con un materiale AppKit su macOS 14, sagoma, tinta e bordi propri. L'header Apple del SDK locale conferma disponibilità 26 per `NSGlassEffectView`; la sua interfaccia pubblica non espone le varianti interne usate da Sapphire. Non è verificata l'identità con l'effetto Siri mostrato nell'allegato. [API Apple][apple-glass]

## Altre idee pertinenti, senza nuovi requisiti

Sapphire implementa categorie di attività come musica, timer, ripiano file, Bluetooth, cambio audio, notifiche, batteria e avanzamento file, con un ordine numerico di priorità. Questo è un esempio di arbitraggio tra eventi, non un protocollo aperto: l'enumerazione contiene casi conosciuti a compilazione. Il modello di estensioni di Cascade resta una decisione separata. [LiveActivityManager][s-activities]

Il monitor Bluetooth registra connessioni e disconnessioni `IOBluetoothDevice`. Il sistema notifiche legge invece il database SQLite di Notification Center, con percorso moderno e percorsi legacy, parsing di plist interne e polling predefinito di cinque secondi. È evidenza di una tecnica concreta per notifiche altrui, non prova di un'API pubblica universale o di consegna immediata e completa; accesso, schema e comportamento sulle versioni supportate vanno verificati separatamente. [Bluetooth][s-bluetooth], [NotificationManager][s-notifications]

Per Now Playing, Sapphire avvia un processo che usa uno script Perl e un `MediaRemoteAdapter.framework` incluso; legge aggiornamenti e invia comandi di trasporto tramite l'adapter. La cattura PCM di FineTune non fornisce di per sé titolo, copertina o controllo play/pause: le due integrazioni vanno pianificate separatamente. [NativeMediaController][s-media]

## FineTune: cosa rende possibile il mixer

**Fatto.** `AudioProcessMonitor` osserva `kAudioHardwarePropertyProcessObjectList`, aggrega i processi audio nelle applicazioni e tiene listener e refresh periodici. Per attribuire helper/XPC usa anche `responsibility_get_pid_responsible_for_pid`, API privata risolta con `dlsym`, poi ripiega sulla risalita dell'albero processi. È rilevante per Safari/WebKit e browser Chromium: identificare l'app non equivale a identificare ogni scheda o ogni brano. [Monitor dei processi][f-process]

**Fatto.** Per un'app, `ProcessTapController` crea un `CATapDescription` privato sui suoi `AudioObjectID`, con `.mutedWhenTapped`: l'uscita originale viene soppressa mentre il tap è attivo e l'audio viene riprodotto dal percorso controllato. Prova un tap sullo stream di un device per preservare canali, poi ripiega su stereo mixdown. Crea un aggregate device privato che contiene tap e output; il callback legge i buffer, applica livello/mute e scrive l'uscita. Questo percorso non installa un driver audio aggiuntivo; utilizza oggetti HAL creati a runtime. [Creazione e avvio][f-tap]

**Fatto.** L'output multiplo è implementato nel medesimo aggregate: primo device come clock, compensazione del drift sugli altri e modalità stacked quando serve replicare il segnale. Gli aggregate scelti dall'utente vengono appiattiti nei sottodevice; ci sono regole specifiche per la compensazione del tap con Bluetooth e sorgenti virtuali. Il codice non giustifica una promessa di latenza identica o sincronizzazione perfetta tra qualsiasi coppia di dispositivi. [Piano dell'aggregate][f-aggregate]

**Inferenza.** Volume per app, routing e output simultanei richiesti dall'utente sono tecnicamente plausibili senza includere EQ nella prima versione, ma costituiscono un motore audio persistente. Non vanno legati al ciclo di vita della pagina SwiftUI o alla presenza del notch aperto. Il costo non consiste soltanto in slider: formati, sample rate, clock, helper dei browser, chiamate Bluetooth e riconnessioni richiedono verifica su hardware reale.

## Permessi e versioni

Apple documenta Core Audio taps da macOS **14.2** nel sample ufficiale: occorre `NSAudioCaptureUsageDescription`; l'avvio della registrazione sull'aggregate con tap provoca il consenso per audio di sistema. Il tap può catturare gruppi di processi e silenziarne l'uscita. Questo conferma la primitiva, non tutta l'app FineTune. [Sample Apple][apple-taps]

**Fatti del repository.** FineTune dichiara 15.0 nel README, ma il progetto nello snapshot imposta **15.4**. I target app hanno sandbox disabilitata, hardened runtime abilitato e flag `ENABLE_TCC_SPI` attivo. `AudioRecordingPermission` usa il framework privato TCC per preflight e richiesta; senza quel flag assume lo stato autorizzato, che non dimostra un consenso effettivamente presente. [Configurazione build][f-project], [Gestione consenso][f-permission]

Sono presenti usage descriptions per audio di sistema, microfono e Bluetooth, ed entitlement audio-input/Bluetooth/network-client. Il controller tenta di disattivare gli stream microfono dei device duplex per evitare richieste non necessarie; un fallimento può lasciare comparire il prompt. I permessi vanno quindi presentati per capacità effettiva, senza promettere che l'audio per app richieda sempre, oppure mai, il microfono. [Info.plist][f-info], [Entitlements][f-entitlements], [Stream di ingresso][f-input]

## Callback, UI e affidabilità

**Fatto con correzione documentale.** Il controller è `@MainActor`; il processamento è `nonisolated`, con stato condiviso `nonisolated(unsafe)`. Un commento afferma che il callback esegua sul thread HAL ignorando la queue passata. Apple specifica invece che `AudioDeviceCreateIOProcIDWithBlock` effettua dispatch **sincrono sulla queue fornita**, oppure invoca direttamente il blocco se la queue è nulla. FineTune passa una queue dedicata, non quella main: il commento non va trasformato in specifica di Cascade. [Controller][f-thread], [Contratto Apple][apple-ioproc]

**Inferenza.** Il codice è utile come studio, ma non certifica la sicurezza della concorrenza: `nonisolated(unsafe)` elimina controlli, non sostituisce sincronizzazione e gestione della durata dei dati. Servono separazione tra stato UI e callback, dati preallocati, aggiornamenti controllati, nessuna attesa di UI/I/O nel percorso che produce audio e misure di underrun. L'aggiornamento dei meter deve poter rallentare quando il widget è invisibile senza interrompere il routing.

FineTune distingue teardown asincrono e teardown atteso; quest'ultimo precede la ricreazione. L'ordine è stop device, distruzione IOProc, aggregate e tap. Per cambio output tenta crossfade con due percorsi e dispone di ricreazione distruttiva; ha recupero dei tap inattivi, cooldown e ricreazione al cambio sample rate Bluetooth. All'avvio ripulisce aggregate orfani: il sorgente segnala il rischio che un crash lasci audio applicativo silenziato. [Risorse][f-resources], [Switch e invalidazione][f-switch], [Recupero][f-recovery], [Orfani][f-orphans]

## Decisioni che questi fatti rendono necessarie

1. **Minimo macOS:** Cascade attualmente imposta 14.0. Un motore basato sui taps richiede almeno un gate 14.2; riusare direttamente FineTune attuale non è un porting verificato per Sonoma. Valutare minimo superiore oppure capacità ridotte su sistemi precedenti. [Progetto Cascade locale](../../../Cascade.xcodeproj/project.pbxproj)
2. **Fallback audio:** se consenso, tap o device falliscono, proposta da validare: ripristinare il percorso macOS e disabilitare il routing interessato, conservando le preferenze. Non dichiarare funzionante uno slider che non controlla l'audio.
3. **Prototipo audio:** verificare browser/helper, app con routing proprio, due output con clock diversi, Bluetooth durante chiamata, USB duplex, hotplug, sleep/wake, crash e ripartenza; misurare latenza, drop e consumo senza EQ.
4. **Prototipo glass:** confrontare macOS 14 e 26, display con/senza notch, scaling e accessibilità. L'aspetto approvato e l'accettazione di API interne sono decisioni umane separate.

Queste sono proposte di verifica, non decisioni già approvate. Non sono stati eseguiti build, test audio, profilazione o prove di permessi.

## Licenze dichiarate e provenienza

Sapphire dichiara **AGPL-3.0**; FineTune **GPL-3.0**. Questo report descrive funzionamento e riferimenti, senza incorporare codice. Ispirazione visiva/funzionale, dipendenza e copia di sorgenti sono scelte distinte; nessuna delle ultime due è decisa qui. [Licenza Sapphire][s-license], [Licenza FineTune][f-license]

[s-commit]: https://github.com/cshariq/Sapphire/commit/e718d72feba61538a61ffc14e3abc32a9b4e35b9
[f-commit]: https://github.com/ronitsingh10/FineTune/commit/2285279d36d3f8115c1c2d4aecd904f1bdf96a51
[s-background]: https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Notch/NotchController.swift#L656-L696
[s-glass]: https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Utilities/LiquidGlassView.swift
[s-activities]: https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/LiveActivities/LiveActivityManager.swift#L16-L99
[s-bluetooth]: https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Services/Bluetooth/BluetoothManager.swift#L58-L81
[s-notifications]: https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Services/Miscellaneous/NotificationManager.swift#L197-L306
[s-media]: https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/Sapphire/Services/Music/NativeMediaController.swift#L135-L285
[s-license]: https://github.com/cshariq/Sapphire/blob/e718d72feba61538a61ffc14e3abc32a9b4e35b9/LICENSE
[f-process]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Monitors/AudioProcessMonitor.swift#L91-L177
[f-tap]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L530-L705
[f-aggregate]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L295-L412
[f-project]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune.xcodeproj/project.pbxproj#L364-L493
[f-permission]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Permission/AudioRecordingPermission.swift
[f-info]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Info.plist
[f-entitlements]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/FineTune.entitlements
[f-input]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L454-L497
[f-thread]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L6-L50
[f-resources]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/TapResources.swift
[f-switch]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/ProcessTapController.swift#L708-L877
[f-recovery]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/AudioEngine.swift#L1881-L2000
[f-orphans]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Audio/Engine/OrphanedTapCleanup.swift
[f-license]: https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/LICENSE
[apple-glass]: https://developer.apple.com/documentation/appkit/nsglasseffectview
[apple-taps]: https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps
[apple-ioproc]: https://developer.apple.com/documentation/coreaudio/audiodevicecreateioprocidwithblock(_:_:_:_:)
