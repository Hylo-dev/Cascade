# Launcher e trasporto autenticato — prosecuzione del 24 settembre 2026

**Esito: punto 1 ancora bloccato, nessun launcher produttivo abilitato.** La richiesta di procedere riprende il lavoro tecnico; conserva la decisione di non accettare processi gestiti orfani. Questo rapporto registra nuove verifiche delle API e del raccordo al runtime. Non è una specifica approvata di un nuovo launcher né una prova nativa.

**Aggiornamento successivo:** l'utente ha poi autorizzato una [prova nativa XPC separata](../../superpowers/verification/2026-09-24-addon-xpc-lifetime.md), ora conclusa. L'uscita del client termina il servizio bloccato nelle esecuzioni osservate; la cancellazione della connessione con client vivo non lo termina nei due secondi misurati. Il testo sotto conserva il contesto della ricerca precedente. Il launcher resta non qualificato.

## Due problemi distinti

1. Possedere la durata del processo dalla creazione, anche se il supervisore muore prima di `main` o dell'aggancio del tracing; fermare il lavoro non cooperativo e osservare l'uscita del processo esatto.
2. Autenticare il mittente dei messaggi e legare i messaggi all'incarnazione, alla versione e ai grant ammessi dal runtime, con limiti e revoca effettivi.

Un risultato positivo sul secondo problema non conclude il primo. La [decisione vigente](../../../.scratch/cascade-product/issues/22-managed-process-exit-proof.md) non va riaperta per ripetere una richiesta di eccezione già rifiutata.

## Risultati nuovi e loro limiti

### Spawn sospeso

L'[esame distinto di spawn, exec e fork](2026-09-24-spawn-managed-lifetime.md) confronta SDK pubblico e sorgenti XNU fissati a una revisione. `POSIX_SPAWN_START_SUSPENDED` non costituisce un vincolo di uscita alla morte del genitore. `SETEXEC` non aggiunge quel vincolo e un modello basato sull'eredità del tracing attraverso fork non è qualificato. Non si introduce una prova che lasci intenzionalmente un processo sospeso contando sul solo genitore per ripulirlo.

### Servizio XPC legato al client: pista distinta da SMAppService

La [panoramica Apple di XPC](https://developer.apple.com/documentation/xpc) descrive il servizio XPC di applicazione come legato alla durata del client, con uscita del servizio alla morte del client. Questo è un indizio positivo distinto dalla persistenza di LaunchAgent/LaunchDaemon registrati tramite ServiceManagement. Il precedente esito negativo su `launchd`/SMAppService non prova che ogni servizio XPC abbia lo stesso limite.

Restano da stabilire la copertura dell'avvio prima del primo messaggio, l'arresto esplicito mentre Cascade resta aperta e l'osservazione autorevole dell'uscita. La cancellazione della connessione è asincrona e non interrompe un handler già in corso: non è un'API di terminazione del processo. Fonte locale: `xpc/connection.h`, righe 585–612, nell'SDK macOS di Xcode-beta; [API Apple](https://developer.apple.com/documentation/xpc/xpc_connection_cancel(_:)).

Il manuale pubblico `xpcservice.plist(5)` dell'SDK descrive la discovery dei servizi inclusi nell'app e nei framework da essa usati. Non è una specifica per registrare un `.xpc` arbitrario installato dopo la firma di Cascade. Non è stato identificato in questa ricognizione un percorso documentato che combini pacchetti di editori esterni, assenza di codice addon nel processo grafico, isolamento per owner e durata gestita. Un servizio fisso incluso in Cascade non dimostrerebbe da solo la parità con addon esterni. Fonte: SDK `usr/share/man/man5/xpcservice.plist.5`, righe 16–39; [struttura dei bundle Apple](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle).

La pista XPC rimane **non qualificata**, non dimostrata impossibile. Non viene trasformata in un adapter di produzione sulla base della sola descrizione generale della durata.

### ExtensionFoundation non offre una correzione già dimostrata

L'interfaccia pubblica `AppExtensionProcess` nell'SDK esaminato espone `invalidate`, creazione di connessioni/sessioni e callback di interruzione, senza una distinta operazione pubblica di arresto forzato. La [documentazione di invalidate](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/invalidate()) descrive la terminazione all'ultima connessione. La [fixture locale precedente](../../superpowers/verification/2026-09-09-addon-runtime-P0.md) conserva però il fallimento reale con worker non cooperativo anche dopo invalidazione di entrambi i canali e rilascio dei riferimenti. Non si riclassifica quel risultato come PASS e non si ripete la stessa prova senza una nuova ipotesi verificabile.

### Autenticazione XPC: controllo dei messaggi ricevuti

L'SDK espone `xpc_connection_set_peer_code_signing_requirement` da macOS 12, quindi senza innalzare il minimo compilato di Cascade. Il requisito viene verificato sui messaggi **ricevuti**. Non garantisce che un messaggio in uscita non sia consegnato a un peer non autorizzato. L'[interpretazione DTS di Apple](https://developer.apple.com/forums/thread/837286) conferma questa distinzione; `xpc/connection.h`, righe 772–803, ne documenta il comportamento. La [guida DTS all'autenticazione](https://developer.apple.com/forums/thread/681053) raccomanda le API pubbliche di code-signing requirement e, per i messaggi C XPC, `SecCodeCreateWithXPCMessage`.

Conseguenza per C1: non inviare grant, dati privati o comandi con effetti come primo messaggio assumendo che il controllo del peer protegga anche l'invio. Il bootstrap deve avere contenuto non sensibile; prima dell'ammissione serve una strategia completa che vincoli la destinazione autorizzata anche rispetto a sostituzione, exec e trasferimento degli endpoint. Un semplice saluto iniziale autenticato non prova che gli invii successivi mantengano la stessa destinazione. Questo rapporto non sceglie né inventa un nuovo protocollo crittografico per colmare il problema.

## Raccordo effettivo al codice

Il grafo MCP non contiene il progetto Cascade; è stato usato il fallback sul filesystem.

- [`AddonRuntimeTransport.swift`](../../../CascadeKit/Sources/CascadeRuntime/AddonRuntimeTransport.swift) dichiara ancora esplicitamente l'assenza di un conformer produttivo di `AddonRuntimeAdapter`.
- L'adapter attuale ha handoff sincrono e limitato, ingresso con proprietà esclusiva, receipt e rilascio fisico. Storage, asset, invocazioni e sottoscrizioni condividono la capacità. La vecchia bozza `send(event) async -> output` non basta a rappresentare il contratto corrente.
- [`Package.swift`](../../../CascadeKit/Package.swift) non contiene un target di trasporto nativo. [`CascadeServices.start`](../../../Cascade/CascadeServices.swift) registra ancora `ClockWidget` direttamente.
- Il [piano C1](../../superpowers/plans/2026-09-10-addon-runtime-completion.md) richiede C0 ammesso per l'adapter reale. Aggiungere un conformer simulato o un altro launcher privo di controllo della durata non soddisfa questo prerequisito.

## Condizione concreta per riprendere l'implementazione

Serve un meccanismo pubblico documentato o una nuova architettura dimostrabile che unisca:

1. proprietà della durata dalla creazione del processo, senza aggancio tardivo;
2. stop del processo esatto mentre l'host vive, con prova della sua uscita;
3. conservazione di sandbox, firma e identità per owner;
4. supporto ai pacchetti esterni senza caricarne codice nel processo grafico;
5. ammissione autenticata e capacità limitata compatibili con l'adapter corrente.

La prima proposta che soddisfa questi punti va trasformata in un esperimento firmato finito e revisionabile, poi misurata. Ripetere parser, simulatori, prove di EOF o l'invalidazione già fallita non risolverebbe il prerequisito.

### Domanda tecnica pronta per Apple DTS — non inviata

> We are building a macOS 14+ host for separately signed native addon packages. Addon code must remain outside the GUI process, with App Sandbox and Hardened Runtime preserved. We require managed-process cleanup after host or supervisor death, including startup before main, plus explicit termination of an unresponsive addon while the host remains alive. We distinguish IPC invalidation and a signal request from observed process exit. Direct-child spawn leaves a pre-attachment lifetime gap; the current local ExtensionFoundation fixture does not stop a noncooperative worker after all connections are invalidated, although host death does stop it. Does Apple provide a supported lifecycle owner and identity-bound termination mechanism for this combination? If Application-type embedded XPC services are the intended solution, what supported packaging/discovery path admits separately installed third-party addon code without changing the signed host bundle or loading that code into the GUI process? Please distinguish the documented client-lifetime contract from startup coverage, on-demand stop, exit observation, and publisher isolation. We seek a supported mechanism or a precise compatibility boundary, not a private SPI or a debugging entitlement workaround.

## Verifica di questa consegna

Lavoro documentale e lettura di sorgenti/API; nessuna build o prova nativa addon eseguita, nessun nuovo risultato di test rivendicato. L'ultima suite prodotto registrata rimane quella del 23 settembre, non rieseguita qui. Nessuna modifica a codice prodotto, entitlement, dipendenze o record di ammissione. Il driver C0d conserva l'uscita incondizionata 78 e SHA-256 `687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`. Il riavvio ordinario di Cascade è una verifica separata dell'app esistente e non qualifica il launcher.
