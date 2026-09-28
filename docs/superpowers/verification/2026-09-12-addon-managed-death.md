# C0d — diagnostica offline approvata, esecuzione nativa sospesa

Sono implementati e revisionati l’osservatore e la sequenza diagnostica D0–D3 per
studiare l’uscita del worker dopo la morte del supervisore. **La prova reale non è
stata eseguita e non è autorizzata dal driver corrente.** Lo script termina sempre
con codice 78 prima di creare prodotti, compilare, firmare o avviare partecipanti.
Non esiste un’opzione o variabile per aggirare il blocco. Rimuoverlo richiede una
modifica di progetto e sorgenti revisionata separatamente.

## Comportamento implementato e verificato offline

Un solo ciclo osserva output e notifiche dei processi, conservando identità, status,
ordine e limiti. La richiesta di arresto non equivale all’uscita osservata. Il PID
del supervisore diretto resta riservato prima del fallback e del wait finale. Gli
esiti mancanti, le code inutilizzabili e l’assenza dello status restano sconosciuti.
I quattro casi si fermano al primo risultato incompleto o negativo, senza retry.

La prima revisione ha rilevato F01/P2: un rifiuto della registrazione proc faceva
perdere stdout già disponibile. Il primo giro di correzione conserva il drenaggio
limitato, senza riprovare la registrazione, registrare PID tardivi o rilasciare un
permesso di avvio. Un test causale riproduce la perdita prima della correzione.
G01, il blocco operativo dello script, è un requisito successivo distinto. Il suo
RED ha usato esclusivamente un mktemp finto che registra ed esce: nessun setup reale.

Verifica finale dopo la correzione, con comandi separati e uscita 0:

- 35 test ManagedDeathEvidenceTests, sul vero observer/reducer con endpoint simulati.
- 54 test storici Tracing e 26 OwnerBootstrapEvidenceTests invariati.
- Sintassi zsh e parsing Python validi. Il driver già protetto è stato invocato e ha
  restituito 78 come previsto; il corpo nativo è rimasto ineseguito.

Riesame: spec PASS, qualità APPROVED, F01 chiuso, G01 conforme, zero nuovi rilievi.
Sei hash sorgente verificati contro preimage esatti; nessuna modifica fuori scope.
Log e report iniziali rimangono distinti da quelli di correzione. Log finali nella
cartella di lavoro `continuation-managed-death`: `C0d-fix1-death-green.log`,
`C0d-fix1-historical-green.log`, `C0d-fix1-owner-green.log`.

## Perché il gate nativo resta chiuso

Le iniezioni intenzionali D2/D3 avverrebbero dopo tracing confermato. Tuttavia una
morte anticipata del supervisore, anche durante cleanup, può precedere la chiamata
dello Stub a PT_TRACE_ME. Un segnale al gruppo non prova un ordine atomico fra i due
processi. Nel sorgente pubblico XNU quel ramo usa il parent corrente e può raggiungere
la logica di modifica delle protezioni anche per tale parent; dopo riassegnazione,
non è dimostrato che sia ancora un processo della prova. I controlli di policy possono
rifiutare l’operazione, ma l’esito della beta installata non è noto. Non è stato
osservato né provocato alcun cambiamento di launchd. [XNU ptrace](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/kern/mach_process.c),
[XNU code signing](https://raw.githubusercontent.com/apple-oss-distributions/xnu/main/bsd/kern/kern_cs.c).

Per questo non eseguiamo deliberatamente tracing dopo la perdita del parent e non
consideriamo il controllo getppid prima/dopo come un vincolo atomico. La proposta
C0e E2 è stata ritirata. Nessuna nuova eccezione di privilegi, modifica della GUI o
accettazione implicita di rischio è stata introdotta. I risultati nativi C0o già
osservati con parent vivo restano storici e non vengono riscritti.

## Consegna e limiti

Integrati sei file diagnostici e tre documenti, con 400 input non documentali
identici fra originale e copia locale (inclusi i prototipi). I 337 input già usati
per la build C5b sono invariati: nessuna modifica al codice dell’app e nessuna nuova
compilazione necessaria. La firma deep/strict è riconfermata con esito 0; lo stesso
controllo confinato aveva restituito CSSMERR_TP_NOT_TRUSTED, senza modifiche al
portachiavi. Il collegamento Applications è quello della build C5b firmata. Riavvio
verificato: PID 51942 chiuso senza forzatura, nuova istanza stabile PID 53808 nel
percorso atteso. Record `/private/tmp/cascade-c0d-offline-20260912-restart.json`.
I 474 test Swift della precedente consegna non vengono presentati come prova C0d.

Compilazioni native C0d: 0. Partecipanti nativi C0d: 0. Uscita del tracee fermo/in
esecuzione, autorizzazione NOTE_EXITSTATUS e compilazione dei rami C nuovi restano
non misurate. Launcher produttivo, template distribuito, morte dell’host e gare di
avvio restano non qualificati; protezioni VM complessive sconosciute. C5c può avanzare
sulle risorse delle immagini senza aprire questo gate o duplicare il runtime.
