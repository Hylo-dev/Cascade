# Passaggio audio AirPods e avviso essenziale

## Problema riprodotto dai dati

Il caso segnalato è il ritorno automatico delle AirPods dall'iPhone al Mac,
non necessariamente una nuova connessione ACL. Il monitor precedente deduplicava
correttamente la connessione già presente, ma perdeva il nuovo instradamento audio.
I log locali di ControlCenter confermano `SmartRoutingSystemBannerContent` con
evento `connected`, presentato tramite `MBSystemBannerAssertion` e MenuBarAgent.
La successiva ripetizione del popup non è riuscita all'utente durante l'indagine.

## Modifica

Un listener CoreAudio sull'uscita predefinita rileva i passaggi verso un dispositivo
Bluetooth identificato dal suo UID reale. La notifica Darwin
`com.apple.BluetoothServices.AudioRoutingChanged` è soltanto un segnale aggiuntivo
per rileggere tale uscita: non genera da sola un avviso. Nessun polling, discovery,
lettura continua dei log o modifica dell'uscita audio.

La sequenza AirPods → uscita integrata → AirPods emette un nuovo avviso anche se
la connessione ACL permane. Startup e ripresa creano baseline silenziose. Gli
errori temporanei HAL preservano la baseline; solo l'assenza confermata di uscita
la azzera. Il primo cambio audio entro due secondi da una nuova connessione fisica
si accorpa al suo avviso, poi i successivi ritorni sono eventi autonomi. I metadati
mantengono identità/revisione e significato del cambio audio, scartando risultati
appartenenti a eventi precedenti.

Il cambio di baseline sostituisce anche task e stream audio, così gli elementi
accodati prima del risveglio non assumono l'identità della nuova sessione.
Una nuova route conserva il modello, ma attende misure fresche della batteria:
valori dei singoli auricolari appartenenti alla route precedente non possono
sovrascrivere una nuova percentuale aggregata.

Limite esplicito: se il passaggio automatico mantiene invariato l'UID dell'uscita
audio predefinita, il semplice hint Darwin non genera un evento. Il monitor
richiede una transizione verificabile dell'uscita, non presume una nuova route.

La presentazione Bluetooth contiene soltanto modello/simbolo e anello: nessun
nome, stato o numero visibile. La traccia residua è verde al 28% di opacità con
spessore pari al 60% dell'arco carico; le ali preferite passano da 116 a 40 punti.
I testi per accessibilità e help usano un catalogo EN/IT che segue la lingua
selezionata dal sistema per l'app, con fallback inglese.

## Avviso nativo

Il riconoscimento include lo schema SystemBannerUI con identificatori esatti
`smart-routing-system-banner` e `com.apple.controlcenter.dismiss`. Gli
identificatori provengono dalle implementazioni del framework Apple installato.
Su macOS 27 l'host aggiuntivo è `com.apple.MenuBarAgent` (maiuscole significative).
La chiusura resta selettiva, subordinata a un evento recente, nome esatto e testo
di connessione fornito dalle risorse di sistema; pairing, cambio inverso verso
l'iPhone e controlli interattivi restano esclusi. Non viene chiusa la finestra
condivisa di MenuBarAgent.

Questa via AX interviene dopo la presentazione: non garantisce l'assenza di un
primo fotogramma del popup. Il funzionamento sul popup reale resta da verificare
quando torna riproducibile. Non equiparare l'osservazione attiva alla soppressione
confermata.

Sono state escluse le API private protette da entitlement Apple: il probe
AASystemStateMonitor/AADeviceManager riceve `kMissingEntitlementErr`; il listener
SystemBanner controlla esplicitamente il proprio entitlement. La preferenza
legacy `srConnectionAlert` non ha mostrato un utilizzo nella presentazione del
banner di questa versione. Nessuna di queste autorizzazioni o preferenze è stata
alterata.

## Verifiche

- Regressione sul ritorno audio a link già presente: fallimento osservato prima
  della correzione in `/private/tmp/cascade-smart-route-integration-red.log`.
- Suite reducer/metadata/lifecycle Bluetooth e policy AX:
  `/private/tmp/cascade-smart-route-bluetooth-tests.log`.
- Harness CoreAudio/route: `scripts/test-bluetooth-audio-route.sh`.
- Harness grafico: dodici PID Apple, semantica batteria e lifecycle animazione;
  anteprima in `/private/tmp/cascade-bluetooth-presentation/notices.png`.
- Regressione batteria precedente: fallimento osservato in
  `/private/tmp/cascade-route-battery-red.log`, poi suite Bluetooth passata.
- Build Debug e verifica della firma stabile riuscite:
  `/private/tmp/cascade-smart-route-build.log`. Risorse EN/IT compilate nel bundle.
- 42 controlli volume superati: `/private/tmp/cascade-smart-route-volume-tests.log`.
- `git diff --check` passato.
- Riavvio completato dopo lo sblocco, il 2026-09-08 alle 12:42:39: PID 74601,
  percorso `/private/tmp/cascade-development-derived/Build/Products/Debug/Cascade.app`.
  Alle 12:42:40 il controllo volume risulta nuovamente `active`, senza nuova
  richiesta di permesso. La chiusura del popup Smart Routing resta da verificare.
