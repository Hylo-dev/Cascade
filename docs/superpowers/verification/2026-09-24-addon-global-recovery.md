# Estensione esterna: recupero globale e stop tramite broker

24 settembre 2026. macOS 27 beta, build 26A5425a, arm64, SDK 27.0.
Esperimenti isolati, successivi all'approvazione del recupero globale come ultima
risorsa. **Launcher non ammesso; gate invariato.**

## Risultato

È stata osservata la composizione app → broker XPC → estensione esterna: l'uscita
del broker termina il provider con callback bloccato lasciando l'app responsiva.
Uscita normale e crash dell'app terminano entrambi. La prova diretta app → estensione
conferma inoltre una nuova partenza dopo l'uscita verificata della vecchia catena.
Questi risultati riguardano processi già avviati e autenticati.

| Fixture e scenario | Esito | Uscita provider osservata dal trigger | Altra osservazione |
| --- | --- | --- | --- |
| App diretta, uscita normale | PASS | ~10,52 ms | Nuovo host/provider dopo entrambe le uscite |
| App diretta, crash SIGKILL | PASS | ~9,78 ms | Nuovo host/provider dopo entrambe le uscite |
| Broker, uscita normale | PASS | ~6,25 ms | Root ancora viva e responsiva |
| Root del broker, uscita normale | PASS | ~11,31 ms | Broker terminato ~9,78 ms |
| Root del broker, crash SIGKILL | PASS | ~14,42 ms | Broker terminato ~11,25 ms |

Sono singole osservazioni, non limiti temporali garantiti. Le finestre sono di otto
secondi. In tutti i casi il provider rimaneva vivo per due secondi dopo invalidazione
con l'host ancora responsivo. Tutte le uscite misurate e i cleanup sono confermati;
nessun PASS deriva dalla guardia SIGALRM. Le nuove catene nella prova diretta vengono
a loro volta autenticate, confermate e terminate prima della propria guardia.

## Consenso e discovery

L'utente ha autorizzato espressamente soltanto l'estensione locale di prova
«CascadeAddonProbeContainer». L'azione nel pannello di Sistema è stata eseguita dopo
quel consenso. La lettura AX del toggle continuava a riportare off; non viene usata
come prova di un cambio di stato. Dopo l'azione, la prova di discovery registra:

- App: provider presente sia nella discovery legacy sia in quella moderna.
- Broker: provider presente nella legacy, moderna ancora vuota con `unapproved=1`.
- La successiva prova nativa avvia e autentica effettivamente il provider dal broker
  tramite l'API legacy. La discrepanza con la discovery moderna resta aperta.

Il servizio `.xpc` non è un'applicazione apribile da LaunchServices. Il tentativo
precedente di aprirlo come app è stato corretto; il contenitore `.app` di prova e
Cascade sono entità distinte. Nessun consenso generale per altre estensioni è stato
richiesto o modificato.

## Attribuzione e boundedness

Host, broker e provider sono firmati con la stessa identità di sviluppo fissata
dalla fixture, hardened runtime; broker/provider hanno soltanto app-sandbox. I
requisiti XPC controllano identificatore e certificato leaf. Il profilo
`BROKER_PROVIDER` ammette il preciso broker al posto dell'host diretto.

Il root autentica broker, nonce e percorso; il broker autentica il provider e la
sua risposta. Il provider attesta PID, UUID e percorso, correlati alla connessione
autenticata. La registrazione kqueue con ricevuta avviene tra due risposte della
stessa incarnazione. L'ultima risposta precede il callback trattenuto. L'uscita viene
osservata via NOTE_EXIT/NOTE_EXITSTATUS, non inferita dall'invalidazione XPC.

Guardie native separate: provider 25 s, broker 35 s, root del broker 45 s. La prova
diretta usa root 35 s. SIGALRM viene ripristinato e sbloccato esplicitamente;
il caso dedicato conferma l'uscita -14 di un figlio con SIGALRM ereditato bloccato.
La guardia comincia quando viene eseguito il codice della fixture, quindi non
copre la creazione né uno stallo precedente. Il cleanup conserva separatamente le
misure; un'eventuale terminazione forzata riguarda solo il figlio diretto conservato,
mai un processo scelto per nome o un PID scoperto successivamente.

## Tentativi incompleti conservati

La prima prova diretta ha incontrato più copie registrate dello stesso provider:
UNKNOWN, prima dell'avvio. Sono state rimosse dal registro solo copie della fixture
con firma e identità verificate, mantenendo i file. Il percorso atteso viene poi
verificato nell'handshake; identità ambigue restano un errore.

Il primo runner broker si è fermato prima di avviare la catena perché LaunchServices
ritornava -10814 rimuovendo una vecchia copia già deregistrata. Il runner finale
registra quell'esito e procede alla discovery stretta; nessun risultato di quel
tentativo viene contato come prova di lifetime.

Una revisione indipendente ha individuato nella prima implementazione della guardia
il caso di SIGALRM ereditato bloccato. Correzione e prova dedicata precedono le prove
dirette finali. La revisione del broker finale non ha rilevato P1/P2 nella fixture
o nell'attribuzione dei risultati.

## Cosa resta da qualificare

- Creazione → startup/handshake, compresa morte dell'host con avvio ancora pendente.
- Osservazione indipendente dell'uscita della specifica incarnazione in quella fase.
- Riuso del provider fra client, isolamento di più addon esterni simultanei e
  ripartenza selettiva del broker con la stessa app viva.
- Broker completamente bloccato: le precedenti prove C riguardano callback bloccati,
  non la sospensione dell'intero processo né questa composizione ExtensionFoundation.
- Un editore distinto, macOS 14 e gli altri sistemi supportati, UI remota, ripristino
  dello stato e integrazione nel runtime reale.

La [ricerca sulle API pubbliche](../../wayfinder/research/2026-09-24-extension-host-global-recovery.md)
non trova ancora un contratto sufficiente per la garanzia pre-main. Non è una prova
di impossibilità della piattaforma. Un marker in un initializer esplorerebbe una
fase successiva al primo codice eseguito e non chiuderebbe il requisito.

La [policy approvata](../specs/2026-09-10-addon-control-policy.md#recupero-globale-di-emergenza--decisione-del-24-settembre-2026)
consente il recupero globale ma non orfani né riavvio con vecchia catena ignota.
Non serve riproporre questa decisione. Il successivo prerequisito tecnico è un
contratto/API pubblico verificabile per lifetime e osservazione durante lo startup;
era stata preparata una [domanda aggiornata per Apple](../../wayfinder/research/2026-09-24-extension-lifetime-apple-question.md), mai inviata. L'utente ha poi escluso
questa strada: la bozza è archiviata e si prosegue nella
[documentazione pubblica](../../wayfinder/research/2026-09-24-extension-startup-documentation.md),
senza attendere o richiedere una risposta privata di Apple.

## Riproduzione ed evidenza

- [Fixture diretta](../../../Prototypes/AddonPlatform/Recovery/README.md).
- [Fixture con broker](../../../Prototypes/AddonPlatform/BrokerRecovery/README.md).
- [Risultati diretti finali](evidence/2026-09-24-addon-global-recovery/final/results.json),
  [guard check](evidence/2026-09-24-addon-global-recovery/final/guard-check.json).
- [Tentativo diretto ambiguo](evidence/2026-09-24-addon-global-recovery/initial-ambiguous/results.json).
- [Discovery dopo consenso](evidence/2026-09-24-addon-global-recovery/discovery-after-consent/stdout.jsonl).
- [Risultati broker](evidence/2026-09-24-addon-global-recovery/broker-external/broker-results.json).

Ogni gruppo conserva manifest con hash, build log, sorgenti copiati e runner della
propria esecuzione. Nove test Python mirati verificano i classificatori (quattro
diretti, cinque broker); non sono una prova del comportamento del sistema operativo.
Anche il typecheck di host e provider nel profilo Swift predefinito, senza i flag
della prova Recovery, passa dopo lo spostamento degli helper nel file condiviso.
Il gate restituisce ancora exit78 con SHA-256
`687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.
I sorgenti di prodotto Cascade/CascadeKit non sono stati modificati in questo
intervento; nessuna nuova percentuale di completamento viene dedotta dai PASS.
