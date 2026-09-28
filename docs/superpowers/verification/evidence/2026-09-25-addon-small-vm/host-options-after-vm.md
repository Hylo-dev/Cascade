# Riesame delle opzioni host dopo la VM — 26 settembre 2026

Solo ricerca: nessun nuovo processo addon/helper/root della fixture, segnale,
sospensione, privilegio o modifica dell’app. La pausa richiesta dall’utente è
rispettata. La policy contro i processi gestiti orfani e il gate restano invariati.

La prossima prova candidata è **il recupero amministrativo di un provider avviato
normalmente**, autenticato, con guardia già attiva, root e broker vivi. Non risulta
già eseguita nelle evidenze consultate; il SIGCONT previsto dal runner VM non è
mai stato raggiunto. Il comando da valutare nel successivo disegno esecutivo è:

```text
launchctl kill SIGKILL pid/<broker-autenticato>/<job-esatto-della-fixture>
```

Non è un comando da eseguire ora. Nessun sudo sull’host è implicito. Il manuale
pubblico descrive l’invio del segnale al servizio in esecuzione. L’eventuale PASS
richiederebbe l’uscita SIGKILL della precisa istanza già registrata in kqueue,
prima delle guardie, senza richieste concorrenti di avvio o nuova incarnazione.
Diniego, timeout o intervento del cleanup restano FAIL/inconclusivi. Il recupero
ordinario tramite root già misurato sarebbe separato dal risultato.
[Manuale locale launchctl](</usr/share/man/man1/launchctl.1>),
[prove di identità esterna](</Users/c4v4h/Library/Mobile Documents/com~apple~CloudDocs/Projects/XcodeProjects/Cascade/docs/superpowers/verification/2026-09-25-addon-external-identity.md>).

**Servizio non significa incarnazione.** Il comando indirizza il servizio corrente,
non un audit token. Inoltre `pid/<pid>` risolve il dominio mediante un numero PID:
la connessione conservata al broker e controlli prima/dopo non ne impediscono
atomicamente il riuso. Occorre rivedere questo indirizzamento prima dell’esecuzione;
un PASS col dominio vivo non qualifica recupero dopo la morte di broker/root.
Il parsing di `launchctl print` resta diagnostico, non API produttiva.
[Manuale locale launchctl](</usr/share/man/man1/launchctl.1>).

**Nessun passaggio automatico a SIGSTOP/SIGCONT o START_SUSPENDED.** Un processo
fermato dopo HELLO ha già eseguito codice. Una guardia SIGALRM attiva può restare
pendente mentre il processo è fermo: non è un recupero indipendente. XNU 14 usa
`task_suspend_internal` sia nello stop da segnale sia nello spawn sospeso, ma ciò
non rende equivalenti il punto temporale o i contatori misurati su ogni OS.
SIGKILL ha un percorso specifico; il suo successo su un processo ordinario non è
già una prova sul provider fermo prima della prima istruzione.
[XNU segnali](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/kern/kern_sig.c#L2155),
[XNU spawn sospeso](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/kern/kern_exec.c#L1862).

Una calibrazione separata potrebbe creare un minuscolo figlio diretto ordinario
con `POSIX_SPAWN_START_SUSPENDED`, acquisire task-name port/token/firma senza HELLO,
poi terminarlo e confrontare kqueue con wait. Il controller vivo, unico reaper,
con SIGCHLD predefinito e senza SA_NOCLDWAIT conserva il PID del proprio figlio
fino al reap; `WNOWAIT` non lo consuma. È diverso da un PID scoperto. Ma la morte
del controller fa perdere quel presupposto: **non risolve il lifetime EF e non
offre il contenimento della VM**. Non la propongo come prossimo esperimento né
come nuova prova necessaria per sbloccare il prodotto.
[Apple spawn](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/posix_spawnattr_setflags.3.html),
[Apple DTS e limiti di compatibilità](https://developer.apple.com/forums/thread/842442),
[XNU reap/WNOWAIT](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/kern/kern_exit.c#L2562).

Non serve una scelta architetturale per questa ricerca o per progettare la prova
ordinaria. Adottare figli diretti al posto di EF oppure launchctl come controllo
produttivo sarebbe invece una scelta nuova, con problemi di packaging, privilegi
e lifetime ancora da risolvere. Non si ripropongono invalidate già fallito,
guardie/EOF dopo main o un’eccezione agli orfani già rifiutata.
[Analisi spawn già conclusa](</Users/c4v4h/Library/Mobile Documents/com~apple~CloudDocs/Projects/XcodeProjects/Cascade/docs/wayfinder/research/2026-09-24-spawn-managed-lifetime.md>).
