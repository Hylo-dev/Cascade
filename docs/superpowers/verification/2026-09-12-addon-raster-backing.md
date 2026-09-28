# C5c1 — memoria delle immagini, 12 settembre 2026

Questo incremento realizza il backing raster interno del futuro sistema di asset.
Un'immagine reale conserva la memoria e la relativa quota fino all'ultimo riferimento
CoreGraphics; il rilascio effettivo attiva il rimborso nel governor comune. Il contratto
host e i confini sono descritti in [assets](../../addons/assets.md).
Non costituisce ancora un percorso SDK/pubblicazione/renderer utilizzabile dagli addon.

## Implementazione e verifiche mirate

Sei file sorgente/test: estensione di ResourcePolicy e ResourceGovernor, due primitive
Assets e due nuove suite. Ammissione prima dell'allocazione, formato RGBA8 fisso con
massimo 1 MP, esecuzione fuori MainActor, prenotazioni protette e un solo drenaggio
condiviso. I record di gestione individuali non conservano una tabella dimensionata
al picco. Chiusura e cancellazione non liberano quote di immagini ancora vive.

Durante l'implementazione sono state dimostrate e corrette l'omissione dei pixel nel
budget complessivo, la mancanza delle protezioni di durata e la confusione possibile
fra istanze successive del governor allo stesso indirizzo. L'identità della durata
usa ora un nonce e ogni prenotazione protetta ha il proprio segreto canonico.
L'errore iniziale della sandbox del compilatore è un errore di avvio della verifica,
non una prova comportamentale fallita.

37 test mirati passati, exit 0: 19 AssetRasterBackingTests, 5 RetainedAssetReservationTests,
13 ResourceGovernorTests preesistenti. Comprendono veri CGImage, due riferimenti,
sostituzione con la vecchia immagine ancora trattenuta, 1.638 slot reali, fallimenti di
costruzione, cancellazione, ammissione/rimborso sospesi, chiusura, fault conservativi,
concorrenza durante lo svuotamento e tentativi di rilascio anticipato.
Log finale `focused-final.log`, SHA-256
`d9fd8707a0ebee157dd0344a3f5b2702ebbe456023688df7573e2d6f14135611`,
conservato nel checkpoint della consegna insieme ai nove log e agli hash dei sorgenti.

## Revisione

Revisione indipendente: conformità e qualità approvate, nessun rilievo da correggere.
Verificati i sei hash sorgente, le preimmagini, il diff e i nove log. Le prove di
fallimento costruttivo sono indotte: non equivalgono a esaurimento reale della heap
o a un fallimento nativo forzato di CGDataProvider. Il contratto fidato del costruttore
esclude callback differite dopo un risultato nullo.

## Verifica completa

Package finale: **498 test passati**, exit 0, `--no-parallel`: Runtime 267,
Presentation 20, Engine 169, Contracts 38, tool 4. Sessione 81680; log
`/private/tmp/cascade-c5c1-final-full-package.log`, SHA-256
`aa7859da06355d2c937a758b555d923ba350f8929366ecc0b6b0525e798bfbb4`.
I sei hash sorgente sono invariati dopo la verifica. Il log completo finale non
contiene warning; il precedente log mirato include il warning storico e invariato
in PublicationStoreTests sulla variabile weakProducer. Il risultato seriale non
qualifica la vecchia limitazione dei test UI concorrenti.

## Consegna e arresto richiesto

Integrati 10 file (6 sorgenti/test e 4 documenti), preservando il lavoro preesistente.
Confrontati 404 input sorgente, inclusi i prototipi, identici fra checkout originale
e copia locale. Build ufficiale firmata riuscita, exit 0, sessione 34450. Verifica
stretta della firma e aggiornamento di `/Applications/Cascade.app` eseguiti dallo
script di progetto. Gli avvisi Xcode sulla selezione della destinazione e sulle due
variabili SWIFT_DEBUG_INFORMATION sono presenti anche nella build precedente.

Riavvio verificato, sessione 1216 exit 0: PID 53808 chiuso regolarmente senza forzatura,
nuova istanza PID 56048 stabile nel percorso CascadeAddonDevelopment atteso. Log
`/private/tmp/cascade-c5c1-20260912-app-build.log` e
`/private/tmp/cascade-c5c1-20260912-restart.json`. Nessun commit o staging.

Questo conclude il task C5c1. Il lavoro si ferma qui su richiesta dell'utente;
nessun task successivo o ripresa automatica viene avviato.

## Limiti e seguito

L'input contiene pixel già decodificati e fidati; non si prova un decoder di input
ostile. Le quote riguardano memoria controllata e allowances, non copie interne
CoreGraphics/GPU o footprint complessivo. Il ciclo reale delle viste SwiftUI,
importazione SDK, trasferimento compresso, autorizzazioni private, riferimenti alle
revisioni di asset/pubblicazioni, cache e ripristino rimangono da collegare.
L'AssetState futuro deve entrare nella transazione canonica di AddonRuntime.

Il gate dei processi nativi resta HOLD per la sicurezza nel caso di perdita precoce
del supervisore; nessuna nuova prova di tracing è stata eseguita. Il minimo macOS 14
non è qualificato da test eseguiti su questa macchina beta. C5 e la feature completa
restano aperti. Su richiesta dell'utente il lavoro si arresta alla consegna di C5c1,
senza avviare C5c2.
