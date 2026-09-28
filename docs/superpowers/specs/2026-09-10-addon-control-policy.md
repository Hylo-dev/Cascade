# Addon nativi — limite sul lavoro delegato accettato

Data: 10 settembre 2026. Decisione dell'utente: «Direi che ci accolliamo il rischio». Si riferisce alla scelta fra controllo del processo diretto e garanzia estesa al lavoro avviato autonomamente tramite macOS, dopo la spiegazione dei rischi nella conversazione.

## Garanzia approvata

Si prosegue con il sistema nativo su domanda, contenuti conservati dall'host, SwiftUI e servizi comuni già progettati. Cascade misura e governa le risorse dei processi che gestisce e delle operazioni che passano dai propri servizi.

È accettata l'impossibilità attuale di garantire contenimento, attribuzione dei consumi e arresto di tutto il lavoro che un addon fa avviare autonomamente a macOS fuori da quel percorso, per esempio tramite Launch Services. Quel lavoro può continuare dopo la disattivazione dell'addon o la chiusura di Cascade. Non si promette che il pulsante di disattivazione arresti anche tale lavoro esterno.

Questa modifica riguarda quel confine preciso. Non concede nuovi permessi macOS né disattiva la sandbox dei processi gestiti. Non rende accettabili un processo gestito orfano, l'uso di un'identità o di una sessione vecchia, un comando duplicato o quote aggirate attraverso i servizi di Cascade. Il lavoro delegato tramite il broker resta contabilizzato e soggetto ai grant.

Il profilo è una scelta dell'host, uguale per addon del team ed esterni. Non può essere selezionato o ampliato con una dichiarazione nel manifest. La firma serve a verificare origine e integrità; non prova il buon comportamento dell'addon. Una distribuzione iniziale selezionata è una raccomandazione per il rilascio, non un'esenzione tecnica o una nuova restrizione obbligatoria sul prodotto.

## Requisiti ancora vincolanti

- Arresto effettivo e verifica dell'uscita dei processi gestiti, inclusi chiusura/crash di Cascade e morte del supervisore.
- Identità autenticata e sessione revocata dopo cambio di eseguibile; nessuna terminazione di processi individuati soltanto per nome o PID.
- Permessi dei servizi riconvalidati, limiti applicativi, code finite e revoca; CPU/RAM osservate con intervallo e possibile superamento temporaneo dichiarati.
- Nessun codice personalizzato degli addon nel processo grafico di Cascade, nessun polling individuale e nessun processo mantenuto vivo soltanto per mostrare contenuto ordinario.
- UI remota, editori e sistemi operativi qualificati con le rispettive prove prima del supporto dichiarato.

## Conseguenze per il piano

La decisione di prodotto è risolta e non va richiesta nuovamente. Il launcher non è ancora qualificato: restano da risolvere soprattutto la sopravvivenza del worker alla morte del supervisore e l'identità dopo exec. L'accettazione di un rischio non è una nuova prova tecnica.

C0 prosegue solo su quei difetti e sulla qualificazione del nuovo profilo. Il vecchio record `launcher-admission` e i suoi risultati negativi restano invariati. Non eliminare i controesempi e non trasformare `delegatedWorkControlled=false` in true.

Per la qualificazione successiva produrre un record distinto `launcher-admission-direct-v1`, con `policyID: native-direct-control-v1`, `acceptedLimitations: [autonomousOSDelegation]` e verifiche obbligatorie vere: `managedStop`, `hostExitCleanup`, `hostCrashCleanup`, `supervisorDeathStopsWorker`, `identitySafe`, `sessionInvalidatedAfterExec`, `cpuReadable`, `footprintReadable`. Il produttore e il controllo di ammissione devono verificare scenario, policy e limitazione esatta; casi obbligatori saltati o non verificati continuano a impedire il PASS. Il comportamento del lavoro delegato resta nelle osservazioni e nei test di caratterizzazione. Questi nuovi record non sono ancora implementati né generati da questa modifica documentale.

Una volta superate tali prove si completa C1 e si prosegue con runtime, Clock e timer, migrazioni e distribuzione secondo il piano. Nessun cambiamento al linguaggio, alla modalità SwiftUI o ai criteri di verifica delle altre fasi è autorizzato implicitamente.

Riferimenti: [piano di completamento](../plans/2026-09-10-addon-runtime-completion.md), [prove originali](../verification/2026-09-10-addon-launcher-decision.md).

## Recupero globale di emergenza — decisione del 24 settembre 2026

Decisione `native-addon-global-recovery`, versione 1, stato **closed**.
Alla proposta di consentire il riavvio di tutta Cascade come ultima risorsa dopo
il fallimento del recupero selettivo, l'utente ha risposto: «accettato, continua».

È ammessa l'interruzione temporanea anche degli addon sani quando l'infrastruttura
di controllo non riesce più a fermare la catena interessata. Il recupero selettivo
resta il percorso ordinario; il riavvio globale è l'ultima risorsa, non il normale
comportamento di disattivazione. Il recupero sempre selettivo non è più un vincolo
assoluto per questo caso di emergenza.

Restano obbligatori uscita effettiva dei processi gestiti, assenza di orfani anche
prima di main, identità dell'incarnazione, sandbox/firma, nessun codice addon nella
GUI e qualificazione di addon esterni/sistemi operativi. Non è approvato avviare una
nuova istanza mentre la precedente catena è di stato ignoto, né ignorare errori di
recupero o introdurre un ciclo illimitato di riavvii.

Le [prove XPC](../verification/2026-09-24-addon-xpc-frontier.md) motivano questa scelta,
ma non qualificano ancora l'intero launcher. Il gate rimane invariato fino alle
prove richieste. Questa decisione è distinta dalla limitazione sul lavoro delegato
e non riapre l'eccezione sui processi gestiti orfani già rifiutata.

I record di ammissione precedenti restano storici. Un riavvio globale non può essere
registrato come prova di stop selettivo mentre l’host vive: la futura qualificazione
deve identificare separatamente questo percorso e le sue condizioni di recupero.
