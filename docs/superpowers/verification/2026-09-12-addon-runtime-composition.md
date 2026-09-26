# Coordinatore degli addon — verifica del 12 settembre 2026

Il task C2b2 è implementato e approvato nella copia di lavoro isolata. Il package
supera **436 test**, con revisione indipendente conclusa senza rilievi richiesti.
Questo risultato qualifica la composizione interna del runtime; il launcher nativo,
l'integrazione nell'app e la feature completa rimangono da qualificare.

## Comportamento verificato

`AddonRuntime` coordina catalogo e dipendenze risolte, assegnazioni delle pubblicazioni,
avvio e collegamento dei provider, azioni e servizi usando lo stesso
`ResourceGovernor` del broker privato. Il contenuto, la cronologia dei risultati,
gli interessi dei servizi e il processo hanno durate distinte. L'uscita prevista di
un provider conserva le pubblicazioni e gli interessi ancora validi; la nuova
generazione deve ottenere autorizzazioni nuove.

Le ammissioni e la restituzione delle risorse condividono un solo proprietario
dell'operazione. Le sospensioni verso gli actor del broker e delle risorse sono
seguite da controlli dell'autorità corrente. Disattivazione e scadenza di un lavoro
possono richiedere subito l'arresto del provider anche mentre un'altra ammissione
è sospesa. I permessi del lavoro incerto rimangono conteggiati fino all'uscita
esatta osservata; una richiesta di arresto non equivale a quell'uscita.

Il trasporto interno distingue il messaggio ancora in ricezione da quello già
trasferito all'operazione che lo elabora. Il limite viene comunicato prima della
conservazione; il trasferimento mantiene occupato il posto. Ripetere una ricezione
non permette di scartare il messaggio che un'altra operazione sta elaborando.

Un completamento di servizio in attesa non conferisce un esito recuperabile,
un aggiornamento della sequenza o una restituzione dei permessi. Il broker rimane
l'unico registro dei risultati. La ricezione conserva l'istante campionato
dall'host senza ripristinare autorizzazioni revocate. L'esito immediato deriva
dalla conferma effettiva; la rimozione di una voce durante l'uscita del processo
non viene interpretata come successo.

I completamenti senza modifica del contenuto convalidano la propria sessione e
sequenza. Due provider indipendenti non si invalidano a vicenda tramite la revisione
globale delle pubblicazioni. I normali batch di contenuti conservano i controlli
atomici già presenti. Rimangono i controlli di replay, revoca e vecchia generazione.

Le proiezioni dei dati di configurazione e della risoluzione vengono limitate
prima della codifica e della conservazione, comprese le stringhe annidate nelle
versioni. I test verificano anche quote ristrette, esiti conservati con quota piena,
restituzioni esatte, riferimenti alle pubblicazioni e revisione di autorità esaurita.

## Prove e revisione

Ambiente: Xcode beta, cache dei moduli in
`/private/tmp/cascade-addon-clang-cache`, scratch SwiftPM
`/private/tmp/cascade-addon-swift-build`. Dalla directory `CascadeKit`:

```sh
swift test --no-parallel --scratch-path /private/tmp/cascade-addon-swift-build
```

Risultato: exit 0, **436 test**: Runtime205, Presentation20, motore169,
Contracts38, tool4. Log `/private/tmp/cascade-c2b2-fix3-full-package.log`,
SHA-256 `3349e5e5d969f80613945a5c068912f8d54f918188c81a33ce34d08fc337fee0`.

La verifica mirata delle otto suite interessate passa104 test. Non va sommata alla
suite completa, che la comprende. Tutti i14 hash dei file della correzione sono
stati confrontati con il rapporto e ricontrollati dopo la verifica completa.

La revisione iniziale e le tre successive revisioni delle correzioni hanno chiuso
i rilievi sulla proprietà delle risorse, le autorità e i completamenti concorrenti.
Il verdetto finale è Spec compliance PASS e Code quality APPROVED, senza rilievi
richiesti o nuovi difetti importanti nell'ultima modifica. I rapporti, i diff
immutabili e le prove RED/GREEN sono conservati nella directory del piano
`.superpowers/sdd/2026-09-10-addon-runtime-completion/continuation-production/`.
Gli errori della preparazione dei test e l'errore di spazio disco sono registrati
separatamente dai fallimenti comportamentali.

## Limiti attuali

L'adapter usato dalle prove è interno ai test. Non sono ancora qualificati trasporto
IPC produttivo, decodifica nativa, arresto del worker alla morte del supervisore,
scene remote, altri editori o versioni macOS non eseguite. La prova seriale usa la
modalità già adottata dal progetto; il precedente problema del test AppKit eseguito
concorrenzialmente rimane documentato separatamente e non viene dichiarato risolto.

Questa continuazione non è ancora integrata nel checkout originale e non ha ancora
prodotto build, aggiornamento del collegamento Applications o riavvio dell'app.
Il successivo task C0o è un esperimento limitato su identità e dati di due owner,
non l'ammissione automatica del launcher. Il [piano di completamento](../plans/2026-09-10-addon-runtime-completion.md)
mantiene separati i prerequisiti nativi e le altre consegne.

Verifica aggiuntiva prima dell’integrazione: l’asserzione di `ActionDispatcherTests` sul riferimento alla pubblicazione dopo la scadenza della cronologia è stata controllata separatamente, perché non figurava nei14 hash finali. Revisione approvata e singolo test passato sulla versione corrente; questa prova non sostituisce una sequenza completa di pruning nel runtime.

## Integrazione e build del 12 settembre

43 file approvati sono stati integrati nel progetto principale;332 input di build
sono stati confrontati e risultano identici alla copia verificata. La build dal percorso
del progetto è stata interrotta dopo aver osservato Xcode in attesa di NSFileCoordinator
nella lettura ricorsiva del progetto. Il solo processo della build è stato interrotto,
con uscita effettiva osservata; nessuna impostazione iCloud o app Xcode è stata cambiata.

Lo stesso script ufficiale ha poi compilato con successo dalla copia locale identica,
con firma verificata e collegamento `/Applications/Cascade.app` aggiornato. Cascade è
stata chiusa normalmente (PID8956) e riaperta dalla build nuova: PID47210, percorso
atteso e stabilità verificati. Log `/private/tmp/cascade-production-20260912-local-app-build.log`;
record `/private/tmp/cascade-production-20260912-restart.json`.

Questa consegna integra le basi del runtime e il prototipo verificato nel progetto.
Non abilita ancora gli addon nel prodotto né conclude le migrazioni dei widget.
Prosegue l’implementazione dello storage condiviso e del percorso nativo completo.
