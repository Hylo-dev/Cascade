# C5 — decoder immagini, 13 settembre 2026

Implementato il decoder host interno degli asset usando ImageIO e CoreGraphics.
Il [contratto](../../addons/assets.md) descrive il profilo PNG/JPEG supportato,
le quote e i limiti; il [piano dell'incremento](../plans/2026-09-12-addon-image-decoder.md)
registra le decisioni. Non è ancora un percorso SDK/pubblicazione/renderer.

## Modifiche

`BoundedAssetImageDecoder` ammette una sola operazione prima della coda del worker,
con errore `.rateLimited` per le richieste concorrenti. `NativeAssetImageWorker`
usa i codec Apple e CGContext per produrre RGBA8 premoltiplicato sRGB, fuori MainActor.
Nessun nuovo package o codec personalizzato. Input massimo 1 MiB, un megapixel,
RGB8 sRGB, singolo frame e orientamento già corretto.

Due piccoli collegamenti riusano il sistema esistente:
`AssetDisposalCoordinator.assetGovernor` assicura lo stesso governor per staging
e raster; `ResourceGovernor.withAssetDecodeReservation` protegge la quota temporanea
anche dalla pulizia globale dell'owner. I pixel finali mantengono la durata protetta
già verificata in C5c1. Errori, cancellazione e chiusura non rimborsano memoria viva.

## Difetti riprodotti e revisione

ImageIO accetta alcuni file senza terminatore PNG/JPEG. Inoltre un JPEG con scan
troncato e marcatore finale ripristinato può risultare completo prima del disegno,
poi segnalare `statusUnexpectedEOF`. Riprodotti entrambi i comportamenti; aggiunti
controlli fissi di firma/terminatore e una verifica dello stato nativo dopo il disegno.
Non sono una validazione indipendente di chunk, CRC o dati dopo un terminatore precedente.

Revisione indipendente finale: approvata, nessun rilievo aperto. Corretta anche
la documentazione per non attribuire ai controlli fissi garanzie che non offrono.
Le prove includono byte RGBA attesi, ordine delle righe, soglia esatta di un megapixel,
input non ammessi, quote, richieste concorrenti e chiusura/cancellazione in corso.

## Evidenze

- Baseline: 498 test seriali passati. Due casi AppKit non vedevano `NSScreen.main`
  nella sandbox; la suite con accesso alla sessione grafica passa senza modifiche.
- RED iniziale: cinque test contro il decoder ancora non implementato,
  `/private/tmp/cascade-asset-decoder-red.log`.
- RED per file troncati/scan corrotto e classificazione busy:
  `/private/tmp/cascade-asset-decoder-payload-red.log`.
- Mutazioni temporanee hanno riprodotto il rimborso anticipato e la consegna dopo
  chiusura: `/private/tmp/cascade-asset-decoder-mutation-red.log`. Sorgenti ripristinati
  prima della verifica finale. Queste prove successive non vengono descritte come
  RED iniziale dei due test sulle gare.
- GREEN mirato finale: 46 test in quattro suite, exit 0,
  `/private/tmp/cascade-asset-decoder-regression.log`; SHA-256
  `5d76572d78b87cd90520b4b22a131fc06fce1375c9a2c583380562e472bb7942`.
- Package finale: **507 test passati**, exit 0, `--no-parallel`: Runtime 276,
  Presentation 20, Engine 169, Contracts 38, tool 4. Log
  `/private/tmp/cascade-plugin-decoder-final-tests.log`; SHA-256
  `fc1e9db3a6f742d513a44a3657785d429970e66d7f748dd2364dfc9df23a9d9d`.
  Presente il warning storico `weakProducer` in PublicationStoreTests.

Comando della suite: Xcode-beta, `swift test --package-path
/private/tmp/cascade-plugin-decoder-integration/CascadeKit --disable-sandbox
--scratch-path /private/tmp/cascade-plugin-decoder-baseline --no-parallel`, con
cache moduli in `/private/tmp/cascade-plugin-module-cache`. Ambiente macOS 27.0
build 26A5425a, arm64. Non è una prova di esecuzione su macOS 14.

## Build e riavvio

345 input di build/test identici fra checkout e copia locale; hash invariati dopo
suite e build, inventario `/private/tmp/cascade-plugin-decoder-build-inputs.json`.
Build firmata tramite `scripts/build-development.sh`, exit 0. Verifica stretta
della firma e aggiornamento del collegamento Applications eseguiti dallo script.
Log `/private/tmp/cascade-plugin-decoder-app-build.log`; SHA-256
`f6dce82131524b23644f988731f917f9ec44ab2b301ab9ba2448fd8c0224f86d`.
Gli avvisi riguardano la destinazione Xcode e l'assenza della dipendenza AppIntents.

Riavvio verificato: PID 56048 chiuso normalmente, nuova istanza PID 60288 stabile
nel percorso `CascadeAddonDevelopment/Build/Products/Debug/Cascade.app` atteso.
Nessuna terminazione forzata. Record `/private/tmp/cascade-plugin-decoder-restart.json`.
Nessun commit o staging; conservato il lavoro preesistente.

## Limiti e seguito

Restano AssetState e riferimenti alle revisioni/pubblicazioni, autorizzazioni,
trasporto SDK, renderer, cache/ripristino e qualificazione del decoder contro input
ostili. Le allowance non impongono limiti rigidi alla memoria privata o al tempo CPU
delle librerie Apple; la cancellazione non interrompe un codec sincrono.
Nessuna prova nativa di tracing eseguita e nessun launcher abilitato. C5 nel suo
insieme e il sistema plugin distribuibile restano aperti.

Consumo settimanale Codex rilevato alla consegna: 16%, finestra di 10.080 minuti,
telemetria del 12 settembre alle 22:13 UTC. Inferiore al tetto del 60% richiesto.
