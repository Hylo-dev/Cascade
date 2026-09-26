# C5 — condivisione degli asset e contratto SDK

La scelta dell’utente del 13 settembre è implementata: più pubblicazioni dello
stesso plugin possono condividere un raster entro la stessa partizione di privacy
assegnata dall’host. Ogni destinazione riceve un alias distinto; il raster ImageIO /
CoreGraphics resta lo stesso oggetto e i suoi pixel hanno una sola prenotazione.

## Comportamento verificato

`AssetState.share` ricontrolla l’alias sorgente e la sua autorità esatta. Editore,
addon, digest, connessione e partizione devono coincidere; feature e pubblicazione
possono differire soltanto tramite la condivisione esplicita. Ogni nuovo alias
prenota i consueti 4.096 byte di metadata, senza nuova decodifica o copia dei pixel.
Rilascio, fine o scadenza della sorgente non eliminano gli altri alias e pin.
L’ultima referenza reale determina il rilascio della quota raster.

`AddonRuntime.shareAsset` ricontrolla entrambe le pubblicazioni prima e dopo le
attese di ammissione, protegge i metadata pendenti e drena i completamenti differiti
prima dell’inserimento sincrono finale. Le partizioni delle assegnazioni sono
immutabili. `.addonOwned` copre dati autoprodotti; `.isolated(UUID)` separa contesti
scelti dall’host. Il provider non sceglie partizioni nei payload e la privacy del
documento rimane metadata di redazione, senza conferire autorizzazioni.

Il contratto pubblico `AssetHandle` riusa i validatori esistenti e Foundation
Codable: sette campi chiusi, limite raw 8 KiB, owner coerente con PublicationID,
identificatore valido, revisione positiva, dimensioni positive entro 1 MP e byte
RGBA8 esatti. La convalida precede la modifica dello stato canonico. Un handle
costruito o decodificato è metadata non fidato, mai un’autorizzazione.

`AddonAssetClient` espone importazione, condivisione e rilascio async attraverso
`AddonContext.assets`. Il precedente initializer resta disponibile e fallisce
esplicitamente con `dependencyUnavailable` se viene richiesta una funzione asset
senza client. Non è stato aggiunto un trasporto fittizio o codice provider in-process.

## Prove

**552 test seriali passati, uscita 0**, 16 nuovi rispetto alla baseline 536:
Runtime 314, Presentation 22, CascadeKit 170, Contracts 42, Tool 4.
Log: `/private/tmp/cascade-sharing-final-tests.log`.

Casi nuovi: 5 stato condiviso, 5 runtime, 4 contratto handle, 2 context SDK.
Le prove usano CGImage reali, PNG generati da ImageIO, ResourceGovernor e gate di
ammissione deterministici. Coprono widget/activity distinti, medesimo raster e quota,
partizioni isolate compatibili/incompatibili, release/end/expiry indipendenti,
quote metadata, cancellazione, disattivazione e uscita durante ammissione.

RED osservati: runtime (3 errori comportamentali), contratto handle (22 errori di
validazione) e client SDK (dipendenza iniettata ignorata). I tentativi iniziali
state RED/GREEN si sono fermati nella compilazione/firma prima dei test: non vengono
presentati come fallimenti comportamentali. La causa finale osservata era ENOSPC;
rimossi soltanto nove build-cache temporanei creati da questo lavoro, conservando
sorgenti, preimage, diff e log. La successiva suite completa sui sorgenti congelati
include e supera anche tutti i test dello stato condiviso.

Revisione indipendente dei tre diff conclusa senza rilievi aperti. Nessuna libreria
di codec, parser o gestore pixel duplicata: Foundation, ImageIO/CoreGraphics e i
componenti runtime esistenti restano le implementazioni comuni.

## Build e riavvio

356 input di build/test identici fra workspace, copia locale
`/private/tmp/cascade-sharing-integration` e manifest congelato
`/private/tmp/cascade-sharing-build-inputs.json`, verificati anche dopo la build.
Build Debug firmata riuscita tramite `scripts/build-development.sh`; codesign
verificato deep/strict, Applications aggiornato alla build in
`CascadeAddonDevelopment/Build/Products/Debug/Cascade.app`.
Log: `/private/tmp/cascade-sharing-app-build.log`.

Riavvio normale verificato: PID 69877 terminato, nuova istanza stabile PID 73683,
percorso atteso e nessuna terminazione forzata.
Record: `/private/tmp/cascade-sharing-restart.json`. Consumo settimanale rilevato: 22%.

## Limiti

macOS 27.0 beta 26A5425a, arm64, Swift 6.4/Xcode beta; deployment floor macOS 14
invariato, senza prova di esecuzione sul minimo OS. Nessuna qualifica di firma di
addon esterni, trasporto nativo, launcher o decoder isolato per input ostili.
Il gate C0d rimane invariato e nessun processo di tracing è stato avviato.

Le partizioni qui verificate riguardano asset autoprodotti e assegnazioni host;
non implementano trasferimento di asset dai servizi né tracciamento della provenienza
dei byte nativi. Quei percorsi devono derivare autorità dai grant/partizioni canonici
del broker. Restano handoff al renderer MainActor, trasporto, cache e ripristino.
Il piano C5 complessivo non è dichiarato concluso.
