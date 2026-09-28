# Intermediario con callback bloccato — 24 settembre 2026

**Lo stop sul canale bloccato fallisce; un secondo canale verso lo stesso broker
riesce a fermare broker e worker, lasciando app e catena B attive.**

Questa prosecuzione della [prova degli intermediari](2026-09-24-addon-xpc-broker.md)
approfondisce l'ultimo limite presentato all'utente, su richiesta «prova anche quello».
L'ambito misurato è il callback seriale di controllo bloccato, non l'intero processo
sospeso. Non aggiunge prove prima di main o sui pacchetti addon esterni.

## Disegno e risultati

La fixture conserva le due catene app → broker → worker, servizi annidati, firma,
Hardened Runtime e sandbox. `hold-both` inoltra `hold` al worker e trattiene il callback
di controllo del broker in `pause()`. Un'altra coda inoltra la risposta autenticata
del worker. Il runner conferma le identità dopo la registrazione degli eventi kernel.
Il loop bloccante non ha uscita cooperativa; altri thread restano disponibili.

| Prova | Risultato nei due secondi | Esito |
| --- | --- | --- |
| Stop A sul canale bloccato | Nessuna uscita A; app viva e stessa catena B risponde | FAIL |
| Cancellazione del canale A | Nessuna uscita A; app viva e stessa catena B risponde | FAIL |
| SIGKILL dell'app con A bloccato | Entrambi i broker e worker escono con SIGKILL | PASS |
| Stop A tramite secondo canale | Broker A esce 0; worker A esce SIGKILL; app viva e stessa catena B risponde | PASS |

Primi tre casi: build `nested-5mlrp477`; quarto: build `nested-dixw0aig`. Ogni caso
usa processi nuovi. Ambiente macOS 27.0 (26A5425a), arm64, SDK 27.0, clang 21.0.0.
Un'esecuzione per caso, senza qualificare tutte le versioni macOS supportate.

Nel quarto caso il runner apre una nuova connessione con lo stesso identificatore
di servizio, autentica la risposta del broker e confronta PID, UUID e deadline con
l'incarnazione già osservata. Solo dopo invia `exit` sul nuovo canale. La risposta
di identità non passa dal worker bloccato. Il broker esce circa 0,69 ms dopo il trigger,
il worker circa 1,41 ms dopo il trigger: tempi di ricezione degli eventi nell'osservatore,
non limiti temporali garantiti della piattaforma.

## Attendibilità e limiti

La misura usa kqueue con ricevuta, `NOTE_EXIT` e `NOTE_EXITSTATUS`; richiede seconda
conferma delle incarnazioni, azione del client e risposta della stessa catena B.
I messaggi del broker sono autenticati; il broker fidato autentica quelli del worker.
Non vengono segnalati PID di servizi né gruppi. Le guardie SIGALRM scattano dodici
secondi dopo main; la loro eventuale uscita non conta come PASS.

Tutti i quattro servizi sono stati registrati e la loro uscita finale è confermata
in ciascun caso. Nei due FAIL la chiusura dell'app durante la pulizia fa uscire anche A;
le uscite successive restano separate e non modificano il verdetto negativo.
Nessuna uscita ha richiesto SIGALRM.

Separare il controllo dal canale che può bloccarsi è una soluzione dimostrata per
questa specifica classe di stallo. Richiede ancora una coda disponibile a eseguire
lo stop nel broker fidato. Non dimostra recupero selettivo da sospensione dell'intero
processo, esaurimento di tutti i thread o blocco condiviso anche dal controllo.
La prova usa processi fissi fidati, non addon arbitrari.

Il launcher rimane non ammesso: avvio prima di main, percorso pubblico per pacchetti
esterni e garanzia completa di arresto del broker restano aperti. Policy, adapter,
entitlements di Cascade e gate C0d sono invariati.

## Evidenze e verifica

- [Tre scenari con callback bloccato](evidence/2026-09-24-xpc-broker-blocked/blocked/results.json).
- [Recupero con secondo canale](evidence/2026-09-24-xpc-broker-blocked/control/results.json).
- [Manifest primo ciclo](evidence/2026-09-24-xpc-broker-blocked/blocked/build.json) e [secondo ciclo](evidence/2026-09-24-xpc-broker-blocked/control/build.json).
- [Build primo ciclo](evidence/2026-09-24-xpc-broker-blocked/blocked/build.log) e [secondo ciclo](evidence/2026-09-24-xpc-broker-blocked/control/build.log).
- [Fixture e comandi](../../../Prototypes/AddonPlatform/XPCBroker/README.md).

Entrambe le cartelle conservano anche i sorgenti corrispondenti ai manifest.
Nove test del classificatore e sette del verificatore precedente riusato passano.
I nuovi test sono stati osservati fallire prima dell'implementazione. La revisione
indipendente ha individuato un falso negativo del criterio di cancellazione, corretto:
un'eventuale uscita SIGKILL/SIGTERM del broker in quel caso viene ora accettata.
Anche il controllo della stessa incarnazione sul secondo canale è stato revisionato
prima della run.

Nessun test o build dell'app prodotto eseguito: modifiche limitate al prototipo separato.
SHA-256 del gate C0d invariato:
`687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.

Cascade riavviata ordinariamente e verificata: PID precedente 28002, nuovo PID 29180,
eseguibile della build esistente CascadeDevelopment raggiunta da `/Applications/Cascade.app`.
[Evidenza](evidence/2026-09-24-xpc-broker-blocked/cascade-restart.json).
