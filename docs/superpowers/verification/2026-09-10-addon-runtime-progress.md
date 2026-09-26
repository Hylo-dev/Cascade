# Addon runtime — avanzamento del 10 settembre 2026

La feature non è conclusa. È terminata l'indagine C0 con esito **bloccato**; sono disponibili parti indipendenti di C2, C4 e C12, estese nella continuazione descritta sotto. L'utente ha successivamente [accettato il rischio del lavoro delegato](../specs/2026-09-10-addon-control-policy.md). Il piano è stato aggiornato su quel solo confine; nessun launcher è stato abilitato e gli altri difetti tecnici restano da risolvere.

## Codice implementato e revisionato

- `PublicationStore.accept([Publication], owner:)`: fino a 16 identità distinte, un istante comune, aggiornamento atomico di contenuti/quote/revisioni. Il fallimento di una voce ripristina ogni voce precedente. Un solo conteggio senza copie dello store per batch. Quattro test nuovi, incluso un test di mutazione che rileva l'omissione del ripristino dei byte.
- `ResourcePolicy` e `ResourceGovernor`: prenotazioni dell'host, limiti per addon e globali su lavoro, contenuti, memoria ammessa e disco; metadati delle prenotazioni conteggiati; rilascio canonico per proprietario e rilascio automatico al termine dell'operazione anche su errore. Dieci test nuovi. I valori di memoria sono stime di ammissione e non limiti istantanei del processo; non sono ancora collegati a launcher, scheduler o broker.
- `cascade-addon validate`: eseguibile Swift dipendente solo dai contratti pubblici. Legge file regolari con limite prima del parsing, usa AddonManifest.decode e restituisce esiti distinti per dati non validi e argomenti errati. Quattro test nuovi e verifica dell'eseguibile reale. [Guida](../../addons/README.md).
- Harness C0: validatore dei report e regressioni per non considerare prova di uscita un errore di osservazione, né invalidazione autenticata un messaggio mancante. Deadline comune di cinque secondi nei limiti delle attese richieste. Dieci test del validatore e otto del produttore di evidenze; non sostituiscono osservazioni native.

## Verifica del primo incremento

Suite intera: `swift test --package-path CascadeKit --scratch-path /private/tmp/cascade-addon-swift-build --no-parallel --disable-sandbox`, Xcode beta. **248 test passati**, exit 0: Runtime49, Presentation15, motore156, Contracts24, tool4. Log `/private/tmp/cascade-completion-current-all-tests.log`.

Sono conservati i RED comportamentali e i GREEN mirati. Le revisioni delle tre parti Swift sono passate; anche i tre rilievi della revisione C0 sono stati corretti e rivalutati. Nessun commit o staging del lavoro preesistente.

Le [prove native](2026-09-10-addon-launcher-decision.md) conservano i controesempi. Venti sequenze di arresto del figlio diretto e quaranta echo hanno prodotto misure, senza qualificare il launcher. Il worker può sopravvivere al supervisore e può avviare una fixture innocua tramite Launch Services; il cambio eseguibile conserva il canale diagnostico. Le correzioni successive degli harness hanno nuove prove deterministiche, non sono presentate come una nuova esecuzione dei vecchi esperimenti nativi.

Build app: **riuscita**, exit 0, con lo script ufficiale dalla copia locale verificata. L'avvio dal checkout iCloud si era fermato in NSFileCoordinator prima della compilazione, confermato da sample; prima del nuovo tentativo sono stati confrontati 259 file di input identici. Firma deep/strict verificata e `/Applications/Cascade.app` aggiornato alla build `CascadeAddonDevelopment`. Riavvio verificato: PID59576 → PID65407, stesso percorso atteso in DerivedData. Log `/private/tmp/cascade-completion-current-app-build-local.log` e `/private/tmp/cascade-completion-current-restart.json`. La toolchain ha emesso avvisi sulle variabili SWIFT_DEBUG_INFORMATION nel post-action; nessun errore di compilazione. La revisione complessiva di questo incremento è passata e non certifica il completamento della feature.

## Continuazione dopo la decisione sul controllo diretto

- `ActionJournal`: richiesta duplicata senza nuovo lavoro, distinzione fra invio/ricezione/esito, risultato incerto senza retry automatico, rifiuto di risposte di altre generazioni; spazio per la risposta riservato prima del comando.
- `AddonScheduler`: un lavoro per addon e due globali, quattro comandi pendenti, aggiornamenti accorpati, priorità con invecchiamento e posti liberati solo alla conclusione effettiva del lavoro. Scadenze scadute e disattivazioni vengono restituite al coordinatore, senza perdita silenziosa dei comandi.
- `DeadlineQueue` e `RuntimeInstant`: date civili separate dal tempo trascorso, sostituzioni limitate e drenaggio una volta sola dopo sleep/wake. Nessun timer o processo proprio.
- `AddonHealthStore`: storia della versione limitata, quarantena, ritardi di retry, ticket monouso e invalidazione delle vecchie sessioni. Nessun campionamento o arresto nativo attribuito a questa componente pura.
- [Nuove prove C0](2026-09-10-addon-direct-v1.md): controllo isolato dei messaggi tramite audit token positivo dopo exec, inclusa una risposta già in coda; pulizia del gruppo launchd insufficiente per i processi gestiti che cambiano gruppo/sessione. Il nuovo record `launcher-admission-direct-v1` resta negativo; la limitazione già accettata non viene estesa.

Le revisioni hanno corretto il ricalcolo della scadenza civile di un comando già ammesso e due problemi dei nuovi harness: possibile confusione fra guardrail e arresto effettivo, perdita del rapporto durante errori di pulizia. La revisione della salute della versione ha corretto anche un alias del numero di versione che poteva separare le storie di quarantena; le tre revisioni mirate sono concluse senza rilievi aperti. Le nuove componenti pure devono ancora essere collegate al runtime produttivo e al controllo aggregato delle risorse. [Contratto di lifecycle](../../addons/lifecycle.md).

Verifica della continuazione: **288 test Swift passati**, exit 0 (Runtime89, Presentation15, motore156, Contracts24, tool4), log `/private/tmp/cascade-direct-v1-final-swift.log`. **36 test Python passati**, log `/private/tmp/cascade-direct-v1-full-python.log`. I nuovi casi Swift sono 40: 26 su scheduler/scadenze/azioni e 14 su salute/retry. Conservati i RED comportamentali dei difetti corretti. L'avviso sulla variabile weak nei vecchi test di PublicationStore è preesistente.

Integrati 25 file esatti con controllo dei contenuti rispetto alla baseline e alle modifiche già presenti; confrontati 267 input di build identici fra copia locale e checkout iCloud. Nessun commit o staging. La revisione complessiva della continuazione è passata senza rilievi P1/P2. Build app **riuscita**, exit 0, tramite lo script ufficiale `scripts/build-development.sh` dalla copia locale verificata; firma deep/strict verificata e collegamento `/Applications/Cascade.app` aggiornato. Le due istanze precedenti, PID66182 e PID73001, sono state chiuse tramite le API native senza forzatura; alla verifica finale è in esecuzione una sola istanza aggiornata, PID74458, nel percorso atteso `CascadeAddonDevelopment`. Log `/private/tmp/cascade-direct-v1-app-build.log` e `/private/tmp/cascade-direct-v1-restart.json`. I risultati del primo incremento sopra restano storici. Questa verifica conclude il presente incremento, non la feature completa.

## Continuazione servizi e stato

Il [rapporto servizi e checkpoint](2026-09-10-addon-services-storage.md) registra l'incremento successivo: broker host, permessi, interessi condivisi, protezione dei requestID e persistenza limitata con migrazioni. I conteggi e i riavvii riportati sopra restano prove storiche delle rispettive revisioni.

## Continuazione delle azioni

`ActionAuthorizer` e `ActionDispatcher` aggiungono autorizzazione sul contenuto corrente, controllo al consumo monouso, composizione transazionale del journal/scheduler e contabilità locale combinata.36 test mirati passati,15 nuovi. Corretto e rivalutato il recupero dell’esito dopo rimozione della pubblicazione: la cronologia resta accessibile al contesto autorizzato senza creare altro lavoro o rinnovare le scadenze. Restano annotate due osservazioni minori su stile e avvisi preesistenti; il coordinatore actor, la quota globale e il trasporto nativo non sono inclusi in questa prova. [Contratto](../../addons/actions.md).

## Continuazione del coordinatore — 12 settembre

`AddonRuntime` compone ora le componenti pure con autorità canonica, governor comune,
ammissioni e restituzioni coordinate, interessi durevoli e completamenti indipendenti
per sessione. La [verifica corrente](2026-09-12-addon-runtime-composition.md) registra
104 test mirati,436 test completi seriali e revisione approvata senza rilievi richiesti.
Il codice è nella copia isolata; integrazione nell'app e qualificazione dei processi
restano separate. I conteggi e i riavvii precedenti sopra sono prove storiche.

## Resta da fare

C1 richiede un launcher ammesso e identità/canale reali. C2 richiede ora il collegamento del coordinatore approvato alla consegna reale e all'app; C3 collegamento del broker al trasporto, cache e sorgenti reali; C4 metriche native e collegamento delle decisioni di salute all'arresto verificato; C5 storage SDK per chiave, asset e ripristino delle pubblicazioni. C6–C10 comprendono Clock, timer, scene SwiftUI, avvisi e media sul percorso pubblico. C11–C13 comprendono distribuzione, strumenti restanti, parità, piattaforme e misure finali. Il minimo macOS14, altri editori e le scene remote non sono qualificati dalla macchina beta disponibile.

Il [piano](../plans/2026-09-10-addon-runtime-completion.md) resta la fonte del lavoro residuo. La decisione di prodotto sul lavoro delegato è risolta. Nessun addon nativo viene ammesso finché non sono provati arresto, identità e altri controlli del profilo aggiornato.

## Consegna verificata del 12 settembre

Coordinatore C2b2 e diagnostica C0o approvati e integrati:43 file,332 input di build
identici.436 test Swift seriali passati;54 test storici e26 test del prototipo passati.
Il bootstrap con sandbox ereditata ha completato4 casi e8 uscite normali osservate,
con dati separati e continuità dello stesso owner. Build firmata riuscita dalla copia
locale identica, collegamento Applications aggiornato e riavvio verificato da PID8956
a47210. L’avvio di Xcode sul progetto originale era in attesa di coordinamento file;
quel processo è stato interrotto, senza modificare iCloud o Xcode.

La feature rimane aperta: storage per chiave, trasporto e morte dei processi gestiti,
integrazione reale nell’app, migrazione dei nostri widget e qualificazione finale.
[Runtime e consegna](2026-09-12-addon-runtime-composition.md),
[prova del bootstrap](2026-09-12-addon-owner-bootstrap.md).

## Backend storage per chiave — 12 settembre

Implementato e revisionato C5b: valori indipendenti dal checkpoint, isolamento per
publisher/addon, quote condivise con gli altri consumatori, scritture atomiche, cache
separata e recupero dopo chiusura/errori. La prima revisione ha rilevato un errore nel
recupero della sincronizzazione delle cartelle; la correzione ha una riproduzione
comportamentale su nove scenari e un riesame mirato.38 test mirati e474 test della
libreria in modalità seriale passati sulla versione finale. Il risultato iniziale di
471 test resta storico. Trasporto SDK e restante C5 ancora aperti.
[Verifica e stato della consegna](2026-09-12-addon-keyed-storage.md).

## Diagnostica della morte del worker — C0d offline

Il nuovo osservatore e il protocollo finito D0–D3 sono approvati sul piano offline:
35 test nuovi, 54 storici e 26 owner passati. La correzione F01 conserva stdout e
osservazioni avverse quando la registrazione proc viene rifiutata. G01 è un requisito
operativo distinto: il driver termina con exit 78 prima di setup e compilazione.
La prova nativa resta sospesa per il confine del parent perso prima di PT_TRACE_ME;
nessun esito della piattaforma viene dedotto dai test simulati. C0 e la feature
restano aperti; il lavoro indipendente ha completato il backing raster C5c1 sotto descritto.
[Rapporto corrente](2026-09-12-addon-managed-death.md).

## C5c1 — backing raster approvato, 12 settembre 2026

Implementati memoria immutabile CoreGraphics, quota raster nel budget complessivo,
prenotazioni protette e rilascio limitato all'ultima referenza effettiva. La revisione
indipendente ha approvato conformità e qualità senza rilievi. 37 test mirati e 498 test
completi seriali passati sul sorgente congelato; nessun nuovo warning nel log finale.
Rimangono AssetState/SDK, decoder e autorizzazioni, renderer, cache e ripristino.
Nessuna prova nativa/tracing aggiunta e gate C0 ancora HOLD. L'utente ha chiesto
di fermarsi dopo la consegna di questo task; nessun C5c2 avviato.
[Contratto](../../addons/assets.md) e [verifica](2026-09-12-addon-raster-backing.md).
