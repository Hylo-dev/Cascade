# Intermediario XPC dedicato — 24 settembre 2026

**La catena XPC annidata funziona nei quattro scenari misurati. Il launcher resta non ammesso.**
L'utente ha autorizzato «esplora e fai test per questa strada», riferendosi a un intermediario
dedicato da terminare per fermare l'addon mentre Cascade resta aperta.

## Disegno provato

Una piccola app di prova ospita due servizi, BrokerA e BrokerB. Ciascun broker include
nel proprio `Contents/XPCServices` il rispettivo worker ed è l'unico client di quel worker.
Anche il broker è un servizio XPC Application, anziché un processo avviato direttamente
con spawn. La discovery annidata ha funzionato. I cinque binari hanno firma Apple
Development e Hardened Runtime; i quattro servizi hanno soltanto App Sandbox.

L'app simula Cascade senza modificarla. A e B hanno identificatori di bundle distinti
fissati in compilazione; ogni scenario crea processi nuovi. Il worker trattiene il callback
in `pause()`, mentre il broker continua a gestire i comandi di controllo.

Lo stop è una richiesta al broker fidato di eseguire `_exit(0)`. La variante di morte
forzata chiede al broker di segnalare se stesso con SIGKILL. L'osservatore non segnala PID
di servizi, non termina gruppi e non dipende da un attach di tracing.

## Esito nativo

Build finale `nested-pu8j8qxj`, macOS 27.0 (26A5425a), arm64, SDK 27.0, clang 21.0.0.
Un ciclo completo finale, finestra di osservazione di due secondi per caso:

| Scenario | Risultato kernel | Isolamento | Esito |
| --- | --- | --- | --- |
| Stop A | Broker A esce 0; worker A esce SIGKILL, osservato circa 1,40 ms dal trigger | App viva, stessa catena B risponde dopo la finestra | PASS |
| SIGKILL del broker A | Broker A e worker A escono SIGKILL; worker osservato circa 1,40 ms dal trigger | App viva, stessa catena B risponde dopo la finestra | PASS |
| Uscita ordinaria dell'app | Entrambi i broker ed entrambi i worker escono SIGKILL, osservati entro circa 1,95 ms | App esce 0 | PASS |
| SIGKILL dell'app | Entrambi i broker ed entrambi i worker escono SIGKILL, osservati entro circa 2,31 ms | App esce SIGKILL | PASS |

I tempi indicano la ricezione dell'evento kernel rispetto al trigger, non la latenza
interna precisa né una garanzia temporale di macOS. Nei casi di morte dell'app entrambi
i worker trattengono il callback. Nei casi A, B rimane responsivo: non è soltanto un PID
ancora presente, perché il ping conferma la stessa incarnazione di broker e worker.

La pulizia successiva termina il client di prova e registra separatamente l'uscita
della catena B. Tutti i processi noti sono usciti; i quattro servizi sono stati
registrati e osservati in ciascun caso. Nessun PASS dipende dalla guardia SIGALRM.

## Come vengono evitate conclusioni sbagliate

I messaggi del broker sono verificati con requisito di firma e `SecCodeCreateWithXPCMessage`.
Il broker verifica allo stesso modo il worker prima di riportarne l'identità: il root
si fida del broker fisso, non attribuisce al messaggio inoltrato l'identità diretta del worker.
Sono scambiati soltanto dati sintetici. Questo non qualifica l'autenticazione o la
protezione dei messaggi in uscita del futuro protocollo addon.

L'osservatore usa `EVFILT_PROC`, ricevuta della registrazione, `NOTE_EXIT` e
`NOTE_EXITSTATUS`. Dopo la registrazione, una seconda risposta conferma la stessa
incarnazione. Il classificatore rifiuta uscite antecedenti al trigger, fuori finestra,
da errore della fixture, da crash imprevisto o dalla guardia. Per il crash del broker
richiede precisamente SIGKILL. Richiede entrambi i processi A usciti e B ancora
responsivo, oppure tutti e quattro usciti quando termina l'app. La pulizia non può
convertire un risultato negativo in positivo.

Sei test del nuovo classificatore passano; i sette del verificatore precedente riusato
passano. Revisione indipendente effettuata prima del test nativo e sulla correzione
successiva della simulazione di crash. Le correzioni del verificatore includono la
tolleranza dell'invalidazione prevista di A mentre si aspetta il ping B e il rifiuto
di SIGTERM come surrogato della specifica simulazione SIGKILL del broker.

## Primo ciclo e difetto della simulazione di crash

Il primo ciclo (`nested-0bc3kcmz`) ha dato tre PASS e broker-crash FAIL: il broker è
uscito con codice 84, non con SIGKILL. Il worker è comunque uscito SIGKILL, ma il
verificatore non ha promosso il caso. [Risultati originali](evidence/2026-09-24-xpc-broker/initial/results.json)
e [sorgente precedente](evidence/2026-09-24-xpc-broker/initial/Probe.c) sono conservati.

L'istruzione `raise(SIGKILL); _exit(84)` sul thread dispatch introduce una gara:
la richiesta di segnale può tornare prima della terminazione e il ripiego può anticiparla.
Un controllo isolato ha osservato `raise` tornare 0 prima della morte con SIGKILL
([diagnostica iniziale](evidence/2026-09-24-xpc-broker/signal-check.json)). L'ipotesi iniziale
che il segnale fosse semplicemente rifiutato non è stata confermata: l'assert di quella
diagnostica è fallito. Il valore errno dopo una chiamata riuscita non è un errore valido.

Un secondo [riproduttore](../../../Prototypes/AddonPlatform/XPCBroker/SignalCheck.c) confronta
uscita immediata e attesa del segnale: tre uscite con codice 84 contro tre SIGKILL
([dati](evidence/2026-09-24-xpc-broker/signal-race.json)). Il solo codice 84 non distingue
il fallimento di `raise` dalla successiva `_exit`; i due controlli insieme motivano
la correzione, senza attribuire al primo una prova che non contiene.
La fixture ora verifica il ritorno di `raise` e, in caso di successo, aspetta il segnale
senza anticiparlo con `_exit`. La guardia autonoma resta attiva. Il successivo ciclo
firmato conferma SIGKILL effettivo nel caso broker-crash; tutti e quattro i casi passano.

## Cosa dimostra e cosa rimane aperto

Il nuovo risultato supera il limite locale della [cancellazione della connessione](2026-09-24-addon-xpc-lifetime.md):
far uscire un intermediario XPC fidato ha terminato il suo worker bloccato lasciando
attiva l'app e l'altra catena. Quando l'app muore, anche gli intermediari escono nelle
esecuzioni osservate. Questa è una pista concreta da qualificare, non un launcher pronto.

Restano da dimostrare:

1. Copertura dell'avvio prima di main e prima del primo messaggio. Registrazione e
   guardie di questa fixture iniziano dopo main; non provano quella finestra.
2. Supporto pubblico del packaging annidato e della relazione di durata su tutte le
   versioni macOS supportate. Il funzionamento su una build di macOS non basta.
3. Installazione e isolamento di addon esterni e firmati da altri editori. Qui tutti
   i bundle e i due identificatori sono fissi e firmati dalla stessa identità.
4. Stop se è il broker fidato a diventare non responsivo: lo stop provato richiede che
   il broker legga il comando. Il worker bloccato non lo impedisce in questa fixture.
5. Ammissione, limiti, revoca e trasporto coerenti con il contratto del runtime prodotto.

La prossima indagine utile è qualificare il ciclo di vita del broker e del servizio
annidato, compreso l'avvio, insieme al percorso supportato per i pacchetti esterni.
Non serve ripetere la sola cancellazione del canale già risultata insufficiente.

## Fonti e riproducibilità

La [guida Apple XPC](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)
descrive servizi gestiti da launchd e collocati nel bundle dell'app. L'header/manuale
pubblico `xpcservice.plist(5)` dell'SDK descrive namespace dell'app, servizi inclusi e
servizi nei framework. Nessuna di queste formulazioni è stata usata come prova che
tutto il disegno annidato per addon esterni sia supportato.
Le [regole Apple di firma](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)
prevedono firma dal componente più interno verso l'app e posizioni standard per il codice.
La verifica strict/deep della fixture è riuscita.

La [implementazione Apple di raise](https://github.com/apple-oss-distributions/Libc/blob/main/gen/raise.c)
usa `pthread_kill` con fallback a `kill(getpid(), sig)` su ENOTSUP. I manuali pubblici
`raise(3)` e `pthread_kill(2)` dell'SDK documentano invio al thread e il possibile ENOTSUP
per thread non creati con pthread_create; la diagnosi qui usa anche i risultati locali.

- [Fixture e comandi](../../../Prototypes/AddonPlatform/XPCBroker/README.md).
- [Risultati finali](evidence/2026-09-24-xpc-broker/final/results.json).
- [Manifest: comandi, hash e firma](evidence/2026-09-24-xpc-broker/final/build.json).
- [Log della build finale](evidence/2026-09-24-xpc-broker/final/build.log).

La variante siblings preparata nel builder non è stata eseguita, perché la discovery
annidata ha funzionato. Nessun codice prodotto, entitlement di Cascade o adapter è
cambiato. Nessuna suite prodotto rieseguita per questo esperimento indipendente.
Gate C0d invariato: SHA-256 `687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.

Cascade è stata chiusa e riaperta ordinariamente: PID precedente 26301, nuovo PID
28002, percorso dell'eseguibile verificato nella build esistente CascadeDevelopment
raggiunta da `/Applications/Cascade.app`. Nessuna build dell'app necessaria per questo
prototipo separato. [Evidenza del riavvio](evidence/2026-09-24-xpc-broker/cascade-restart.json).
