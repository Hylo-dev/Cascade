# Violazioni CPU degli addon — continuazione del 21 settembre 2026

**Stato: implementazione, revisioni, test e consegna locale completati.** L’utente ha approvato il [conteggio del nuovo consumo oltre credito](../../../.scratch/cascade-product/issues/49-addon-cpu-violation-counting.md): al massimo un incidente moderato per addon e giro, senza contare di nuovo il solo debito residuo.

## Incrementi

Il [classificatore](../../../.scratch/cascade-product/issues/50-addon-cpu-violation-classification.md) è implementato da Terra medium e revisionato da root e Sol medium: PASS, 76 test mirati in cinque suite, inclusi cinque nuovi test. L’osservazione per owner contiene direttamente `noNewViolation`, `moderate` o `unavailable`. Il predicato richiede un addebito nuovo e positivo, acquisito con successo, che lasci il conto oltre credito. Una prova positiva resta valida anche quando manca una misura di un altro processo; in assenza di tale prova, un giro incompleto non viene dichiarato sano. L’errore contabile persistente resta non disponibile.

Root ha richiesto di evitare un secondo elenco parallelo di owner e di provare realmente il rimborso del debito fino a saldo esattamente zero. I test verificano anche più processi nello stesso giro, isolamento fra owner e campioni espliciti/periodici allo stesso istante senza riprodurre una misura nativa già consumata. Il rapporto distingue la prima compilazione per API assente dal red comportamentale successivo con ramo di classificazione disabilitato e dal green finale.

Il [collegamento alla salute del runtime](../../../.scratch/cascade-product/issues/51-addon-runtime-cpu-health.md) è implementato da Sol medium e revisionato da root e Sol medium: PASS. Il runtime possiede coordinatore e `AddonHealthStore`, con sessioni legate a identità/versione e incarnazione canonica, senza batch esterni da riapplicare. Un’operazione alla volta impedisce consegne duplicate o registrazioni parziali; la rivalidazione dopo le attese scarta misure obsolete. Debito e cronologia sopravvivono al riavvio del provider. La terza violazione registra la quarantena interna della versione, senza introdurre ancora una sanzione sulle ammissioni.

La revisione ha corretto un’omissione del cleanup: gli stop per deadline potevano lasciare un binding osservativo registrato. Il distacco passa ora attraverso `hasDeferredCleanup` e il drain comune protetto; registrazione e campionamento rifiutano cleanup pendente o attivo. Il binding non può essere riutilizzato prima del distacco precedente. Otto nuovi test verificano anche owner distinti, dati mancanti, registrazioni duplicate/rifiutate, rollback, stop durante lettura e uscita durante registrazione. Le pause delle fixture sono limitate a cinque secondi. Un red comportamentale con registrazione degli incidenti soppressa produce otto errori attesi; la versione ripristinata passa.

## Confini

Tutto il lavoro riguarda gli addon. Nessun launcher, adapter nativo o timer viene attivato; le osservazioni non provano autenticazione del processo, stop o uscita fisica. La qualifica su altre piattaforme e il costo energetico restano separati. I test con adapter e letture sintetiche provano la logica interna, non garanzie native.

La reazione concreta ai primi sforamenti richiede [definire la riduzione dei nuovi lavori](../../../.scratch/cascade-product/issues/52-addon-cpu-reduced-admission.md). Il limite esistente è già un job per addon: la generica «riduzione delle concessioni» non specifica quando riaprire. Nessuna delle alternative è ancora implementata. Il blocco del launcher resta invariato.

## Evidenze

[Rapporto del classificatore](../../../.scratch/codex-addon/20260921-cpu-violations/task-50-report.md), [revisione indipendente](../../../.scratch/codex-addon/20260921-cpu-violations/task-50-independent-review.md), [disegno della composizione](../../../.scratch/codex-addon/20260921-cpu-violations/health-integration-design.md). Baseline: 1.122 test in 99 suite e 482 input di build congelati prima del lavoro.


## Verifica finale e consegna

- 100 test mirati complessivi PASS: 98 in sette suite runtime e due in una suite trasporto.
- Suite package completa eseguita da root, exit0: **1.135 test in 101 suite**, somma dei cinque prodotti (745/59, 112/11, 170/19, 91/10, 17/2). Il messaggio CoreData relativo al database corrotto appartiene a una fixture negativa attesa.
- Revisioni root e indipendenti PASS sui quattro file congelati: due sorgenti modificati e due nuovi file di test. Nessun input preesistente rimosso; altri sorgenti del checkout dirty preservati.
- Build ufficiale `scripts/build-development.sh` su copia locale identica dei **484 input**: controllo SDK PASS (4 package, 11 target, 90 sorgenti Swift, 140 import), Xcode Debug PASS, firma Apple Development e `codesign --verify --deep --strict` PASS. Hash originali/copia e file revisionati ricontrollati dopo la build.
- `/Applications/Cascade.app` aggiornato alla build verificata. Chiusura normale e riavvio **PID 25071 → 32112**, percorso eseguibile corrispondente alla build e presenza stabile verificata dopo cinque secondi.
- Budget settimanale residuo **90%** all’ultima verifica; nessun reset utilizzato. Arresto del lavoro alla nuova scelta progettuale 52, non per budget. Wayfinder usato soltanto per gli addon; launcher e qualifica nativa restano separati.

[Rapporto runtime](../../../.scratch/codex-addon/20260921-cpu-violations/task-51-report.md), [revisione runtime](../../../.scratch/codex-addon/20260921-cpu-violations/task-51-independent-review.md), [revisione root](../../../.scratch/codex-addon/20260921-cpu-violations/root-review.md), [log suite completa](../../../.scratch/codex-addon/20260921-cpu-violations/package-tests.log), [log build](../../../.scratch/codex-addon/20260921-cpu-violations/application-build.log), [consegna verificata](../../../.scratch/codex-addon/20260921-cpu-violations/delivery.json), [controllo input](../../../.scratch/codex-addon/20260921-cpu-violations/input-verification.json).
