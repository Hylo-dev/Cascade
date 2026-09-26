# Trasferimento asset a blocchi — messaggi e assemblatore interno

Stato: implementazione e revisione approvate, suite finale e build firmata riuscite, riavvio della versione aggiornata verificato. [Piano](../plans/2026-09-14-addon-asset-chunks.md). Meccanismo approvato dall’utente nel [ticket Wayfinder](../../../.scratch/cascade-product/issues/21-asset-transfer.md).

## Consegna

Nove file sorgente/test: sette nuovi e due modificati. Frame dedicati Foundation per begin/chunk/finish/abort e risposte correlate, con profilo sintattico esplicito. Blocchi fino a 65.536 byte, input compresso fino a 1.048.576 byte e frame JSON fino a 196.608 byte, verificato prima del parsing. I validatori semantici esistenti sono riusati. Nessuna nuova dipendenza o implementazione alternativa di un codec immagine.

L’assemblatore interno mantiene una sola ricezione per istanza, con identità esatta di incarnazione, connessione, pubblicazione e assegnazione. Prenota `2 * totalBytes + 4096` byte di memoria temporanea, più i 1.024 byte di voce del governor esistente, prima del buffer a dimensione fissa. Scadenza monotona non rinnovabile di 30 secondi, ordine e lunghezza esatti dei blocchi, pulizia esclusiva. Il decoder ImageIO e i raster conservano le proprie quote indipendenti; revoca o cancellazione non rimborsano memoria ancora usata dal decoder.

## Verifica finale

- **795 test seriali / 80 suite**, inclusi **14 nuovi metodi**; gruppo mirato finale **36 test / 5 suite**.
- **400 input** applicativi/test identici fra originale, copia normalizzata e snapshot congelato; **55 percorsi** nel manifesto cumulativo dei sorgenti/test revisionati verificati. Checkout preesistente preservato, senza commit o staging.
- RED iniziale compilante: due asserzioni comportamentali sulle quote e sulla protezione da releaseAll. Mutanti separati dopo l’implementazione: tre test falliti con 16 rilievi per autorità, ordine e rimborso prematuro; ripristino documentato. Non sono presentati come RED precedente all’implementazione dell’assemblatore.
- Revisione indipendente: una race rilevata e corretta. Append/finish non validi passano ora allo stato di smaltimento sotto lo stesso lock della validazione; i controlli di autorità estranea e occupazione restano non mutanti. Nuova prova deterministica con rimborso del governor sospeso; verifica l’invariante finale, senza pretendere di riprodurre deterministicamente la precedente finestra fra lock. Revisione finale approvata, nessun rilievo residuo.
- Una prova distinta assembla e decodifica tramite ImageIO un PNG reale su più blocchi, confronta i pixel e verifica la durata del raster. La prova esatta da 1 MiB / 16 blocchi verifica tutti i byte tramite un decoder controllato che inoltra poi un PNG valido al decoder reale. Nessun parser PNG/CRC fatto a mano.

La suite precedente alla correzione passava 794 test / 80 suite. Log e snapshot precedenti sono conservati separatamente; il risultato 795 / 80 riguarda il codice corretto e congelato.

Artefatti locali con prefisso `/private/tmp/cascade-asset-chunks-`: `report.md`, `review.md`, `hashes.json`, `build-inputs.json`, `reviewed-inputs.json`, `red.log`, `mutant-red.log`, `restoration.json`, `review-green.log`, `full-tests.log`, `app-build.log`, `restart.json`; preimmagini, diff e alberi congelati conservati. Gli avvisi di compilazione sulle variabili weak e gli errori delle fixture SwiftData deliberatamente corrotte non costituiscono nuovi fallimenti.

## Confine residuo

Questo incremento è una primitiva interna: non autentica da solo l’assegnazione, non negozia il canale, non prenota il workspace dell’adattatore di trasporto, non pubblica un alias canonico e non collega il client SDK. Il runtime dovrà chiamare esplicitamente scadenza e chiusura e integrare gli ingressi/risposte condivisi. Il trasferimento non è ancora un percorso operativo per addon esterni. Launcher nativo e gate C0d restano separati e non qualificati.

L’utente richiede almeno il 35% della quota settimanale disponibile: tetto al 65% utilizzato. Ultima lettura ufficiale finale: 15 settembre 2026, 10:12:01 UTC, quota principale al 61% (39% disponibile). Il contatore Spark è distinto e non viene usato per questo limite.

Build tramite `scripts/build-development.sh` riuscita, firma verificata con codesign deep/strict e `/Applications/Cascade.app` aggiornato alla build CascadeAddonDevelopment. Avvio verificato: PID **28860**, unica istanza Cascade attiva e persistente dopo l’avvio. Al controllo precedente all’avvio non risultava alcuna istanza della build; il vecchio PID 12667 non era più presente. Nessuna terminazione forzata.

Riavvio normale finale, al termine dell’intervento: PID **28860 → 28937**, verificato dopo due secondi; nessuna terminazione forzata. Il file `restart.json` registra quest’ultimo passaggio. Wayfinder riallineato:22 ticket,4 risolti,18 aperti, nessuna dipendenza pendente inesistente o ciclo;215 collegamenti locali verificati, più4 nei documenti specifici del componente.
