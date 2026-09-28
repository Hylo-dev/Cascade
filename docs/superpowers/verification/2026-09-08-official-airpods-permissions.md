# Asset Apple e identità del controllo volume

## Esito implementazione

Sostituiti completamente i modelli generati con le risorse ufficiali locali:

- `/System/Library/PrivateFrameworks/CoreBluetoothUI.framework/Versions/A/Resources/AssetPaths*.plist`
- `/System/Library/CoreServices/BluetoothUIService.app/Contents/Resources/Banner-PID-*-mov/`

I dodici PID verificati sono `2002`, `200F`, `200E`, `2013`, `2014`, `2024`,
`2019`, `201B`, `2027`, `200A`, `201F`, `202D`: AirPods 1/2/3/4, varianti ANC,
Pro e Max. Gli alias corrispondono a immagini identiche nel catalogo Apple;
non si attribuisce arbitrariamente un modello a un dispositivo senza identità.
`productID` e `colorID` attraversano monitor, reducer e vista. I futuri PID
riconosciuti dal catalogo possono risolversi senza nuovi asset nel bundle.

Rimossi i due atlanti e il generatore procedurali. Nessun file Apple viene
copiato nel prodotto o in cache persistenti. Decode in background, massimo
48 fotogrammi da 96 px, un solo giro di tre secondi, con fallback all'immagine
ufficiale e poi al simbolo appropriato. Trasparenza verificata nei nove filmati
base. Il test completo ha misurato 0,179 secondi per la decodifica.

## Volume: evidenza e correzione

Prima della modifica, Cascade PID 65994 era firmata ad hoc con requisito
basato su cdhash. Anche la copia registrata da Xcode era ad hoc con hash diverso.
Il processo riceveva `false` per Accessibilità e non aveva alcun tap volume
registrato, mentre il pannello delle impostazioni mostrava Cascade acceso.
L'ultimo percorso presente nel selettore del pannello era
`/private/tmp/cascade-notch-derived/Build/Products/Debug/`, una vecchia build.
Non è stato letto o modificato direttamente il database TCC.

Con accesso al portachiavi fuori sandbox è stato trovato un certificato Apple
Development valido. La precedente verifica dentro sandbox non lo rendeva
visibile: non era una prova della sua assenza dal Mac. Il target app Debug ora
usa il team del certificato disponibile; `scripts/build-development.sh`
compila e verifica la firma senza ricorrere a un'identità ad hoc. La verifica
esterna conferma la catena Apple e il requisito stabile.

Il secondo problema era il refresh legato a `onAppear` di MenuBarExtra o
all'attivazione dell'app: un'app accessoria può non attivarsi quando il menu
si apre. `VolumeAccessibilityObserver` osserva il segnale di variazione del
permesso e il ritorno dalle Impostazioni. Le richieste vengono accorpate con
un solo ritardo su evento, senza polling. Il worker ricontrolla l'autorizzazione
anche per un tap attivo e lo rimuove se revocata. È disponibile anche un comando
esplicito per ricontrollare il permesso nel menu.

## Verifica

- Build Debug con firma Apple Development e verifica completa riuscite:
  `/private/tmp/cascade-official-assets-build.log`.
- Bundle finale privo dei due atlanti procedurali (rimozione verificata nel log).
- 42 controlli volume: `/private/tmp/cascade-permission-volume-tests.log`.
  Il test a menu non montato fallisce disabilitando l'osservatore del permesso,
  poi passa con la correzione (`cascade-permission-observer-red.log`).
- Harness metadati Bluetooth e 13 controlli policy passati:
  `/private/tmp/cascade-official-metadata-tests.log`.
- Test grafico completo passato: `/private/tmp/cascade-official-presentation-tests.log`.
- Gallery dei dodici PID e factory reali:
  `/private/tmp/cascade-bluetooth-presentation/official-airpods-library.png`,
  `/private/tmp/cascade-bluetooth-presentation/notices.png`.

Il processo della prima build Apple Development (66929) riceveva ancora
Accessibilità negata. La riassociazione del consenso alla build esatta
`/private/tmp/cascade-development-derived/Build/Products/Debug/Cascade.app`
è stata completata dopo l'approvazione esplicita dell'utente, come riportato
sotto. FineTune resta aperto e le sue impostazioni non sono state modificate.

Riferimenti primari:
[Apple sui requisiti di firma](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html),
[Apple DTS sull'identità ad hoc e i permessi](https://developer.apple.com/forums/thread/819406),
[FineTune: osservazione Accessibilità](https://github.com/ronitsingh10/FineTune/blob/2285279d36d3f8115c1c2d4aecd904f1bdf96a51/FineTune/Coordination/AccessibilityPermissionService.swift).

## Diagnosi conclusiva del consenso obsoleto

Il confronto diretto ha identificato l'esatto requisito salvato da TCC:
`cdhash H"a780b3101d2122207ece5987bda5a75df753a19b"`. Corrisponde alla firma della
vecchia `/private/tmp/cascade-notch-derived/Build/Products/Debug/Cascade.app`.
Il log TCC riporta esplicitamente `Failed to match existing code requirement`
per `hylo.Cascade` e `kTCCServiceAccessibility`, confrontando quel cdhash con
il requisito Apple Development della build corrente. Evidenza salvata in
`/private/tmp/cascade-stale-permission-proof.log`.

La semplice voce accesa nel pannello non correggeva il requisito binario
obsoleto. La prima richiesta di reset mirato era stata rifiutata dalla revisione
automatica per assenza di autorizzazione specifica; il consenso è stato quindi
richiesto all'utente, che ha risposto «ok».

Dopo tale approvazione, `tccutil reset Accessibility hylo.Cascade` è riuscito
(`Successfully reset Accessibility approval status for hylo.Cascade`). Tramite
il pannello di sistema è stato aggiunto il bundle firmato dal percorso esatto.
Nessuna modifica diretta al database TCC o ai permessi delle altre applicazioni.

Alle 11:42:02 del 2026-09-08 il processo già in esecuzione, PID 68672, ha
registrato `Volume routing status: active`, senza ricompilazione o riavvio.
`CGGetEventTapList` ha confermato il suo tap HID abilitato (`location=0`,
`options=0`, `mask=16384`), prima dei tap di FineTune (PID 1411), anch'esso
ancora in esecuzione. Questo verifica il riconoscimento del nuovo consenso e
l'attivazione del filtro reale, compreso il refresh automatico del permesso.

È stata richiesta all'utente una pressione fisica di F11 e F12 con il notch
compatto. L'utente ha risposto «si», confermando che compare soltanto l'avviso
di Cascade, con FineTune ancora aperto. La prova manuale dei tasti hardware
conferma quindi anche l'override effettivo dell'avviso volume; questa evidenza
proviene dall'utente e completa le verifiche automatiche e del tap attivo.
