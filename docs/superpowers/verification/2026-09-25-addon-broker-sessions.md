# Broker addon: ricambio ordinario, recupero e isolamento

25 settembre 2026. macOS 27 beta 26A5425a, arm64, SDK 27. Prosecuzione della
richiesta di rendere utilizzabile la parte nativa del sistema addon. Nessun codice
addon integrato nella GUI; launcher produttivo ancora non ammesso.

## Risultato pratico

La fixture dispone ora di due percorsi distinti provati: uscita cooperativa del
solo provider per il normale lavoro breve; uscita del broker per recuperare un
provider bloccato. In entrambi l'host rimane vivo e il nuovo provider parte soltanto
dopo l'uscita kernel del precedente. Il secondo percorso ha un costo di riavvio
molto maggiore, quindi non è adatto a essere usato alla fine di ogni richiesta.

| Caso finale | Osservazione | Esito |
| --- | --- | --- |
| Provider bloccato, arresto broker, nuova catena nello stesso host | Vecchi broker/provider usciti, entrambi gli UUID nuovi, nuova catena poi uscita, host responsivo | PASS |
| Due host contemporanei dello stesso addon | Broker e provider distinti; fermare la prima catena lascia la seconda con identità invariata e risposta autenticata | PASS |
| Due provider cooperativi successivi nello stesso broker | Due uscite status 0, UUID provider diverso, stesso broker riconfermato vivo dopo la seconda uscita | PASS |
| Regressione: stop del broker con host vivo | Provider precedentemente bloccato esce, host risponde | PASS |
| Regressione: uscita normale host | Broker e provider escono prima delle guardie | PASS |
| Regressione: crash host | Broker e provider escono prima delle guardie | PASS |

Tutti i cleanup finali sono completi. Nessun PASS deriva da una guardia SIGALRM.
Nel ricambio cooperativo, la seconda richiesta di startup riceve la prima risposta
autenticata dopo **65,6 ms**. Nel recupero completo, dopo **10,148 s**. Sono singole
osservazioni della build finale, non percentili, limiti di latenza o misure di CPU/RAM.

## Ritardo di riavvio e tentativi conservati

La prima esecuzione (`probe-td97j8xd`) dimostra che mancava il comando di ricreazione
della connessione; termina UNKNOWN, con cleanup completo della catena conosciuta.
Il comando è stato aggiunto alla fixture, scartando gli errori tardivi della vecchia
connessione dopo la sostituzione.

La seconda (`probe-hae_1plo`) attende soltanto due secondi per il nuovo handshake:
la richiesta resta pendente e la prova termina UNKNOWN. La seconda catena non è
autenticata né registrata, quindi `cleanupComplete=false` resta conservato: non è
una prova che un processo sia rimasto orfano e non è una prova della sua uscita.
Il log locale mostra la rimozione del servizio semi-attivo quando l'host termina.

Una finestra diagnostica di 15 secondi, per una sola richiesta senza reinvio, permette
poi il riavvio. La build `probe-q3h1sesl` completa i due primi scenari; la build finale
`probe-b76biql4` li ripete e aggiunge il percorso cooperativo. Il ritardo vicino a
10 secondi è coerente con la regolazione dei riavvii documentata per launchd, ma il
log acquisito non identifica esplicitamente la causa come throttling. La documentazione
generale non va assunta come una SLA del servizio XPC su questo OS.
[Manuale Apple launchd](https://github.com/apple-oss-distributions/launchd/blob/main/man/launchd.plist.5),
[gestione dei servizi XPC](https://developer.apple.com/documentation/xpc).

Le finestre di arresto rimangono di 8 s con margine di 0,5 s dalle guardie: provider
25 s, broker 35 s e root 45 s. `Output.expect` mantiene 2 s come default per tutti
i chiamanti esistenti; solo il primo handshake delle catene successive usa 15 s.

## Attribuzione e limiti

Le firme rimangono vincolate al certificato della fixture e agli identificatori
esatti. Root e broker verificano nonce, PID del peer e percorso atteso. Una seconda
risposta della stessa incarnazione segue la registrazione kqueue con ricevuta.
Le uscite causali vengono copiate prima del cleanup, che non cambia il verdetto.

Nel caso cooperativo, `finish-provider` conferma soltanto l'invio della richiesta:
è l'evento kernel status 0 ad autorizzare `release` e il nuovo startup. Nel recupero,
servono invece le uscite di entrambi i partecipanti. Il nuovo provider deve avere
un UUID diverso; cambiare solo connessione non è considerato un ricambio del processo.
Non si inviano segnali a PID scoperti per nome o percorsi: il solo eventuale kill
di cleanup riguarda il figlio root conservato dal runner.

Il caso con due host non equivale a due addon diversi nello stesso host, né a due
editori diversi. Non chiude la fase prima del primo handshake, lo startup pendente,
l'isolamento di un pool produttivo, la scena remota o la matrice macOS 14/15/26.
La ricerca su un [contenitore fidato con caricamento tardivo](../../wayfinder/research/2026-09-25-trusted-addon-container.md)
non offre una soluzione già qualificata a questi punti e non cambia il formato.

**Il risultato è un percorso di lifecycle funzionante nella fixture, non un sistema
addon attivabile in Cascade.** La policy precedente continua a richiedere assenza
di orfani anche prima di main, compreso il bootstrap fidato. Non viene riproposta
l'eccezione già rifiutata; il gate mantiene lo stesso hash e restituisce exit78.

## Verifica e riproduzione

25 test Python passati: 11 BrokerRecovery, 4 Recovery, 3 Interruption e 7 XPCLifetime.
I test aggiunti sono stati osservati fallire prima dell'implementazione. Revisione
indipendente del riavvio/isolamento e poi del nuovo percorso cooperativo: nessun
P1/P2. Le sei osservazioni native finali usano gli stessi binari e input verificati.
Non sono cambiati sorgenti dell'app principale; non è stata rieseguita CascadeKit.

- [Comandi e fixture](../../../Prototypes/AddonPlatform/BrokerRecovery/README.md).
- [Risultati dei tre nuovi casi](evidence/2026-09-25-addon-broker-sessions/final/session-results.json).
- [Tre regressioni native](evidence/2026-09-25-addon-broker-sessions/final/broker-results.json).
- [Manifest finale](evidence/2026-09-25-addon-broker-sessions/final/build.json).
- [Primo tentativo](evidence/2026-09-25-addon-broker-sessions/missing-reconnect/session-results.json).
- [Finestra troppo breve](evidence/2026-09-25-addon-broker-sessions/startup-window-too-short/session-results.json).
- [Prima verifica positiva di riavvio/isolamento](evidence/2026-09-25-addon-broker-sessions/restart-and-isolation/session-results.json).

Ogni archivio conserva sorgenti, runner con hash verificati, manifest, log, eventi
e cleanup. Il riavvio finale di Cascade è registrato separatamente in `restart.json`.
