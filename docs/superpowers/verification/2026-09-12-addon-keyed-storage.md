# C5b — storage per chiave, 12 settembre 2026

Il backend host è implementato e approvato; C5 nel suo insieme resta aperto.
`AddonKeyedStorage` conserva valori distinti per chiave e identità verificata, separati
dal checkpoint e dalla cache. Le prenotazioni ridimensionabili del governor comune
mantengono le quote anche su staging, errori, chiusura e riconciliazione. Il contratto
pubblico del percorso host e i limiti sono descritti in [storage](../../addons/storage.md).

## Correzione e verifiche

La revisione iniziale ha richiesto F01: l'esistenza di una cartella creata non prova
che il suo parent sia stato sincronizzato. Il primo errore conservava correttamente
la quota ma un retry/reopen poteva saltare il sync. La correzione separa i due stati
con metadati limitati, ripara il parent prima del successo e non aggiunge sync degli
antenati alle normali scritture già confermate. Riesame F01: approvato, nessun rilievo
richiesto aperto. I file iniziali e la prima revisione sono conservati separatamente.

- RED comportamentale:3 test,42 problemi su9 scenari (root/data/cache, retry diretto,
  riapertura dello stesso backend e riapertura con governor nuovo).
- GREEN finale mirato:38 test,34 keyed e4 resize. I sync riusciti sono chiamate reali
  al filesystem; le prove registrano identità delle cartelle, ordine e quote esatte.
- Package finale:474 test passati, exit0, `--no-parallel`: Runtime243,
  Presentation20, Engine169, Contracts38, tool4. Xcode-beta e scratch già predisposto.
  Log `/private/tmp/cascade-c5b-fix1-full-package.log`, SHA-256
  `b8607b28637c9092dea4cef66b4b00a73391741d6e91818efeda667b0ee2204c`.
- I15 hash del perimetro sono invariati prima/dopo la verifica completa. Nove file
  sorgente/test sono cambiati rispetto alla baseline di questo incremento.
- La verifica iniziale di471 test non viene riattribuita alla correzione. La limitazione
  storica del test UI in esecuzione concorrente resta distinta dal risultato seriale.

Sono coperti limiti, isolamento, Unicode byte-esatto, record corrotti/futuri, revoca e
cancellazione durante ammissioni reali, cleanup fallita, commit con durabilità incerta,
quote condivise col checkpoint, inventario limitato e chiusura/riapertura. Sono prove
filesystem/host; non qualificano perdita di alimentazione, sandbox o launcher nativo.

## Consegna

Integrati 13 file (9 sorgenti/test e 4 documenti), preservando le modifiche preesistenti.
Confrontati 337 input di build identici fra checkout originale e copia locale. Build
firmata riuscita, exit 0, tramite `scripts/build-development.sh` dalla copia locale
verificata. Il collegamento `/Applications/Cascade.app` punta alla build appena creata
in `CascadeAddonDevelopment`. Riavvio osservato: PID 47210 chiuso senza forzatura,
nuova istanza PID 51942 stabile nel percorso atteso. Log
`/private/tmp/cascade-c5b-20260912-app-build.log` e
`/private/tmp/cascade-c5b-20260912-restart.json`. Nessun commit o staging.
Questa consegna completa C5b, non la feature complessiva.

## Lavoro residuo

Trasporto SDK autenticato con sessioni/permessi e frame dedicato per il valore massimo,
barriera globale prima dell'ammissione allo startup, asset e decoder, ripristino delle
pubblicazioni e avvisi senza replay. Restano inoltre controllo dei processi reali,
collegamento all'app, widget nostri sullo stesso SDK e qualificazione finale. Nessun
adapter produttivo viene abilitato da C5b.
