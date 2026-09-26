# P0 — esito della prova nativa del 9 settembre 2026

**Gate del launcher: NON SUPERATO.** Il prototipo è separato dal prodotto e non è
un esecutore utilizzabile dai widget Cascade. P1 può avanzare; P2/P3 non incorporano
questo launcher finché arresto e controllo delle risorse non sono dimostrati.

## Ambiente e percorso verificato

macOS 27 beta (26A5425a), Apple Silicon, Xcode beta / Swift 6.4. Target minimo compilato:
macOS 14. Le macchine 14/15/26 e una seconda identità di editore non sono disponibili;
quei casi sono **non verificati**, non implicitamente compatibili.

Tre target Xcode distinti: host `hylo.Cascade.AddonProbe`, contenitore standalone
`hylo.Cascade.AddonProbeContainer`, estensione
`hylo.Cascade.AddonProbeContainer.Provider`. Firma Apple Development del team di
sviluppo del progetto. Il contenitore include l'estensione e tutto il suo codice;
nessuna app sorgente completa, framework di tale app o servizio omonimo è richiesto.

Il target ExtensionKit genera il punto di ingresso corretto. Discovery attraverso
`AppExtensionIdentity.matching`, attivazione attraverso il browser Apple, avvio con
`AppExtensionProcess`. Un primo canale passa esclusivamente un endpoint anonimo;
il canale applicativo ordinario verifica team e signing identifier in entrambe le
direzioni con i requisiti di firma Foundation. Il PID dichiarato nella risposta deve
corrispondere al PID del peer fornito da Foundation ed essere diverso dall'host.

Le prove usano solo file sentinel creati dal harness, localhost e `/usr/bin/true`.
Nessun file o credenziale dell'utente viene letto. Il processo di prova non è un
worker registrato o avviato da Cascade.

## Risultati osservati

| Prova | Esito | Evidenza / limite |
| --- | --- | --- |
| Build reale ExtensionKit | PASS | Debug e Release firmate, prodotti in DerivedData |
| Echo autenticato standalone | PASS | Release: host 43206, provider 43209, UUID correlato, 165,41 ms complessivi; deadline esterna 2 s |
| Chiusura normale dell'host | PASS nella fixture | `NSApplication.terminate`: host 43401, provider 43403, uscita osservata in 318,72 ms dalla partenza della prova |
| Crash/kill dell'host con worker non cooperativo | PASS nella fixture | SIGKILL del solo host 43410; provider 43412 uscito, 154,12 ms dalla partenza della prova |
| Arresto esplicito mentre l'host vive | FAIL ripetuto | `AppExtensionProcess.invalidate`, invalidazione di entrambi i canali, listener e rilascio di tutti i riferimenti: worker spin ancora presente dopo 2 s, in Debug e Release |
| Lettura del sentinel di un'altra cartella addon | Accesso negato | Sandbox senza entitlement di file esterni; fixture realmente esistente |
| Connessione diretta di rete | Accesso negato | `connect` a localhost restituisce errore di permesso |
| Creazione di sottoprocesso | Consentita | `/usr/bin/true` viene avviato: App Sandbox da sola non garantisce assenza di processi aggiuntivi |
| Host con bundle/signing identity diversa | Discovery negata | Nessuna identità trovata; **non** equivale a una prova completa di rifiuto sul canale autenticato |
| CPU e physical footprint, aggregazione sottoprocessi | Non qualificato | Nessuna misura di RSS viene presentata come physical footprint; manca un adapter di supervisione ammesso |
| Messaggio JSON corrotto | PASS | Rifiuto intercettato senza crash dell’host, 150,22 ms complessivi |
| Riuso PID e arresto atomico sicuro | Non qualificato | Il cleanup del harness verifica fixture e start time, ma non è una soluzione produttiva al riuso PID |
| UI SwiftUI remota / focus / VoiceOver | Non implementata nella prova | La preview del renderer ordinario P1 non vale come prova ExtensionKit remota |
| Altro editore / altro OS | Non verificato | Firma locale e compilazione con target 14 non bastano |

Le latenze singole sono osservazioni diagnostiche, non p95, benchmark o budget
energetici qualificati. Il caso spin dura pochi secondi; il harness chiude prima
il proprio host e pulisce soltanto il PID autenticato della fixture, verificandone
percorso e istante di avvio. L'host ha anche un guardrail di cinque secondi.

## Problemi riprodotti e decisione

1. Sul sistema beta in uso, chiamare `setCodeSigningRequirement` direttamente sul
   `NSXPCConnection` gestito da ExtensionFoundation causa SIGSEGV in libxpc. Il
   bootstrap pubblico con listener ordinario risolve lo scambio autenticato; nessuna
   API privata viene utilizzata per aggirarlo.
2. L'invalidazione non ha fermato il worker bloccato mentre l'host è rimasto aperto.
   Eliminare la precedente finestra browser, rilasciare tutti i riferimenti e passare
   alla build Release non ha risolto la prova. La chiusura della connessione non viene
   quindi trattata come arresto del processo.
3. La sandbox consente sottoprocessi. Prima dell'ammissione pubblica serve una prova
   che il loro costo e la loro uscita siano governati con l'addon, oppure un profilo
   che ne vieti davvero l'esecuzione. Una dichiarazione nel manifest non lo risolve.

Il gate resta chiuso perché questi punti incidono direttamente sulla promessa di
risorse controllate. Non è stato introdotto un esecutore in-process, neppure per
widget del team, e non sono state ridotte silenziosamente le garanzie approvate.
Il prossimo lavoro produttivo dipende da una strategia di arresto e osservazione
verificata; una diversa soluzione di lancio richiede nuove prove P0 prima del trasporto
P2. La scena remota e la migrazione dei widget restano task aperti nel piano.

## Riproduzione e fonti

[README e comandi del prototipo](../../../Prototypes/AddonPlatform/README.md).
Gli output grezzi rigenerabili sono in `Prototypes/AddonPlatform/Results/` (ignorati
in git). I JSON registrano PID, requestID, percorso della fixture, tempi ed esito;
`lifecycle` e `sandbox` restituiscono errore finché le rispettive condizioni falliscono.

API confrontate con gli header pubblici nell'SDK locale e con la documentazione Apple:
[host di app extension](https://developer.apple.com/documentation/extensionfoundation/adding-support-for-app-extensions-to-your-app),
[estensione per un host](https://developer.apple.com/documentation/extensionfoundation/building-an-app-extension-to-support-a-host-app),
[discovery](https://developer.apple.com/documentation/extensionfoundation/discovering-app-extensions-from-your-app),
[invalidate](https://developer.apple.com/documentation/extensionfoundation/appextensionprocess/invalidate()).
Il fatto che un simbolo sia presente nell'SDK non è stato usato come prova della
relativa garanzia di esecuzione.

## Alternative verificate il 9–10 settembre

È stata implementata e ripetuta anche l'alternativa del processo figlio diretto
prevista dalla specifica. Il [prototipo DirectChild](../../../Prototypes/AddonPlatform/DirectChild/README.md)
usa un supervisore nativo distinto che conserva l'identità del figlio non ancora
raccolto, impone `RLIMIT_NPROC` soft/hard 0 prima di exec e reagisce alla chiusura della
pipe dell'host. Host e supervisore conservano i loro limiti originari.

Le prove reali mostrano arresto del figlio non cooperativo con host ancora vivo e
dopo uscita/crash dell'host; creazione diretta di figli e rialzo del limite negati;
letture di CPU/footprint riuscite e CPU confrontata con wait4. Questi risultati
risolvono la primitiva di controllo del figlio, **non l'intero profilo**.

Un controesempio impedisce il passaggio in produzione: il worker può chiedere a
Launch Services di aprire una app innocua firmata e leggibile dentro il proprio
bundle. Il limite dei figli diretti rimane 0, ma il processo avviato ha padre PID 1 e
non appartiene al supervisore. La prova controlla il percorso esatto del bundle e
il marker prodotto dall'app; non avvia applicazioni dell'utente. Le tre esecuzioni
falliscono esplicitamente `delegatedLaunchDenied`, con gli altri 15 controlli passati.
Il comando riproducibile è `/bin/zsh scripts/test-addon-direct-child.sh`; esce 1 per
questa ragione. Revisione indipendente conferma la coerenza di fonte, evidenze e cleanup.

Per ExtensionKit è stata provata anche la ricerca di un handle NSRunningApplication
sul peer già autenticato. Il provider headless restituisce **nessun handle**:
`forceTerminate()` non viene quindi chiamato. Non si tratta di una richiesta di
terminazione rifiutata. Comando: `CASCADE_PROBE_CONFIGURATION=Release /bin/zsh
scripts/test-addon-platform.sh --case application-stop`; esitoFAIL osservato con
host PID 50118/provider PID 50120. Il log completo conserva l'evento diagnostico.
La [documentazione Apple](https://developer.apple.com/documentation/appkit/nsrunningapplication)
limita questa API alle applicazioni tracciate, non a ogni processo.

Il [prototipo della scena SwiftUI remota](../../../Prototypes/AddonPlatform/RemoteUI/README.md)
compila, ma il controllo grafico del selettore è rimasto bloccato per circa 10,5 ore.
La scena non è stata abilitata né eseguita: nessuna prova di interazione o di
lifecycle remoto è dichiarata superata. È un impedimento dello strumento di prova,
non un difetto dimostrato di ExtensionKit.

**Decisione:** entrambi i percorsi di esecuzione rimangono sperimentali. Prima di P2
occorre dimostrare il controllo del lavoro delegato a macOS, oppure rivedere
esplicitamente il requisito di contenimento totale per il codice nativo. Vietare
soltanto la specifica app annidata di questa fixture non dimostrerebbe la garanzia.
Il sistema a componenti posseduti dall'host e i contratti P1 restano validi; nessun
bypass è stato introdotto per far avanzare i widget del team.

Ripetizione indipendente del 10 settembre: `/private/tmp/cascade-direct-child-root-verified.log`,
esito 1 con il solo controllo degli avvii delegati fallito in tutti e tre i casi.
Le app innocue osservate hanno PID 56745/56749/56753 e padre PID 1. Build finale
RemoteUI riuscita in `/private/tmp/cascade-remote-scene-final-build.log`; nessun
avvio della scena. Diagnostica finale ExtensionKit in
`/private/tmp/cascade-application-stop-final.log` con motivo specifico corretto.
