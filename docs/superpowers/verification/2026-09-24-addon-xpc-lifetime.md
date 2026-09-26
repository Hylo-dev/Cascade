# Prova mirata XPC — 24 settembre 2026

**Esito: tre casi positivi, cancellazione con client vivo negativa. Launcher ancora bloccato.**

Aggiornamento successivo: la [prova con intermediario XPC dedicato](2026-09-24-addon-xpc-broker.md)
ha verificato lo stop di una catena lasciando attiva l'app e una seconda catena.
Non modifica i risultati della cancellazione registrati qui né ammette il launcher.
Autorizzazione esplicita: «ok, procedi con la prova mirata XPC». Esperimento separato
dal driver C0d e dal codice prodotto; non cambia la decisione sui processi gestiti orfani.

## Risultato nativo

Una esecuzione completa della fixture firmata su macOS 27.0 (26A5425a), arm64,
SDK 27.0, Apple clang 21.0.0. Ogni scenario usa una nuova incarnazione.

| Scenario | Osservazione | Esito |
| --- | --- | --- |
| Servizio cooperativo, client vivo | Uscita con stato 0 osservata circa 0,6 ms dopo il trigger | PASS |
| Connessione cancellata, client vivo, callback trattenuto | Nessuna uscita osservata nei due secondi; client ancora vivo | FAIL |
| Uscita ordinaria del client, callback trattenuto | Uscita del servizio con SIGKILL osservata circa 1,6 ms dopo il trigger | PASS |
| Client termina con SIGKILL, callback trattenuto | Uscita del servizio con SIGKILL osservata circa 1,2 ms dopo il trigger | PASS |

I tempi sono differenze fra trigger e ricezione dell'evento kernel nell'osservatore,
non misure precise della latenza interna di macOS. Il FAIL riguarda la finestra di due
secondi, non una sopravvivenza indefinita. Durante la pulizia del caso cancel, l'uscita
del client ha prodotto l'uscita del servizio con SIGKILL; questo evento successivo è
registrato separatamente e non converte il caso in PASS. Per tutti e quattro i casi
sono confermate le uscite di client e servizio. Nessuna uscita dipende da SIGALRM.

## Attendibilità e limiti

Host e servizio sono fixture C fisse, firmate con l'identità Apple Development
`4A857D842A5406C2D3071776FDE7B27B3098FE63`, Hardened Runtime; il servizio ha soltanto
l'entitlement App Sandbox. Le verifiche delle firme sono riuscite. Le risposte
sono autenticate con requisito di firma e `SecCodeCreateWithXPCMessage`.

Il runner registra `EVFILT_PROC` con ricevuta, `NOTE_EXIT` e `NOTE_EXITSTATUS`;
un secondo messaggio autenticato conferma PID, UUID di incarnazione e deadline
dopo la registrazione. Conferma anche l'azione del client prima di classificare.
Non invia segnali al PID del servizio né a gruppi di processi. Conserva il proprio
figlio diretto per la pulizia del client. Il servizio ha un allarme di otto secondi
da main; un'uscita dovuta a quell'allarme, a un errore o a un crash della fixture
non viene accettata come successo della terminazione.

La prova copre esclusivamente un servizio Application incluso nel bundle, dopo main
e dopo l'autenticazione. Non prova la copertura prima di main, l'esecuzione di addon
esterni, l'isolamento fra editori, la protezione dei messaggi in uscita o un adapter
produttivo. Un singolo ciclo su questa versione di macOS non qualifica tutte le
versioni supportate. Il callback non cooperativo appartiene alla fixture controllata.

## Cosa cambia per la soluzione

XPC è una pista concreta per legare il servizio alla vita del suo client dopo l'avvio:
anche la morte forzata del client ha fatto terminare il servizio osservato. La sola
`xpc_connection_cancel` non soddisfa invece lo stop richiesto mentre quel client vive.

Una possibile architettura da valutare è un client intermedio dedicato a ciascun addon:
terminare quel client potrebbe fermare il relativo servizio lasciando Cascade aperta.
Non è una soluzione già dimostrata: occorrerebbe garantire anche la vita dell'intermediario
fin dalla creazione, evitando di spostare su di lui lo stesso problema, e qualificare
discovery, firma e installazione degli addon esterni. Il presente esperimento si conclude
qui; non introduce questo ulteriore livello né ammette il launcher.

## Evidenze e verifiche

- [Risultati grezzi](evidence/2026-09-24-xpc-lifetime/results.json), compresa la pulizia separata.
- [Manifest della build](evidence/2026-09-24-xpc-lifetime/build.json), comandi e hash di sorgenti/binari.
- [Log della build](evidence/2026-09-24-xpc-lifetime/build.log), firma, entitlement, sistema e compilatore.
- [Fixture e riproduzione](../../../Prototypes/AddonPlatform/XPCLifetime/README.md).

Sette test del verificatore passano. Revisione indipendente completata prima della
prova: corretti il falso positivo su crash/errore del servizio, la mancata conferma
dell'azione e la gestione dell'invalidazione attesa. La prima esecuzione nativa
(`probe-kf1be9u0`) si è interrotta nel runner per l'assenza di `KQ_EV_RECEIPT` nel modulo
Python; non produce un verdetto. Corretto usando `EV_RECEIPT = 0x0040` dall'header pubblico
`sys/event.h`, senza cambiare il criterio. La nuova build `probe-czbrf_sw` ha eseguito
tutti i casi e il runner ha restituito 1 per il risultato negativo valido di cancel.

I tentativi iniziali di build avevano rilevato due errori della fixture, corretti prima
della prova: callback di `xpc_main` e sintassi del requisito `codesign -R`.
Nessuna suite prodotto rieseguita: questa consegna aggiunge soltanto il prototipo e
le evidenze. Il gate `scripts/test-addon-managed-death.sh` rimane invariato,
SHA-256 `687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.

Riavvio ordinario di Cascade completato e verificato: PID precedente 24641, nuovo
PID 26301, eseguibile della build esistente CascadeDevelopment raggiunta da
`/Applications/Cascade.app`. Nessuna ricompilazione dell'app necessaria per il
prototipo separato. [Evidenza del riavvio](evidence/2026-09-24-xpc-lifetime/cascade-restart.json).
