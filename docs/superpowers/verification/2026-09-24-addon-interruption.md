# onInterruption e rilascio dell'estensione: verifica nativa

24 settembre 2026, macOS 27 beta 26A5425a, arm64, SDK 27.0.
Verifica autorizzata dopo la [ricerca documentale](../../wayfinder/research/2026-09-24-extension-startup-documentation.md).
Nessun contatto con Apple. **Nessuna ammissione del launcher.**

## Esito finale

`onInterruption` viene consegnata dopo l'uscita volontaria e il crash del provider,
con uscita della stessa incarnazione osservata indipendentemente dal kernel.
Non viene consegnata nei sei secondi dopo invalidazione/rilascio; in quei casi
non viene osservata neanche l'uscita del provider, incluso il caso cooperativo.

| Scenario con host ancora vivo | Uscita kernel nella finestra | onInterruption | Riferimenti visibili dopo rilascio |
| --- | --- | --- | --- |
| Provider esce volontariamente | Sì, status 0 | Sì, stesso nonce | Conservati intenzionalmente come controllo |
| Provider provoca il proprio crash | Sì, SIGKILL | Sì, stesso nonce | Conservati intenzionalmente come controllo |
| Invalidazione, provider cooperativo | Non osservata | Non osservata | Proprietà forti nil e quattro weak nil |
| Rilascio, provider cooperativo | Non osservata | Non osservata | Proprietà forti nil e quattro weak nil |
| Invalidazione, callback provider bloccato | Non osservata | Non osservata | Proprietà forti nil e quattro weak nil |

Nei controlli, la notifica è registrata circa 3 ms dopo l'osservazione kernel; non
è una garanzia di latenza. Nei tre casi senza uscita, il cleanup chiude normalmente
l'host e osserva poi la terminazione del provider con SIGKILL. Tutti i cleanup sono
completi; nessuno dei cinque provider arriva alla propria guardia SIGALRM.

Il runner termina con exit0 perché le osservazioni sono complete e attribuite.
**Non significa che siano riusciti cinque arresti selettivi.** I tre risultati
negativi hanno un limite di sei secondi: non dimostrano sopravvivenza indefinita.

## Come sono state separate le osservazioni

Il callback è configurato prima di `AppExtensionProcess(configuration:)` e cattura
soltanto un nonce di avvio, senza trattenere processo o canali. Le notifiche vengono
registrate con clock monotono sotto lock e lette dallo snapshot della fixture.
I confronti cominciano dopo startup: registrazione kqueue con ricevuta fra due
risposte autenticate della stessa incarnazione, firma e percorso esatti, UUID e
guardia verificati. La sola notifica non viene mai classificata come uscita.

La finestra comune si chiude prima di un ultimo drain kernel e dello snapshot IPC.
Un'uscita osservata nel drain finale solo dopo il cutoff rende il confronto UNKNOWN; le notifiche
successive rimangono in `lateNotifications`. Nei cinque casi finali questa lista è
vuota. Tempi e uscite del cleanup sono conservati separatamente.

Guardie post-avvio indipendenti: provider 25 s, host 35 s. Nessun kill verso PID
scoperti o scelti per nome. Crash del provider richiesto sul canale autenticato e
realizzato dal provider stesso; cleanup limitato al figlio host conservato e alla
successiva osservazione kernel del provider registrato.

## Cosa dice il controllo dei riferimenti

Nei tre casi di rilascio sono nil le proprietà dell'host per AppExtensionProcess,
canale, bootstrap, listener e delegate. Anche i riferimenti deboli ai quattro
oggetti Foundation/delegate risultano nil. Il metodo asincrono di startup è già
rientrato prima dei comandi; il callback non cattura un proprietario del processo.

Il caso `release-cooperative` invalida i canali e il listener, ma rilascia
AppExtensionProcess senza chiamare esplicitamente il suo `invalidate()`. Il caso
`invalidate-cooperative` chiama anche quest'ultimo. Nessuno dei due termina il
provider nella finestra osservata.

Questo riduce l'ipotesi di un riferimento dimenticato **nelle proprietà controllate
della fixture**. AppExtensionProcess è uno struct: la verifica non osserva tutti
i riferimenti interni di ExtensionFoundation né ne deduce l'implementazione. Non
attribuisce quindi la causa a un bug macOS, ad ARC o alla permanenza di una precisa
connessione interna.

## Revisione e validazione

La prima esecuzione è conservata in `initial-window-boundary`. Una revisione
indipendente ha trovato un P2 nel confine della finestra: lo snapshot IPC prolungava
il tempo dichiarato senza ulteriore osservazione kernel. Il runner è stato corretto
e i cinque casi rieseguiti nella build finale `probe-ifxbuc_6`; il rapporto usa solo
questi risultati finali.

La revisione finale conferma chiuso il P2 e non rileva altri problemi materiali.

Tre test del classificatore verificano separazione notifica/uscita, osservazioni
negative e rifiuto di nonce, guardie o tempi incoerenti. Quattro test Recovery e
cinque BrokerRecovery restano verdi. Typecheck Swift del profilo ordinario di host
e provider riuscito. Non è stata rieseguita la suite completa CascadeKit: i sorgenti
di prodotto non sono cambiati.

## Conseguenza pratica e limite

`onInterruption` è utile come notifica di un processo che è terminato. La prova non
lo trasforma in un comando per forzarne l'arresto, né in un osservatore che continua
a funzionare dopo la morte dell'host che lo riceve. Il [recupero tramite broker](2026-09-24-addon-global-recovery.md)
rimane il percorso con evidenza positiva di arresto lasciando l'app viva.

Nessuna copertura della fase prima dell'handshake, della cancellazione con initializer
pendente o degli altri sistemi operativi. Il gate resta invariato ed exit78. La
verifica richiesta è conclusa; la garanzia integrale del launcher resta aperta.

## Evidenza e riproduzione

- [Fixture e comandi](../../../Prototypes/AddonPlatform/Interruption/README.md).
- [Cinque risultati finali](evidence/2026-09-24-addon-interruption/final/interruption-results.json).
- [Manifest di build e hash](evidence/2026-09-24-addon-interruption/final/build.json).
- [Prima esecuzione, con limite nel confine](evidence/2026-09-24-addon-interruption/initial-window-boundary/interruption-results.json).

Ogni esecuzione conserva sorgenti nativi, runner, hash, log di build e registrazione,
identità autenticate, snapshot, eventi kernel e cleanup.
