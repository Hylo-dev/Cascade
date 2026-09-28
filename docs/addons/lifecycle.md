# Ciclo di vita di contenuti, lavori e azioni

Il runtime nativo completo non è ancora abilitato. Questo documento descrive le componenti già implementate e il loro confine; il collegamento a processi, trasporto autenticato, broker dei servizi e renderer rimane nel [piano di completamento](../superpowers/plans/2026-09-10-addon-runtime-completion.md).

## Contenuto e processo hanno durate diverse

`PublicationStore` conserva i valori pubblicati, le revisioni e le date di scadenza. La normale chiusura della connessione del provider non cancella il contenuto né la storia delle revisioni; rilascia soltanto la sua autorità e la relativa riserva di memoria. Disattivazione e revoca rimuovono anche le pubblicazioni future. Il [confine delle sessioni](sessions.md) lega l’ammissione a una connessione canonica dell’host: controlla generazione, sequenza, ID assegnati, revisioni e schemi concordati prima di modificare lo stato. La verifica nativa del processo deve ancora essere collegata; il solo ID contenuto nel messaggio non dimostra chi lo ha inviato.

## Code finite, nessun timer per addon

`AddonScheduler` gestisce al massimo un lavoro in esecuzione per addon e due globalmente. Ogni addon può avere quattro comandi in attesa e sedici aggiornamenti distinti in attesa, entro il budget di memoria del componente. Cento richieste di aggiornamento della stessa pubblicazione in attesa occupano un solo posto; un comando non viene scartato per fare spazio a uno nuovo.

Le azioni precedono normalmente gli aggiornamenti. Dopo cinque secondi un aggiornamento in attesa acquisisce priorità per evitare un rinvio indefinito; ogni lavoro resta soggetto alla propria scadenza, limitata al massimo a trenta secondi dalla sua ammissione nello scheduler. Questi valori appartengono alla policy host, uguale per tutte le origini.

Un lavoro scaduto prima dell'avvio viene restituito al runtime perché comunichi il rifiuto. Se era già in esecuzione, lo scheduler richiede l'arresto e mantiene il posto occupato finché il runtime conferma la fine effettiva del lavoro o del processo. Una richiesta di arresto non equivale a un arresto osservato.

`DeadlineQueue` raccoglie fino a 1.024 scadenze sostituibili per ID. Distingue date civili e durate trascorse; elimina una scadenza una sola volta e non genera tick arretrati dopo lo stop del Mac. Non installa timer: espone al futuro runtime la prossima attesa, da gestire con un unico risveglio comune. La ricerca del minimo è una scansione limitata, senza array temporanei, sui soli eventi del runtime; non appartiene al rendering.

## Un risultato perso non autorizza a ripetere il comando

`ActionJournal` distingue comando in attesa, inviato, ricevuto dal provider e concluso. La conferma di ricezione non è una conferma di esecuzione. Prima di ammettere il comando riserva spazio anche per un risultato da 64 KiB, così un journal pieno non impedisce di conservare l'esito di un effetto già avvenuto.

La stessa richiesta restituisce lo stato noto senza creare altro lavoro o prolungare la conservazione. Riutilizzare il suo ID cambiando input, pubblicazione o altri campi viene rifiutato. La cronologia conserva fino a 128 richieste per addon per dieci minuti dall'ammissione, entro il budget globale del componente. A quota piena rifiuta nuove richieste senza eliminare gli esiti già noti.

Dopo invio, un timeout, una disconnessione o una disattivazione possono lasciare l'esito sconosciuto: l'effetto esterno potrebbe essere già avvenuto. Il journal non ritenta automaticamente. Una risposta tardiva, proveniente da un'altra generazione o da un altro addon, non può sostituire l'esito terminale. Un comando ancora non inviato riceve invece un rifiuto definito.

La data civile della richiesta viene convertita in una scadenza monotona all'ammissione nel journal. Lo scheduler conserva quella scadenza anche se l'utente cambia l'ora del Mac. Le durate monotone sono valide soltanto per l'istanza corrente del runtime e non vengono serializzate per il riavvio successivo.

## Autorizzazione prima della consegna

`ActionAuthorizer` controlla l’addon verificato, la feature assegnata dall’host e la risoluzione corrente delle dipendenze. L’azione deve comparire nel contenuto attualmente utilizzabile, con lo stesso input della richiesta; una voce futura della timeline non conferisce ancora l’autorizzazione. Contenuto scaduto, obsoleto o oscurato per privacy non autorizza nuovi comandi. La normale assenza del provider non impedisce un’azione su contenuto ancora valido.

`ActionDispatcher` compone journal e scheduler entro un unico limite locale di 8 MiB, includendo i metadati e lo spazio per gli esiti. Riserva un lavoro e produce un ticket monouso; il consumo del ticket ricontrolla lo stato corrente prima di registrare l’invio. Due azioni possono attendere sulla stessa revisione, ma prima della seconda consegna va verificata nuovamente la revisione. Un vecchio ticket o un esito di un’altra generazione non può consumare il lavoro nuovo.

Il coordinatore di produzione dovrà possedere questi valori e lo stato autorevole, serializzando aggiornamenti, revoche e consegna al trasporto. Questa componente non lancia processi e il proprio limite locale non sostituisce ancora la quota comune di tutto il runtime. Il [contratto delle azioni](actions.md) precisa recupero degli esiti, scadenze e conferma della fine del lavoro.

## Guasti e riavvii limitati

`AddonHealthStore` conserva la storia della versione verificata. Tre violazioni moderate entro cinque minuti mettono quella versione in quarantena; una violazione grave richiede l'arresto immediato. Un crash con domanda ancora presente consente al massimo tre tentativi dopo 1, 5 e 30 secondi; il quarto crash richiesto mette la versione in quarantena.

Ogni tentativo ha un ticket consumabile una volta sola, legato alla sessione fallita. Il runtime deve ricontrollare domanda e abilitazione quando arriva la scadenza. Disattivazione, revoca o sostituzione della sessione invalidano i ticket precedenti. Registrare di nuovo la stessa versione non azzera la storia; il ripristino è un'operazione esplicita dell'host. La storia sopravvive ai riavvii del provider se l'host conserva lo store, ma non è ancora persistita fra riavvii di Cascade.

Queste sono decisioni di stato: l'osservazione dei consumi e l'arresto reale devono ancora essere collegati al launcher qualificato.

## Confini ancora da collegare

Le componenti sono valori di stato posseduti dall'host. Non eseguono codice addon nel processo di Cascade e non costituiscono da sole autenticazione o un launcher. Il [checkpoint store](storage.md) aggiunge persistenza per valori opachi e migrazioni preparate; il ripristino automatico delle pubblicazioni resta da collegare. Il [broker dei servizi](services.md) implementa già permessi, interessi e decisioni limitate collegati a ResourceGovernor; il coordinatore deve ancora collegare queste decisioni al trasporto autenticato e alle sorgenti reali. Il coordinatore deve collegare journal, code e quote comuni senza sommare budget indipendenti come se fossero un unico limite; i costruttori consentono già di ridurre i budget locali.

Restano da collegare al coordinatore l’arbitraggio delle azioni già implementato, la gestione del contenuto obsoleto e le prove di pubblicazione con provider realmente assente. La [qualificazione nativa](../superpowers/verification/2026-09-10-addon-direct-v1.md) contiene una prova positiva isolata di identità dopo cambio eseguibile, ma il launcher integrato resta non ammesso per il controllo alla morte del supervisore.
