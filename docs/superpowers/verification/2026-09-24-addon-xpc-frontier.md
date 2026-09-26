# XPC: comandi bloccati e addon esterni

**Aggiornamento successivo:** l’utente ha accettato il riavvio globale come ultima risorsa.
La [decisione registrata](../specs/2026-09-10-addon-control-policy.md#recupero-globale-di-emergenza--decisione-del-24-settembre-2026)
supera i riferimenti a scelta pendente nel rapporto storico qui sotto; le prove
e i loro limiti restano invariati.

24 settembre 2026. **Launcher ancora disabilitato.** Prosecuzione autorizzata con
fixture isolate; nessuna modifica al prodotto o alla policy. La scelta sul riavvio
globale come ultima risorsa è pendente e non riapre l'eccezione sugli orfani già rifiutata.

## Blocco dei comandi

`hold-all` nella fixture XPCBroker imposta atomicamente il blocco di ogni successivo
callback di comando A, anche sul secondo canale, e trattiene il callback iniziale.
Il worker conferma il proprio blocco; la risposta autenticata passa da una coda
indipendente. Per lo stop, il secondo canale è autenticato sulla stessa incarnazione
prima del blocco. Listener, risposte e segnali restano operativi: **non è una
sospensione dell'intero processo**, non viene inviato SIGSTOP, le guardie sono attive.

macOS 27 beta 26A5425a, SDK 27.0, arm64, target compilato 14.0. Root Hardened Runtime;
broker/worker Hardened Runtime + App Sandbox, firme fissate come nelle prove precedenti.
Build finale: `CascadeXPCBrokerProbe/nested-boa0k31m` in DerivedData.

| Scenario, finestra 2 s | Esito | Evidenza |
| --- | --- | --- |
| Stop A sul secondo canale, root e B vivi | FAIL | Nessun exit A; root e B reattivi |
| Uscita normale root | PASS | Quattro servizi SIGKILL, eventi entro 1,95 ms |
| Self-SIGKILL root | PASS | Quattro servizi SIGKILL, eventi entro 2,03 ms |

Sono tempi di ricezione degli eventi kernel dal trigger, non latenze garantite.
Il classificatore ammette status 9 o 15 per i servizi; i risultati sono tutti 9.
Status root richiesti 0/-9. Guardia e crash accidentali non producono PASS.

Durante il **cleanup del FAIL**, root esce normalmente: B termina subito, A circa
**5 secondi dopo il root**, prima della guardia. Osservato in entrambi i cicli.
Il caso ha un secondo canale e uno stop pendente; non è stata isolata la causa della
differenza rispetto a host-normal. Non si estende il PASS rapido a ogni sequenza né
si usa il cleanup per promuovere il FAIL. Tutti i partecipanti tracciati risultano
infine usciti. Nessun segnale a PID o gruppi individuati per scansione.

Runner finale **exit 1**, coerente con un FAIL valido. Conservati
[ciclo iniziale](evidence/2026-09-24-xpc-frontier/frozen-initial/results.json) e
[finale](evidence/2026-09-24-xpc-frontier/frozen-final/results.json), log, manifest e
sorgenti corrispondenti. Il secondo aggiunge host-normal dopo il ritardo nel cleanup.

## Discovery dell'addon esterno

Nuova fixture [XPCDiscovery](../../../Prototypes/AddonPlatform/XPCDiscovery/README.md):
app con ID/punto della P0 e broker sandboxed con ID distinto. Ricompilato e aperto
il contenitore vuoto della fixture P0 per registrarne i metadati. **Nessun provider
avviato**, nessuna costruzione di AppExtensionProcess. Campionamento 2 s per entrambe
le API. Firma controllata su entrambe le connessioni; risposta con nonce, bundle ID
e PID verificato rispetto alla connessione Foundation. Nessun grant o dato utente.

| Chiamante | Legacy | Monitor moderno |
| --- | --- | --- |
| App | Provider atteso trovato | Stesso provider, disabled 0, unapproved 0 |
| Broker | Vuoto | Vuoto, disabled 0, unapproved 1 |

[Risultato autenticato](evidence/2026-09-24-xpc-frontier/discovery-final/stdout.jsonl).
**Punto e monitor non rifiutano il target XPC** nella prova. `unapproved=1` è un
conteggio, non l'identità autenticata di quell'elemento: suggerisce un ostacolo di
approvazione nel contesto broker, senza isolarne la causa. Non dimostra impossibilità,
diritto di lancio o proprietà della durata. Exit 0 del runner significa risposta
autenticata, non qualificazione; il controllo positivo dell'app è verificato qui.

[Primo tentativo](evidence/2026-09-24-xpc-frontier/discovery-initial/) inconcludente
per difetto fixture: setter di firma su NSXPCListener.service, vietato dall'header
Foundation. Errore 4097 e SIGSEGV nel setter, log/crash ridotto conservati. Correzione:
requisito sulla NSXPCConnection ricevuta prima di export/resume, senza rimuovere
l'autenticazione. La verifica preliminare non aveva individuato questo errore.

La [variante browser](evidence/2026-09-24-xpc-frontier/discovery-browser/) costruisce
EXAppExtensionBrowserViewController dal broker, lo mantiene 60 s dopo la risposta,
guardia autonoma 90 s. Stessi conteggi. **Verifica visiva bloccata dal Mac sulla
schermata di blocco**: nessuna finestra acquisita, nessun toggle o consenso cambiato.
Creare la view senza errore non dimostra visibilità o supporto del percorso UI.

## Ricerche e scelta pendente

[Audit token](../../wayfinder/research/2026-09-24-audit-token-termination.md): il kernel
verifica PID/versione, ma libproc non soddisfa il requisito di API pubblica supportata
e la presenza nell'SDK non prova macOS 14.0. Nessuna API privata introdotta.
[Fonte DTS](https://developer.apple.com/forums/thread/837541).

[Composizione broker/ExtensionFoundation](../../wayfinder/research/2026-09-24-extension-broker-composition.md):
nessun parametro pubblico individuato per far approvare alla GUI un'estensione a
nome del broker. Browser e Impostazioni Sistema richiedono ancora verifica a desktop
sbloccato; non si modificano database interni. La [risposta DTS sull'hosting annidato](https://developer.apple.com/forums/thread/846017)
riguarda un'estensione che ospita altre estensioni, non questo preciso broker XPC.

La domanda di prodotto proposta all'utente è se consentire **il riavvio di tutta
Cascade come ultima risorsa**, interrompendo temporaneamente anche gli altri addon,
oppure richiedere sempre recupero selettivo. Il secondo canale risolve uno stallo
localizzato, non il caso appena misurato. Per la prima strada servono prima prova
dell'uscita dell'intera catena, tempi e ripristino; lanciare una seconda app non basta.
Per la seconda serve un'altra primitiva pubblica o architettura dimostrata.

Entrambe conservano nessun processo gestito orfano, sandbox/firma, assenza di codice
addon nella GUI e minimo macOS. Un sì al riavvio **non abilita da solo il launcher**.
Restano: consenso e avvio esterno autenticato, proprietà della durata, pre-main,
incarnazione esatta, altro editore, macOS 14/15/26, SwiftUI remoto. Domanda ad Apple
preparata nella ricerca, **non inviata**.

## Verifiche

- Build firmate riuscite: C XPC, Swift discovery e contenitore P0.
- 7 test XPCLifetime + 11 XPCBroker passati; nuove aspettative osservate fallire prima
  dell'implementazione. Nessuna nuova suite prodotto rivendicata.
- Gate eseguito: exit 78, senza avvio C0d; SHA-256 invariato
  `687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.
- Solo prototipi/evidenze cambiati: nessuna nuova build Cascade necessaria.
- Riavvio ordinario finale e percorso app registrati in
  [restart.json](evidence/2026-09-24-xpc-frontier/restart.json).
