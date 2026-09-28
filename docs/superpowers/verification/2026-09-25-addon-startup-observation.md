# Uscita del provider durante lo startup — 25 settembre 2026

## Risultato e limite

15 scenari nativi PASS, distribuiti su tre varianti della stessa fixture, più tre
controlli negativi di autenticazione riusciti. Il provider viene identificato
mentre è bloccato dentro `AppExtension.init`, poi in un costruttore C precedente
all'entry point, infine nello stesso costruttore con SIGTERM ignorato. Arresto/crash
del broker e uscita/crash del root fanno terminare il provider osservato. Nel
profilo resistente lo status kernel è SIGKILL, senza intervento del runner sul PID.

**Non è ancora l'ammissione del launcher.** Resta senza prova l'intervallo fra
creazione del processo e ingresso nel primo codice diagnostico. L'inizializzazione
di dyld e delle dipendenze precede il costruttore C. Non è una dimostrazione di
impossibilità, ma neppure una ragione per derogare alla decisione dell'utente del
20 settembre. Gate C0d invariato: exit 78, SHA256
`687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.

Prova locale su macOS 27 beta 26A5425a arm64, SDK 27, target minimo 14 invariato.
Provider e host della fixture appartengono allo stesso editore; compatibilità con
altri sistemi/editori e integrazione nel prodotto non sono qualificate da questa
matrice. Non è stato modificato il codice della vera app Cascade.

## Autorizzazione e metodo

L'utente ha autorizzato la prosecuzione autonoma delle prove finché non occorre
un suo intervento. Si è mantenuta la fixture esterna già abilitata; nessun nuovo
consenso in Impostazioni, grant TCC, servizio permanente o contatto con Apple.
Le skill systematic-debugging, ponytail, research, test-driven-development,
requesting-code-review e verification-before-completion hanno guidato l'indagine.

L'osservatore è figlio diretto conservato dal runner e sopravvive al root sotto
prova. Un messaggio Mach HELLO trasporta un audit token allegato dal kernel.
Security verifica identifier, certificato leaf, **CDHash della build esatta** e
percorso del bundle. Il runner registra EVFILT_PROC con EV_RECEIPT e NOTE_EXEC/EXIT;
soltanto dopo la ricevuta positiva l'osservatore manda una challenge imprevedibile.
L'ACK deve provenire dallo stesso token completo, UUID, deadline e fase. Nessun
PID dichiarato dal target viene accettato senza quel riscontro.

L'osservatore registra un nome Mach univoco con `bootstrap_register`, API pubblica
ma deprecata, limitata alla diagnostica. La sola fixture provider aggiunge
`com.apple.security.temporary-exception.mach-lookup.global-name` per quel nome;
App Sandbox resta attiva. Questo **profilo differisce dal prodotto** e non decide
il futuro trasporto SDK. A fine caso il nome deve risultare UNKNOWN_SERVICE.
Le fonti primarie e i limiti delle API sono nella [ricerca](../../wayfinder/research/2026-09-25-addon-startup-observer.md).

Le guardie indipendenti sono 25 s nel provider, 35 nel broker, 40 nell'osservatore,
45 nel root. La finestra di misura è 8 s, interamente precedente alle guardie.
Il verdict usa la fotografia delle uscite prima del cleanup: né SIGALRM né un
kill successivo di cleanup possono produrre PASS. I soli processi terminabili
direttamente dal runner sono figli Popen conservati; nessun kill su PID scoperto.

## Matrice osservata

| Caso | AppExtension.init | Costruttore C | Costruttore C con SIGTERM ignorato |
|---|---|---|---|
| Sblocco e canale ordinario della stessa istanza | PASS | PASS | PASS |
| Stop broker, root ancora responsivo | PASS | PASS | PASS |
| SIGKILL broker, root ancora responsivo | PASS | PASS | PASS |
| Uscita normale root | PASS | PASS | PASS |
| SIGKILL root | PASS | PASS | PASS |
| Mittente con firma/identità diversa rifiutato | sì | sì | sì |

Il controllo di sblocco verifica lo stesso PID/UUID/deadline tramite il canale XPC
normale, poi ferma la catena. Negli altri quattro casi non viene rilasciato il blocco.
Tutti i provider ordinari escono con SIGTERM; tutti quelli configurati per ignorarlo
escono con SIGKILL. Questo prova l'uscita forzata osservata, **non** una sequenza di
segnali SIGTERM → SIGKILL, che il test non traccia.

Latenza provider dal trigger, inclusi i controlli: 1,849–3,321 ms nella init;
1,712–3,928 ms nel costruttore; 2,600–10,564 ms nel profilo resistente. Sono singole
osservazioni locali, non un limite temporale garantito. Tutti i cleanup confermano
l'uscita di root, broker e provider; osservatore vivo durante la misura, uscita
ordinata dell'osservatore e nome Mach assente dopo ogni caso.

In **tutte** le varianti il broker riporta `process-ready` mentre il provider è
ancora fermo. Quindi il ritorno da `AppExtensionProcess(configuration:)` non implica
che `AppExtension.init` sia finita o che il canale applicativo sia pronto. Il test
non viene descritto come un initializer host ancora pendente: la fase è accertata
nel codice esatto del provider, non dedotta dal solo stato host.

Per il costruttore sono conservati `otool -l`, `nm -nm`, `__init_offsets` e tabella
dei simboli indiretti. L'offset dell'initializer corrisponde a
`startup_before_entry`; LC_MAIN conduce allo stub `_NSExtensionMain`, come nella
build Xcode ordinaria. La guardia e l'UUID C sono riusati da Swift dopo lo sblocco.
Il timer parte quando viene armato, non dalla creazione del processo.

## Tentativi non qualificati conservati

- AF_UNIX, `probe-860_n5b0`: bind EPERM nel container, prima di avviare qualsiasi
  provider. TCC attribuisce Codex come responsible; nessun permesso ampliato per
  aggirare il diniego. Trasporto abbandonato per questa fixture.
- `probe-or1q_x20`: errore di compilazione per uso di `mach_port_destroy` deprecato;
  sostituito con rilascio esplicito dei diritti, nessun test nativo eseguito.
- `probe-7na4sb1w`: build arrestata perché il livello di output codesign non esponeva
  il CDHash richiesto; lettura corretta con `-dvvv`, nessun test nativo eseguito.
- `probe-xbuwn_k1`: negativo respinto e osservazione autenticata riuscita, ma
  release-control UNKNOWN. Il provider usciva con SIGTRAP dentro ExtensionFoundation.
  Il link manuale mancava dell'entry point `_NSExtensionMain` e del profilo
  `-application-extension` usati da Xcode. Ripristinati quei flag e il packaging
  normale senza Info.plist da CLI incorporato. Il successivo controllo passa.
  Il crash report del PID osservato e il cleanup completo sono archiviati.

La revisione ha inoltre rilevato che il classificatore accettava SIGTERM anche
per il broker a cui veniva iniettato SIGKILL. Corretto: richiede status 9 in quel
caso. Regressione osservata fallire prima e passare dopo la modifica. Analogo
controllo per il provider resistente e per l'etichetta della fase diagnostica.

## Evidenze e verifiche

Archivio: [evidence/2026-09-25-addon-startup-observation](evidence/2026-09-25-addon-startup-observation).

- `final-init`: `probe-4g99x6ye`, cinque PASS + negativo.
- `final-constructor`: `probe-h_9kxqgb`, cinque PASS + negativo.
- `final-resistant`: `probe-izxg04jl`, cinque PASS + negativo.
- `unix-preflight`, `c-build-error`, `cdhash-build-error`, `wrong-extension-entry`:
  tentativi precedenti, senza reinterpretarli come successi.
- Manifest, snapshot sorgenti, hash source/runner/binary, comandi, entitlements,
  ricevute kernel, audit token, timestamp e log conservati per ogni build finale.
  Integrità verificata prima delle modifiche successive; i vecchi risultati vanno
  ricalcolati con il classificatore del relativo snapshot.
- 33 test Python verdi: StartupObservation 8, BrokerRecovery 11, Recovery 4,
  Interruption 3, XPCLifetime 7. Evidenza in `unit-tests.json`.
- Revisione indipendente dei sorgenti, classifier e risultati nativi.
- Il gate produttivo rimane exit 78 (`gate.json`). Nessun adapter produttivo abilitato.

## Frontiera rimasta

Il trasporto diagnostico ha permesso una prova indipendente in fasi prima
inaccessibili al normale handshake. Non rende osservabile dall'esterno uno stallo
precedente a qualsiasi codice della fixture e non crea un handle pubblico di
terminazione valido dalla nascita del processo. Anticipare ancora una callback
non eliminerebbe, da solo, questa lacuna. Nessuna nuova scelta di policy viene
richiesta: la decisione di tenere il launcher bloccato resta applicata.

## Riavvio dell'app

Cascade chiusa e rilanciata dalla build già collegata in `/Applications/Cascade.app`,
con nuovo PID 63292 verificato stabile per tre secondi. Nessuna modifica al
codice dell'app, quindi nessuna nuova build prodotto richiesta. Percorso effettivo
e comandi sono in `restart.json`.
