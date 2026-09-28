# Credito CPU degli addon — continuazione del 20 settembre 2026

**Esito: PASS per i componenti interni**, dopo revisione root e indipendente, test completi, build firmata e riavvio verificato. La decisione sul [credito condiviso](../../../.scratch/cascade-product/issues/46-addon-cpu-burst-policy.md) è approvata: capacità iniziale 100 ms CPU e ricarica di 5 ms CPU per secondo monotono, conservata fra lavori e riavvii del provider. Sostituisce la precedente combinazione ambigua di finestra mobile e burst per job.

## Incrementi

- [Credito CPU](../../../.scratch/cascade-product/issues/47-addon-cpu-credit.md): Terra medium ha implementato il valore interno `AddonCPUBudget`; root e revisione indipendente Sol medium PASS. 12 test mirati PASS. Aritmetica `Duration`, istanti limitati e ordinati anche sotto il nanosecondo, debito osservato conservato, conversione esatta di `UInt64.max`, errore atomico se un nuovo addebito eccede il limite rappresentabile. Nessun reset per job.
- [Collegamento alle osservazioni comuni](../../../.scratch/cascade-product/issues/48-addon-cpu-accounting.md): Sol medium ha implementato il collegamento; root e un secondo Sol medium hanno revisionato il codice finale: PASS. L’owner event-driven è esplicito e il conto appartiene al coordinatore esistente, con identità e capacità limitate. Nessun secondo campionatore o ingresso per riapplicare batch già prodotti. Il risultato per owner distingue copertura completa del giro, incompleta senza saldo ed errore contabile persistente senza saldo; gli addebiti validi restano acquisiti anche quando manca una misura di un altro processo.

## Test e consegna

- **71 test mirati in 4 suite PASS**: 12 del credito, 12 del collegamento e 47 delle osservazioni/reducer/coordinatore preesistenti. Il collegamento ha un red comportamentale compilato e un successivo green.
- **1.122 test completi in 99 suite PASS**, rispetto alla baseline di 1.098 test in 97 suite. Root ha ricompilato e rieseguito tutti i prodotti del package nella sessione desktop, con Xcode-beta e `swift test --disable-sandbox --package-path CascadeKit --scratch-path /private/tmp/cascade-addon-tests --no-parallel`. I cinque risultati Swift Testing sono sommati nel [riepilogo](../../../.scratch/codex-addon/20260920-cpu-credit/test-summary.json).
- Root ha richiesto il test di atomicità dell’overflow a un istante successivo; nel collegamento ha corretto la conservazione del conto nello stato di errore e l’ordine della validazione dell’editore. Le fixture di overflow ora considerano anche la ricarica durante il debito. Nessun rilievo importante residuo nelle revisioni indipendenti.
- **Build ufficiale e firma Apple Development PASS.** `scripts/build-development.sh` è stato eseguito su una copia locale con 482 input SHA-256 identici al progetto prima e dopo la compilazione. Questa evita il blocco iCloud di `NSFileCoordinator` documentato nella precedente consegna. Controllo SDK: 4 package, 11 target, 90 sorgenti Swift e 140 import PASS; `codesign --verify --deep --strict` PASS.
- Lo script ha aggiornato `/Applications/Cascade.app` alla build in `CascadeDevelopment/Build/Products/Debug/Cascade.app`. Chiusura normale e riavvio verificati: **PID 18882 → 25071**, percorso dell’eseguibile corrispondente e stabilità per cinque secondi. [Risultato](../../../.scratch/codex-addon/20260920-cpu-credit/delivery.json).
- Gli hash dei quattro file sorgente/test revisionati coincidono con quelli consegnati. Gli altri input registrati sono invariati; nessuna modifica al lettore/riduttore preesistente o ad altri sottosistemi. Nessun commit o esperimento nativo.

## Limiti

I componenti restano interni e osservativi. Il binding processo/editore resta un’aspettativa fornita dall’host, non un’autenticazione nativa. Nessun collegamento produttivo al launcher, al governor o alla salute, nessun timer o nuovo processo. Il credito vive nell’incarnazione del coordinatore: il riavvio del provider lo conserva, il riavvio dell’app host non è persistenza su disco. Nessuna applicazione automatica del profilo event-driven a UI/audio continui.

Il saldo contabilizza la CPU effettivamente osservata. Non costituisce una garanzia istantanea o una prova di copertura dell’intera vita del processo. Profili pubblici, comportamento nativo macOS14/Intel, costo energetico e arresto supervisionato restano da qualificare.

## Evidenze

[Brief e revisione del calcolo](../../../.scratch/codex-addon/20260920-cpu-credit/task-47-independent-review.md), [disegno del collegamento](../../../.scratch/codex-addon/20260920-cpu-credit/ownership-design-review.md). Il primo red del calcolo era soltanto compilazione per tipo assente; non è presentato come un fallimento comportamentale TDD. Una verifica successiva in un package temporaneo ha alterato la sola ricarica: sei fallimenti comportamentali; ripristino byte-identico e 12 test PASS. È una verifica della sensibilità dei test, non un red TDD storico.

## Punto progettuale successivo

Prima di collegare gli sforamenti a `AddonHealthStore` serve [definire le violazioni CPU distinte](../../../.scratch/cascade-product/issues/49-addon-cpu-violation-counting.md). Un solo burst può lasciare debito per più campioni: ripetere la lettura del saldo negativo non prova nuovo consumo. La raccomandazione è contare nuovo consumo oltre il credito, una volta per addon e giro di misura; la scelta di prodotto resta aperta.

[Revisione root e confronto degli input](../../../.scratch/codex-addon/20260920-cpu-credit/root-review.md), [revisione indipendente del collegamento](../../../.scratch/codex-addon/20260920-cpu-credit/task-48-independent-review.md), [log completo dei test](../../../.scratch/codex-addon/20260920-cpu-credit/final-package-tests.log), [log build](../../../.scratch/codex-addon/20260920-cpu-credit/final-app-build.log).

Il tracker derivato contiene 49 ticket: 32 risolti, 17 aperti, dei quali 7 disponibili e 10 bloccati; nessun ticket rimane assegnato. Dipendenze esistenti e prive di cicli verificate. Budget settimanale disponibile alla consegna: **92%** (8% consumato), sopra la soglia di arresto del 75%. L’arresto riguarda la scelta progettuale successiva richiesta dall’utente, non il budget.
