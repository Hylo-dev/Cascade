# Azioni e controllo nativo — continuazione del 10 settembre

Il lavoro è in corso. Nessun launcher produttivo è stato abilitato e la feature non è conclusa. La precedente [verifica luci/sessioni](2026-09-10-addon-light-sessions.md) resta storica; i risultati qui descritti riguardano la nuova continuazione.

## Autorizzazione e comandi

`ActionAuthorizer` controlla installazione verificata, feature assegnata, dipendenze correnti, pubblicazione/revisione utilizzabile e input effettivamente pubblicato. `ActionDispatcher` compone journal e scheduler entro un solo limite locale di 8 MiB, inclusi risultati riservati e metadati. Prima della consegna consuma un ticket canonico una sola volta e ricontrolla il contesto corrente.

Disattivazione, timeout o perdita della connessione dopo invio conservano l’esito incerto e richiedono l’arresto; il posto di un lavoro ancora attivo viene liberato soltanto con conferma della sua conclusione effettiva. Alla scadenza della cronologia, i metadati minimi di un lavoro ancora attivo rimangono conteggiati. Lo stesso requestID non può essere riusato fino all’uscita esatta del vecchio lavoro.

La revisione ha rilevato e fatto correggere un caso concreto: un’azione poteva chiudere la propria pubblicazione e rendere irrecuperabile il risultato già registrato. Il recupero ora usa l’identità e la feature ancora autorizzate e la richiesta originale esatta; non richiede una pubblicazione ancora presente. Le nuove azioni e la consegna mantengono invece il controllo del contenuto corrente. Una richiesta duplicata non rinnova la cronologia e non crea un nuovo lavoro.

Verifica mirata corrente: 36 test in 4 suite passati, 15 nuovi rispetto alla baseline. Log `/private/tmp/c2a-fix1-green.log`; conservata la regressione RED `/private/tmp/c2a-fix1-red.log`. Revisione della correzione conclusa senza nuovi problemi. I rilievi di formato sono stati poi corretti e rivalutati:81 test mirati passati e nessun rilievo residuo. [Contratto pubblico](../../addons/actions.md).

Queste sono componenti possedute dall’host. La composizione nell’actor autorevole è ora in lavorazione, come descritto sotto; il trasporto e i processi reali restano da collegare.

## Stato unico e variazione delle quote

Le regole e i registri dei contenuti sono stati estratti in `PublicationState`, un valore interno sincrono. L’actor pubblico `PublicationStore` mantiene le API esistenti e delega alla stessa implementazione. Il runtime potrà così possedere direttamente contenuti e azioni, evitando un controllo basato su uno snapshot diventato vecchio durante un’attesa.45 test mirati e revisione indipendente superati; i successivi aggiustamenti di commento e formato sono conclusi e revisionati.

`ResourceGovernor` può ora variare atomicamente una prenotazione di stato già esistente. La crescita viene ammessa soltanto per la differenza necessaria, rispettando il limite comune e quello dell’owner; la riduzione restituisce spazio e conserva ID e quota dei metadati. Un rifiuto lascia invariati i conteggi e le altre prenotazioni.55 test mirati, inclusi8 nuovi, e revisione indipendente superati. Questa operazione modifica il conteggio: il runtime deve ancora possedere e ricontrollare l’autorità dell’operazione prima di conservare un nuovo contenuto.

## Composizione del runtime — cronologia delle revisioni

Aggiornamento del 12 settembre: la composizione ha concluso la revisione con tutti i rilievi risolti,104 test mirati e436 test completi seriali passati. Il [rapporto aggiornato](2026-09-12-addon-runtime-composition.md) descrive i sorgenti approvati e i limiti; i paragrafi seguenti conservano la cronologia precedente.

Il nuovo `AddonRuntime`, ancora interno alla libreria, riunisce contenuti, azioni, catalogo autorizzato e collegamenti agli addon. La prima implementazione usa lo stesso `ResourceGovernor` per le proprie risorse e per il broker dei servizi. Sono stati aggiunti la preparazione degli aggiornamenti prima del commit, i completamenti correlati, l’avvio delle dipendenze nell’ordine risolto e il recupero dei risultati senza nuovo lavoro. La chiusura ordinaria del provider invalida i vecchi grant e conserva gli interessi ancora validi, da riattivare attraverso una nuova acquisizione autorizzata.

La prima revisione indipendente ha individuato 22 rilievi. Il primo giro di correzioni ha superato 99 test mirati in 8 suite, inclusi 22 test di composizione; i 14 hash dei sorgenti e delle prove sono stati verificati. La nuova revisione ha confermato 13 rilievi risolti, ne mantiene aperti 9 e ne aggiunge uno: restano quindi 10 correzioni richieste, 6 P1 e 4 P2. Riguardano soprattutto l’autorità dei risultati dei servizi, la pulizia anche quando non c’è un’ammissione attiva, le scadenze delle singole richieste, la capacità e il trasferimento dello spazio dei dati, e la rimozione delle assegnazioni ancora autorizzate da una connessione. Il secondo giro di correzioni è stato interrotto alla soglia richiesta del 20% di uso residuo; il blocco non è approvato. I casi mirati F01/F07 sono stati riferiti passati, ma le modifiche del giro interrotto non hanno ancora una compilazione e verifica complessiva.

Sulla prima revisione congelata sono passati 91 test mirati in 8 suite. La successiva suite completa ha passato tutti i 192 test del runtime, i 20 della presentazione, i 38 dei contratti e i 4 del tool. Dei 169 test del motore, uno è fallito: `controlDragKeepsExpandedContentAliveUntilMouseUp` non ha osservato lo stato chiuso entro il proprio limite. Controller e test sono invariati rispetto alla baseline; la singola prova è poi passata isolatamente, ma la causa del fallimento nella suite completa non è ancora dimostrata. Il risultato complessivo resta pertanto negativo, con 423 test eseguiti e un fallimento. Log conservati: `/private/tmp/cascade-c2b2-full-package.log` e `/private/tmp/cascade-c2b2-control-drag-focused.log`. I conteggi mirati e completi si sovrappongono.

Sulla correzione congelata, una nuova suite completa ha eseguito 431 test: Runtime 200, Presentation 20, Contracts 38 e tool 4 passano; Engine 169 riproduce lo stesso singolo fallimento. Anche i soli 56 test del controller lo riproducono nell’esecuzione predefinita; la stessa build con `--no-parallel` li passa tutti, con il test del trascinamento concluso in 0,302 secondi. Queste osservazioni indicano una dipendenza dall’esecuzione concorrente, ma non dimostrano il meccanismo preciso. Il risultato predefinito complessivo resta negativo; non sono state modificate le sorgenti dell’interfaccia. Evidenze: `C2b2-fix1-root-package-verification.json` nello stage e log `/private/tmp/cascade-c2b2-fix1-full-package.log`, `cascade-c2b2-fix1-notch-suite.log`, `cascade-c2b2-fix1-notch-serial.log`.

L’avvio iniziale della suite era stato impedito dalla sandbox esterna durante la compilazione del manifest SwiftPM; l’esecuzione mirata fuori da quella sandbox ha consentito la verifica senza modifiche al codice. Le connessioni di prova non costituiscono autenticazione di processi reali e non abilitano un launcher produttivo. Integrazione nell’app, build firmata e riavvio restano da eseguire dopo le verifiche richieste.

## Prima prova di compatibilità del controllo nativo

Nuove fixture firmate usano un supervisore fidato senza App Sandbox e due eseguibili di prova con il solo entitlement App Sandbox; tutti hanno Hardened Runtime. Non sono stati aggiunti permessi di debug o deroghe alla firma. I ruoli corrispondono ai profili già utilizzati; il processo grafico di Cascade non è stato coinvolto nella prova.

Sulla macchina disponibile (macOS 27 beta 26A5425a, arm64, SDK 27, firma Apple Development, target di compilazione macOS 14), due casi normali di confronto e un caso `PT_TRACE_ME` hanno prodotto sei uscite normali osservate. La chiamata ha restituito 0; 18 snapshot hanno conservato Valid/Hard/Kill=true e Debugged=false, con identità, firma e profili coerenti. I processi sandboxed hanno negato apertura di un file estraneo e connessione al listener locale della fixture; gli stessi accessi sono riusciti all’osservatore. Il limite hardNproc=0 non poteva essere rialzato.

Record immutato: `/private/tmp/cascade-tracing-native.eqB11w/report.json`; inventario degli hash `evidence-sha256.json` nella stessa directory. I processi sono terminati normalmente, confermati da wait del figlio posseduto e notifiche kernel di uscita; nessun guardrail ha prodotto quelle terminazioni.

Il risultato riguarda l’inizializzazione. Non dimostra ancora exec del worker, ispezione della nuova identità da fermo, morte del supervisore/host o integrità completa di ogni protezione VM. Le osservazioni usano domini temporali distinti per programma nativo e osservatore Python: non sono state sottratte date appartenenti ai due domini. Non c’è una misura di latenza di arresto per guasto.

La revisione ha confermato la credibilità della corsa effettiva e individuato cinque difetti del verificatore su evidenze parziali, progressione e pulizia dopo errore. Tutti e cinque sono stati corretti e rivalutati; 25 test offline passano. Il record nativo originale, conservato immutato, supera anche il verificatore più rigoroso. L’ammissione nativa rimane negativa, e `allVMProtectionsPreserved` resta sconosciuto. Una firma valida per macOS 14 non equivale a una prova eseguita su macOS 14 o con firma di distribuzione.

## Exec controllato e identità del worker

Una nuova build delle stesse fixture ha eseguito due confronti normali, il caso di inizializzazione del controllo e un solo caso di sostituzione Stub→Worker. Il supervisore ha osservato il vero arresto del figlio all’exec, verificato da fermo la nuova identità Worker tramite un riferimento Security fresco e ottenuto successo dall’unica chiamata di ripresa. I bit pubblici e il profilo sono rimasti coerenti con il confronto della stessa build.

La verifica successiva del Worker non è arrivata entro il limite originale: SIGALRM ha prodotto uno stop, il supervisore ha richiesto PT_KILL e ha osservato l’uscita effettiva per SIGKILL. Tutti gli otto processi creati hanno una conferma di uscita. Il risultato del caso è **sconosciuto**, non un rifiuto di piattaforma dimostrato. Record originale `/private/tmp/cascade-tracing-exec-N142j3/report.json`, SHA-256 `fbcee615d9abc433af01b2bdd8ec845a5550459e782a2b91048faa476a899824`.

Il punto di controllo veniva scritto dopo diverse chiamate CF/Security: la sua assenza non localizzava il blocco. La prova successiva ha aggiunto marcatori prima e dopo tali chiamate, senza allungare i tempi o cambiare permessi. La revisione del verificatore ha inoltre fatto correggere due casi di conclusioni eccessive con identità di processo o flag di guardia incompleti. Le correzioni hanno superato la revisione indipendente e 40 test offline; la rivalutazione del record conserva la sostituzione del worker osservata e il risultato complessivo sconosciuto. Le evidenze native restano conservate e l’ammissione produttiva rimane disabilitata.

## Localizzazione dell’avvio

Una successiva fixture ha aggiunto marcatori all’ingresso del Worker e prima/dopo le prime chiamate CF/Security.44 test offline, compilazione dei tre ruoli e revisione indipendente superati. Una sola nuova esecuzione dei confronti e del caso C ha conservato identità e protezioni pubbliche, ma nessun marcatore del Worker è arrivato. Dopo la ripresa è stato osservato un ulteriore SIGTRAP, seguito dall’arresto controllato e dall’uscita effettiva. Questa volta non è scaduto l’allarme; la differenza rispetto alla prova precedente è conservata. Tutti gli otto processi sono usciti.

I log di sistema, letti soltanto per il PID e l’intervallo della fixture, mostrano l’inizio dell’inizializzazione App Sandbox del Worker e nessun errore esplicativo. Il risultato resta sconosciuto; non dimostra un rifiuto preciso né un errore nella prima chiamata dell’addon. Record `/private/tmp/cascade-tracing-localization-BpyVoV/report.json`, SHA-256 `c7987d2b2ae28d8048b5a2ab268ae539c4ab5d06b205af0d1901429770f105e0`.

## Confronto senza tracing e rapporto di crash

Una sola nuova build ha ripetuto i confronti e la sostituzione controllata, poi eseguito la stessa transizione senza tracing. Profili, firme e limiti sono rimasti invariati. Il caso controllato ha nuovamente verificato la nuova identità da fermo, ripreso il Worker e osservato SIGTRAP prima del primo marcatore. Anche il Worker senza tracing è terminato per SIGTRAP prima di inviare marcatori. Tutti i dieci processi hanno conferme effettive di uscita; nel caso senza tracing non sono intervenuti guardrail o richieste di arresto.54 test offline e revisione indipendente superati, senza rilievi aperti.

I record grezzi mantengono il risultato sconosciuto: l’intenzione di eseguire il Worker, da sola, non autentica l’esecuzione. Separatamente, il rapporto di crash del sistema è stato correlato alla fixture tramite PID, genitore, orari, firma e UUID dell’eseguibile compilato. Localizza il guasto del caso senza tracing in `_libsecinit_appsandbox`, durante l’inizializzazione di libSystem, con indicazione `SYSCALL_SET_USERLAND_PROFILE`, prima dell’ingresso ordinario nel programma. Non specifica l’errore esatto né dimostra che il caso controllato abbia lo stesso stack. Il vincolo documentato sulla reinizializzazione della sandbox è coerente con il guasto, ma resta un’inferenza sulla causa precisa. [Discussione tecnica Apple](https://developer.apple.com/forums/thread/112800).

Record nativo immutato `/private/tmp/cascade-tracing-untraced-13iaN3/report.json`, SHA-256 `9d1d51fecf06d4bf24f9dfe597de5d246a5e73a988b8bd2a497b1d5a8f215d0e`; estratto del crash `worker-crash-extract.json` nella stessa directory, SHA-256 `07c162092ab4582bce36dbc8f9141eeb3808ca12fc5ed4158c3d85d011b2cdb1`. Questa localizzazione orienta la correzione della configurazione di avvio. Non abilita un nuovo profilo, non qualifica codice addon arbitrario e non dimostra ancora l’arresto alla morte del supervisore. Il launcher produttivo resta disabilitato.

## Integrazione e verifiche conclusive

La suite completa delle basi precedenti alla composizione C2b2 è passata: 408 test (Runtime177, Presentation20, motore169, Contracts38, tool4), log `/private/tmp/cascade-production-prerequisites-swift.log`. Le prove mirate si sovrappongono e non vanno sommate a questo totale. Non ancora eseguite per questa revisione: revisione complessiva, integrazione nel checkout condiviso, build firmata e riavvio. Il piano resta aperto. L’utente ha successivamente richiesto un arresto automatico al 20% di utilizzo residuo: il controllo periodico e il salvataggio del punto di ripresa sono predisposti, senza rinnovo automatico del limite né ripresa automatica del lavoro.

## Arresto richiesto dall’utente

Alle 23:47:19 UTC del 10 settembre (01:47:19 dell’11 settembre in Italia) il residuo è sceso al 20%. L’implementer è stato interrotto; gli altri agenti erano già conclusi e non restavano processi Swift della task. Il controllo periodico è stato verificato in pausa, senza reset o ripresa automatica. Sorgenti, evidenze e punto di ripresa vengono conservati nel checkpoint del progetto originale. Nessuna integrazione, build dell’app o riapertura della versione aggiornata è stata effettuata per questa continuazione.

## Ripresa del 12 settembre e bootstrap con sandbox ereditata

La nuova fixture C0o usa due identità di bootstrap distinte e due Worker che ereditano
la sandbox del rispettivo bootstrap. La prova prevista deve distinguere continuità dei
dati dello stesso addon, negazione dell’accesso ai dati dell’altro addon e sostituzione
controllata dell’eseguibile. Non è ancora un launcher produttivo.

La prima invocazione si è fermata nella preparazione: il comando di verifica della firma
ha interpretato il requisito come un percorso di file. Solo il Supervisor è stato compilato
e firmato, senza eseguirlo; nessuno dei quattro casi e nessuno degli otto processi previsti
è stato avviato. Il record conserva `unknown`, `complete=false` e `setupExit=1`.
È un errore nella fixture, non una prova negativa della piattaforma.

Sono passati54 test storici e16 test del nuovo verificatore, oltre ai controlli di sintassi
dello script e degli otto ruoli/configurazioni C. La revisione indipendente del codice è
in corso. Il rapporto iniziale resta immutato:
`/private/tmp/cascade-owner-bootstrap-eNbrVB/owner-report.json`, SHA-256
`3284962036f0f934c7cbca2f9e99edb8a7ddb726f03201bb6b9d61bb87ad5fcb`.
Una sola ulteriore preparazione/esecuzione è prevista dopo revisione e correzione, con
gli stessi limiti, senza ripetere casi già misurati o cambiare i permessi.

Correzione della precedente osservazione sui processi Swift: durante il controllo del
12 settembre sono stati trovati un vecchio `swift-test` e il suo helper, avviati l’11
settembre per una prova RED. L’assenza di sessioni attive dichiarata al precedente
checkpoint non dimostrava la loro uscita. Sono stati identificati precisamente, interrotti
e osservati uscire tramite notifiche del kernel prima di avviare C0o. Questa pulizia dei
test non costituisce una prova dell’arresto degli addon.

La successiva e unica esecuzione dopo le correzioni ha completato O1–O4, con otto uscite normali osservate. Il [rapporto del bootstrap](2026-09-12-addon-owner-bootstrap.md) conserva risultati, provenienza e limiti; revisione delle correzioni conclusa senza rilievi aperti.
