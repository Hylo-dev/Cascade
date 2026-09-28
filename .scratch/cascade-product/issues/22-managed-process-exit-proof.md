# Definire una prova sicura di uscita dei processi gestiti

ID: 22
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: open
Assignee: none
Blocked by: none

## Question

Quale disegno della prova può verificare l'uscita effettiva del worker dopo la morte del supervisore, anche se questa precede l'aggancio del tracing, senza coinvolgere un processo estraneo alla prova? Definire condizioni verificabili per rivedere il gate C0d; se manca un meccanismo conforme, registrare il limite senza abilitare il launcher.

## Contesto verificato — 14 settembre 2026

La [diagnostica offline C0d](../../../docs/superpowers/verification/2026-09-12-addon-managed-death.md) è implementata e revisionata. Il driver termina con codice 78 prima di compilare o avviare i partecipanti; la prova nativa resta ineseguita. La documentazione individua la gara tra morte del supervisore e tracing come impedimento ancora aperto. I controlli del parent prima/dopo non sono stati qualificati come vincolo atomico.

L'accettazione del rischio del lavoro delegato a macOS, documentata nella [politica di controllo](../../../docs/superpowers/specs/2026-09-10-addon-control-policy.md), è già acquisita e non risolve questo distinto requisito sui processi gestiti. I test del runtime puro e dello storage non qualificano il launcher.

Questo ticket prepara una decisione sul disegno e sulle prove necessarie. Non autorizza esecuzioni native, modifiche al gate o nuove eccezioni. La [prova della UI SwiftUI esterna](19-extension-host-probe.md) resta un'indagine distinta. L'esito alimenterà [installazione e isolamento delle estensioni](05-extension-distribution.md).

## Aggiornamento — 18 settembre 2026

Indagine Codex Astra high completata in sola lettura: [analisi dei meccanismi e delle prove mancanti](../../codex-addon/20260918-continuation/managed-process-design.md). Nessuna soluzione dimostrata copre ancora l’intera finestra di vita del worker. L’attach dal supervisore e la gestione tramite launchd richiedono qualifiche distinte; il solo protocollo di abort del bootstrap non dimostra l’uscita del processo in ogni fase. Nessuna prova nativa eseguita, nessun cambiamento al gate C0d; ticket aperto.

## Preparazione offline completata

Il successivo [modello finito del bootstrap](39-bootstrap-abort-offline.md) è verificato con31 test e revisione indipendente. Riproduce parsing, deadline e rifiuto di prove incoerenti usando esclusivamente osservazioni sintetiche. Non dimostra uscita fisica né copertura dalla creazione ad attach/exec; il presente ticket rimane aperto, senza autorizzare un esperimento nativo o modificare il gate.

## Punto decisionale — 20 settembre 2026

La prosecuzione corrente autorizza più incrementi fino a una decisione progettuale necessaria o al margine del tetto settimanale20%. Il [bootstrap C](40-bootstrap-abort-c.md) conclude la preparazione offline: main compilato, logica verificata in memoria, nessun processo nativo di prova eseguito. Non occorre un altro parser o modello equivalente.

Il passaggio al launcher incontra una garanzia ancora senza meccanismo qualificato: uscita effettiva anche quando il supervisore muore fra creazione del processo e ingresso del bootstrap in main. Lettura EOF e deadline iniziano a funzionare soltanto quando il codice fidato viene eseguito; non provano l'uscita durante uno stallo precedente. Resta inoltre da qualificare attach/stop sotto i profili di firma e sandbox attuali. Questo è un limite delle prove disponibili, non una dimostrazione di impossibilità della piattaforma.

**Scelta presentata all'utente (risolta sotto):** mantenere integralmente il requisito di uscita dei processi gestiti, lasciando il launcher disabilitato finché non esiste una soluzione qualificata (raccomandato), oppure aprire una revisione esplicita del requisito limitatamente al bootstrap fidato prima dell'attach. La seconda strada accetterebbe che quel processo possa restare vivo se non riesce a eseguire l'abort; non equivale a un timeout garantito e non estende l'eccezione al codice arbitrario dell'addon. Non è approvata da questa prosecuzione e non abilita automaticamente alcun launcher.

La [politica già approvata](../../../docs/superpowers/specs/2026-09-10-addon-control-policy.md) afferma: «Non rende accettabili un processo gestito orfano». L'eccezione sul lavoro delegato a macOS resta distinta e non va richiesta nuovamente. La decisione riguarda questa precisa garanzia, non una generica autorizzazione a continuare.

È già descritta una futura prova circoscritta senza tracing: baseline e perdita del supervisore, due partecipanti fissi per caso, identità conservate, osservazione dell'uscita effettiva e arresto al primo risultato incompleto. Anche un esito positivo dimostrerebbe soltanto l'abort nelle esecuzioni osservate; non chiuderebbe la finestra pre-main. Il [disegno esistente](../../codex-addon/20260918-continuation/managed-process-design.md) resta proposta ineseguita. Nessun gate, entitlement o requisito modificato.

Arresto richiesto alla decisione: nessun nuovo ticket chiuso, nessun agente lanciato e nessun nuovo test di prodotto eseguito in questa ricognizione. Ultimo contatore osservato1% settimanale, sotto20%; il budget non è la causa dell'arresto.

## Decisione dell'utente — 20 settembre 2026

«Manteniamo il launcher bloccato». Si conserva integralmente la garanzia di uscita effettiva dei processi gestiti, compreso il bootstrap fidato prima dell'attach. Nessuna eccezione per uno stallo prima di main. La scelta di policy è risolta e non va riproposta senza nuove indicazioni dell'utente.

Il launcher rimane disabilitato e il gate C0d invariato. Questo ticket resta aperto per il distinto problema tecnico della prova conforme; non si dichiara qualificato il launcher e non si sbloccano implicitamente le attività che lo richiedono. I test offline già consegnati conservano il loro ambito. Eventuali attività indipendenti restano soggette ai propri requisiti e al tetto settimanale20%.

## Ricerca successiva — 23 settembre 2026

[Verificare la gestione della durata tramite launchd](68-launchd-managed-lifetime-research.md) è conclusa con fonti Apple e verifica del relativo SDK: la pista non stabilisce la garanzia integrale già richiesta. Non è una prova di impossibilità generale né un esperimento nativo. La scelta di mantenere il launcher bloccato resta acquisita; il presente ticket tecnico rimane aperto.

## Prosecuzione del punto 1 — 24 settembre 2026

La richiesta «procediamo col punto 1» riprende la ricerca del launcher e del trasporto autenticato senza cambiare i requisiti. L'[esame di spawn/exec/fork](../../../docs/wayfinder/research/2026-09-24-spawn-managed-lifetime.md) non individua una primitiva pubblica di proprietà della durata dalla creazione: avvio sospeso, sostituzione dell'immagine ed eredità del tracing non chiudono la finestra nota. Il [raccordo launcher/trasporto](../../../docs/wayfinder/research/2026-09-24-launcher-transport-frontier.md) distingue la pista del servizio XPC legato al client dai precedenti LaunchAgent/Daemon, registra i requisiti ancora non qualificati e il limite dei controlli XPC sui messaggi in uscita. Include una domanda tecnica per Apple DTS, non inviata. Nessuna prova nativa, modifica al gate o ammissione produttiva; ticket ancora aperto per impedimento tecnico, senza riproporre la scelta di policy.

## Prova XPC successivamente autorizzata — 24 settembre 2026

La successiva istruzione «ok, procedi con la prova mirata XPC» autorizza il solo
esperimento isolato ora [eseguito e documentato](../../../docs/superpowers/verification/2026-09-24-addon-xpc-lifetime.md).
Il servizio fisso incluso nel bundle termina quando il client esce normalmente o
con SIGKILL, anche con callback trattenuto. Cancellare la connessione con il client
vivo non produce uscita nei due secondi osservati. Baseline cooperativa positiva;
uscita finale di tutti i partecipanti confermata, senza usare la guardia SIGALRM.
Restano non qualificati stop mentre l'host vive, copertura prima di main e pacchetti
esterni. Nessun cambiamento a gate, policy o ammissione; ticket ancora aperto.

## Intermediario XPC dedicato — prova successiva del 24 settembre 2026

Su richiesta «esplora e fai test per questa strada», la [fixture con due catene XPC annidate](../../../docs/superpowers/verification/2026-09-24-addon-xpc-broker.md)
supera quattro scenari nel ciclo finale: uscita ordinaria e SIGKILL del broker A
terminano il suo worker bloccato mentre app e catena B restano attive; uscita ordinaria
e SIGKILL dell'app terminano entrambi i broker e worker. Una prima simulazione di crash
ha prodotto un codice d'errore ed è stata conservata come FAIL, poi corretta e rieseguita.
Il risultato qualifica soltanto la fixture dopo main su questa versione di macOS.
Restano avvio prima di main, supporto del packaging annidato, pacchetti esterni e
arresto se anche il broker fidato non risponde. Ticket aperto e gate invariato;
nessuna nuova decisione di policy richiesta.

## Callback del broker bloccato — prosecuzione del 24 settembre 2026

La [prova successiva](../../../docs/superpowers/verification/2026-09-24-addon-xpc-broker-blocked.md)
conferma che stop e cancellazione sul canale con callback bloccato non fanno uscire A
nei due secondi osservati; la morte dell'app termina ancora tutti i servizi. Un secondo
canale autenticato verso la stessa incarnazione del broker consente invece lo stop A
lasciando app e B attive. Questo risolve lo stallo del callback testato, non un blocco
dell'intero broker. Garanzia pre-main e addon esterni non qualificati; gate invariato.

## Frontiera XPC — ulteriore prosecuzione del 24 settembre 2026

La richiesta di continuare autonomamente fino a una scelta progettuale ha prodotto
[nuove prove firmate](../../../docs/superpowers/verification/2026-09-24-addon-xpc-frontier.md).
Con tutti i callback di comando del broker bloccati, il secondo canale non ferma A;
uscita normale/crash root terminano i quattro servizi nelle prove dedicate. Nel cleanup
dopo stop pendente A impiega circa cinque secondi dopo root: non è garantito il tempo
rapido di ogni sequenza. Nessuna prova di sospensione dell'intero processo o pre-main.

La nuova fixture di discovery trova il provider esterno nell'app, ma dal broker
riporta lista vuota e unapproved=1. Nessun errore di target alla costruzione del punto
moderno. Browser diagnostico non ispezionato perché il Mac è bloccato; nessun consenso
modificato, nessun provider avviato. Le API libproc con audit token non sono ammesse
come pubbliche supportate. La scelta nuova, ancora pendente, riguarda il possibile
riavvio globale in emergenza, non l'accettazione di orfani. Gate ancora exit78 e
invariato; policy e ammissione produttiva restano immutate.

## Recupero globale accettato e addon esterno — 24 settembre 2026

Alla proposta precedente l'utente risponde «accettato, continua». La decisione
`native-addon-global-recovery` è ora chiusa nella policy: riavvio globale ammesso
come ultima risorsa, uscita verificata e assenza di orfani ancora obbligatorie.
Il consenso successivo riguarda soltanto l'estensione locale CascadeAddonProbeContainer.

La [nuova prova](../../../docs/superpowers/verification/2026-09-24-addon-global-recovery.md)
conferma cinque scenari dopo autenticazione: recupero diretto dopo uscita normale
e crash dell'host, con nuova catena soltanto dopo le uscite; stop del broker con
provider esterno terminato e app responsiva; uscita normale e crash del root con
broker/provider terminati. Cleanup completi, guardie estranee ai PASS. Dopo l'azione
di consenso il broker trova e avvia il provider con discovery legacy; quella moderna
continua a riportare unapproved=1. Lo stato AX del toggle non è una prova di abilitazione.

Il packaging esterno ha quindi una prova di composizione positiva, limitata alla
fixture firmata dallo stesso editore su macOS 27 beta. Restano pre-main, osservazione
indipendente dell'uscita durante avvio pendente, riuso fra host, isolamento fra addon
esterni simultanei, altri editori/OS e integrazione. La domanda tecnica aggiornata
per Apple è una bozza locale non inviata. Nessun adapter di prodotto ammesso, gate
exit78 invariato; ticket ancora aperto per requisito tecnico non qualificato.

## Approfondimento nelle fonti pubbliche — 24 settembre 2026

L'utente esclude di contattare Apple e chiede di cercare nella documentazione.
La bozza di domanda è archiviata, non inviata; una risposta privata non è un
prerequisito della prosecuzione. La [ricerca aggiornata](../../../docs/wayfinder/research/2026-09-24-extension-startup-documentation.md)
trova una risposta Apple DTS già pubblica: l'host controlla il ciclo di vita
ExtensionFoundation tramite AppExtensionProcess e invalidate, distinto dal
ciclo di vita dei servizi XPC. Le API documentano il rilascio dell'ultima connessione
e onInterruption, configurabile già nella richiesta di avvio.

Le fixture non impostano ancora quel callback. Il confronto fra notifica e uscita
kernel, con correlazione alla richiesta e controllo dei riferimenti, è una prossima
prova concreta ricavata dalle API pubbliche. Non è stato eseguito in questo
approfondimento; startup pendente e morte dell'host restano distinti. Nessuna prova
di orfani dedotta dal silenzio della documentazione, nessuna nuova ammissione.

## Verifica onInterruption eseguita — 24 settembre 2026

Su richiesta «procedi con la verifica», [cinque scenari nativi](../../../docs/superpowers/verification/2026-09-24-addon-interruption.md)
confrontano il callback configurato prima dell'initializer con eventi kernel
registrati dopo autenticazione. Uscita volontaria e crash del provider producono
entrambi uscita e callback con lo stesso nonce. Invalidazione cooperativa, rilascio
cooperativo e invalidazione con callback bloccato non producono nessuno dei due
nei sei secondi osservati, pur con proprietà forti e quattro weak nil. Cleanup
completi tramite chiusura host; nessuna guardia scaduta.

La revisione ha corretto un bordo temporale e la build finale ha ripetuto tutti
i casi. La notifica è utilizzabile come osservazione, non come stop forzato né
come copertura quando muore il suo host. Non si deduce assenza di tutti i riferimenti
interni del framework. Prova richiesta conclusa, ticket generale ancora aperto,
gate invariato, nessuna richiesta ad Apple.

## Ricambio ordinario e recupero con host vivo — 25 settembre 2026

La [verifica del broker](../../../docs/superpowers/verification/2026-09-25-addon-broker-sessions.md)
aggiunge tre PASS nativi: nuova catena nello stesso host dopo uscita verificata,
due host simultanei con processi distinti e seconda sessione preservata, due
provider cooperativi successivi nello stesso broker. Il riavvio del broker impiega
circa 10,15 s; il ricambio del solo provider circa 66 ms nella prova finale.
Le tre regressioni precedenti (stop broker, quit host, crash host) restano PASS.

25 test Python e revisione senza P1/P2; cleanup finali completi. Sono conservati
anche il primo tentativo senza comando restart e quello con startup timeout troppo
breve, quest'ultimo con seconda catena non identificata e cleanup non qualificato.
Il caricamento tardivo in un contenitore fidato è stato valutato nelle fonti:
aggiunge un formato/ABI e non risolve il pre-main del contenitore. Non viene adottato.

La parte post-handshake ora ha un percorso ordinario e un recupero concretamente
eseguibili nella fixture. C0 resta aperta e il gate invariato: non si dichiara il
sistema utilizzabile nell'app finché la garanzia di startup richiesta è senza prova.


## Startup osservato indipendentemente — 25 settembre 2026

Con la prosecuzione autonoma autorizzata sono stati eseguiti [15 scenari nativi](../../../docs/superpowers/verification/2026-09-25-addon-startup-observation.md)
PASS, più tre rifiuti di mittenti estranei: provider fermo in AppExtension.init,
in un costruttore C prima dell'entry point e nel medesimo costruttore con SIGTERM
ignorato. In ciascuna variante controllo di sblocco, stop/crash broker e quit/crash
root; il profilo resistente esce con SIGKILL, cleanup completi e osservatore vivo.
33 unit test verdi. Conservati anche il preflight AF_UNIX fallito e il crash dovuto
all'entry point errato della prima build manuale, poi corretto.

L'identità viene verificata da un audit trailer Mach, requisito con CDHash esatto,
EV_RECEIPT e challenge dopo registrazione. La fixture aggiunge soltanto il lookup
al nome diagnostico univoco; profilo separato dal prodotto, servizio assente a fine
caso. Il broker è già process-ready mentre la fixture è parcheggiata: il ritorno
dell'initializer host non prova che il provider abbia finito la propria init.

Rimane non qualificato l'intervallo creazione → primo codice diagnostico; il
costruttore segue parti di dyld/libSystem e non copre l'intero pre-main. Nessuna
nuova deroga, nessuna richiesta ad Apple, nessun launcher abilitato. Gate exit78
con hash invariato. Ticket aperto per la frontiera tecnica, senza riproporre la
scelta di policy già chiusa.

## Identità senza HELLO e laboratorio sospeso — 25 settembre 2026

La [prova esterna](../../../docs/superpowers/verification/2026-09-25-addon-external-identity.md)
verifica in due esecuzioni task-name port, token kernel, firma/CDHash/path e ricevuta
kqueue prima del primo HELLO. Negativi respinti, ricambio nello stesso job osservato,
uscite kernel e cleanup completi. Profilo provider ordinario sandbox-only e HR.
`task_for_pid` resta negato; `launchctl debug` con sola variabile diagnostica è
respinto perché richiede root. Nessun avvio sospeso eseguito.

La pista successiva è la prova in una VM macOS eliminabile: stessa firma, privilegi
di configurazione nel guest e cleanup dell'intero ambiente controllato dall'host.
Non è una soluzione produttiva già qualificata né un'eccezione sugli orfani. La VM
non è ancora preparata: circa 6 GB liberi sul volume corrente, contro 25 GB indicati
per la sola immagine pronta. Chiesta disponibilità di un volume con almeno 60 GB
di margine operativo. Gate e decisione di policy invariati.

## Preparazione con spazio ridotto — 25 settembre 2026

Dopo che l'utente ha liberato spazio e chiesto una VM piccola, la
[preparazione](../../../docs/superpowers/verification/2026-09-25-addon-small-vm.md)
seleziona una sola Sonoma vanilla 14.1, senza Xcode, 2 CPU e 4 GiB di RAM.
Il disco da 50 GB è sparse: il precedente margine di 60 GB non è trattato come
un requisito minimo dimostrato. La prova riutilizza la fixture firmata originale
e un payload di circa 32 MB.

Il primo download raggiunge il 99% ma viene fermato dalla riserva configurata di
4,5 GiB; il controller elimina soltanto lo stato incompleto del tentativo e
recupera circa 16,4 GiB. Un secondo tentativo, in corso, riserva 3 GiB durante
il download e 3,5 GiB all'avvio, conservando i dati parziali a ogni interruzione.
Nessun guest o addon sospeso è ancora stato avviato: l'ostacolo misurato è lo
spazio del laboratorio, non un risultato negativo del framework.

Dodici test del runner aggiornato passano; rifiuto reale sull'host verificato
prima di avviare qualsiasi fixture. La diagnostica opzionale di stackshot resta
separata dal payload baseline. Arresto esterno della VM, controllo di ripresa e
casi di morte rimangono da qualificare. Gate exit78 e hash invariati.


## Guest piccolo avviato e limite di discovery — 26 settembre 2026

La [verifica piccola VM](../../../docs/superpowers/verification/2026-09-25-addon-small-vm.md)
ora contiene avvii reali: 2 CPU, 4 GiB RAM, disco allocato 16,63 GiB. Il guest
misurato è Sonoma 14.3/23D56, non il 14.1 del tag. SIP era disabilitato nell'immagine:
riabilitato tramite Recovery e verificato prima delle fixture. Arresto VZ dall'host
qualificato con exit 0 e riavvio con UUID diverso; nessun fallback SIGKILL.

Corretto un errore nel preflight del runner: codesign verificava tutte le slice
contro il CDHash ARM64. La selezione esplicita ARM passa con il requisito originale;
controlli negativi respinti e 12 test puri passano. Manifest e fixture immutati.

Il primo HELLO dal broker su questo guest scade: discovery resta `idle`, log LS
`-10814` e extension point nullo. Né registrare l'app esatta né avviarla tramite
Launch Services cambia il risultato. Il consenso della fixture risulta già
abilitato nella UI di sistema. La GUI trova e avvia il provider, che respinge
correttamente quel peer perché la fixture accetta soltanto il broker.

Nessuna sospensione viene armata e nessun caso di morte sospesa è eseguito.
VM spenta, prove conservate sull'host. Il laboratorio piccolo è utilizzabile, ma
questa composizione sul guest 14.3 non supera il prerequisito di discovery.
Non è una prova di impossibilità generale di macOS 14, né una decisione di alzare
il minimo dell'app. C0 e ammissione launcher restano aperti; gate exit 78 invariato.


## Pausa VM e spazio restituito — 26 settembre 2026

L'utente richiede di fermare l'approccio VM e cercare una strada senza VM.
La macchina Sonoma viene eliminata con il comando Tart, dopo conferma stopped;
lista VM vuota, disco assente. Rimossi runtime/cache e credenziali di laboratorio.
Circa 18 GB restituiti; evidenze e fixture originale restano nel repository.
Le immagini 26/27 sono state consultate solo nei metadati, mai scaricate.
Nessuna decisione di architettura o abbassamento delle garanzie viene inferita
da questa richiesta. Le opzioni host devono prima qualificare un recupero sicuro
senza confondere figli POSIX controllati con processi EF non parentali.

Il [riesame senza VM](../../../docs/wayfinder/research/2026-09-26-addon-host-recovery-after-vm.md)
individua come candidato il recupero del job ordinario con broker ancora vivo;
nessun nuovo esperimento eseguito, nessun trasferimento del risultato a
START_SUSPENDED o alla morte del supervisore.
