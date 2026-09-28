# Identità esterna e preparazione della prova sospesa — 25 settembre 2026

## Risultato

Due esecuzioni native verificano l'identità del provider senza usarne il messaggio
HELLO. Il profilo resta Hardened Runtime e App Sandbox, con il solo entitlement
`com.apple.security.app-sandbox` sul provider. Nessun get-task-allow, debugger,
ptrace, API privata o grant TCC aggiunto. Il launcher produttivo rimane bloccato.

| Verifica | Esito osservato |
| --- | --- |
| task-name port → token kernel → firma/CDHash/path → ricevuta kqueue → token invariato | riuscita in entrambe le esecuzioni |
| Processo diverso, firmato dallo stesso editore | rifiutato da Security, status -67050, in entrambe |
| HELLO ordinario successivo e nuova conferma esterna | stesso provider |
| Uscita cooperativa del primo provider | evento kernel, status 0, prima della guardia |
| Nuovo provider nel medesimo broker | nuova istanza, stesso dominio e label diagnostico |
| Chiusura root e uscita di broker/provider sostitutivo | root 0, broker 9, provider 15; cleanup completo |
| Acquisizione task control port | negata, status 5 in entrambe |
| Configurazione diagnostica launchctl della prossima invocazione | negata: richiede root |

Ambiente: macOS 27 beta 26A5425a arm64, SDK 27, deployment target 14 invariato.
Nessuna qualificazione runtime di macOS 14/Intel o di editori diversi.

## Che cosa aggiunge

Il PID letto da `ps` fornisce soltanto un candidato. Il codice C conserva un name
port, legge `TASK_AUDIT_TOKEN`, autentica con Security il token completo rispetto
a identifier, leaf, CDHash arm64 esatto e bundle path, poi registra EXIT/EXEC con
EV_RECEIPT. Rilegge e autentica lo stesso token dopo la registrazione. La prima
richiesta HELLO viene inviata soltanto dopo questo passaggio; il broker deve già
riportare `channel-ready`, evitando due avvii concorrenti.

Prima dello stop viene verificata l'assenza di eventi già accodati e nuovamente
l'identità. L'osservatore registra l'uscita; il tempo è quello della lettura
dell'evento, non il timestamp del kernel. La prova verifica un provider ordinario
già in esecuzione: **non dimostra che nessuna sua istruzione fosse stata eseguita**.
Non si confonde assenza di HELLO con sospensione o assenza di IPC interno al framework.

Gli snapshot launchctl mostrano il provider nel dominio `pid/<brokerPID>` con
label `hylo.Cascade.AddonProbeContainer.Provider`. Dopo l'uscita cooperativa il
servizio resta inattivo; la nuova richiesta EF usa nuovamente il medesimo dominio
e label. Sono osservazioni diagnostiche locali, non un'API stabile di discovery
né un handle della singola incarnazione.

Il primo preflight supera così la dipendenza dal codice collaborativo per
l'identificazione. Il control port resta invece indisponibile: il name port non
conferisce il diritto di terminare il processo. Nel secondo caso il comando
`launchctl debug` tenta soltanto l'aggiunta della variabile inutilizzata
`CASCADE_PROBE_DEBUG_PREFLIGHT=1`; exit 1 e messaggio `requires root privileges`.
Non è mai stato armato `--start-suspended`, né richiesta elevazione tramite sudo.

## Prossima prova: laboratorio macOS eliminabile

La soluzione candidata al problema del recupero della prova è una VM dedicata.
Il processo resta firmato con il profilo ordinario e viene avviato normalmente
da ExtensionFoundation; il privilegio amministrativo per configurare il solo job
di prova rimane nel guest. Un controllo sul Mac ospitante può arrestare la VM se
il provider sospeso sopravvive al fault. Apple documenta lo stop anche da stato
Paused senza attendere una chiusura cooperativa del guest.
[VZVirtualMachine.stop](https://developer.apple.com/documentation/virtualization/vzvirtualmachine/stop(completionhandler:)).

Sequenza da qualificare, **non ancora eseguita**:

1. Preparare una VM senza dati personali, importando le fixture già firmate; le
   chiavi di firma restano sul Mac. Qualificare prima l'arresto forzato della VM e
   l'acquisizione dei log dall'esterno. Nessun falso PASS prodotto dal cleanup.
2. Ripetere il preflight ordinario nel guest. Identificare il job esatto durante
   la prima esecuzione, verificarne lo stato inattivo dopo l'uscita e mantenere
   vivi root/broker. Solo la configurazione diagnostica launchctl usa root.
3. Armare una sola invocazione sospesa e richiederla tramite EF. Verificare token,
   firma, immagine effettiva e fase di stop: provider e xpcproxy sono casi distinti.
4. Iniettare perdita di broker/root con osservatore indipendente vivo. Salvare
   risultato ed eventi prima di qualsiasi recupero. Se necessario, arrestare la
   VM; il caso resta FAIL/UNKNOWN secondo le osservazioni precedenti allo stop.

Questo cambia l'ambiente di test, non il formato addon o l'architettura del
prodotto. Un futuro PASS nella VM non coprirebbe automaticamente primo avvio,
intervallo xpcproxy o ogni versione macOS. I relativi requisiti restano espliciti.
La variante con get-task-allow/debugger è stata valutata ma non realizzata perché
proverebbe un profilo diverso da quello richiesto.

Nessun runtime VM trovato nelle applicazioni/CLI e nei percorsi comuni controllati.
Il volume dati locale riporta circa 5,9 GiB disponibili; i due volumi Asahi montati
hanno circa 1,4 GiB ciascuno. Nessuno è adatto alla preparazione. La guida Tart
indica circa 25 GB per l'immagine pronta e default di 2 CPU/4 GB RAM; la proposta
di riservare almeno 60 GB è un margine operativo per immagine, disco e prove,
non un requisito minimo del framework. Domanda sul volume da usare inviata
all'utente; nessuna VM scaricata, installazione o cancellazione di dati personali.
[Tart Quick Start](https://tart.run/quick-start/).

## Evidenze

[Archivio](evidence/2026-09-25-addon-external-identity): `ordinary` corrisponde a
`probe-8zj1e_09`; `debug-permission` a `probe-veiyjfa3`. Sono conservati manifest,
sorgenti e runner esatti, log, token, ricevute, snapshot launchctl e risultati.
Le fixture firmate sono in `signed-fixture.tar.gz`: copie .app sciolte nell'albero
iCloud ricevevano metadati Finder che impedivano la verifica strict. Gli archivi
sono stati estratti in una directory temporanea, ricontrollati byte per byte e
verificati con codesign; `integrity.json` registra gli hash. Nessuna modifica dei
binari eseguiti per archiviare le prove.

La prima build `probe-t779x3qs` non è stata eseguita: la revisione ha individuato
prima del lancio la corsa fra begin-startup/hello, l'assenza dell'osservazione di
cleanup della seconda catena e la mancata verifica degli eventi pre-trigger.
Le due build eseguite includono le correzioni. Revisione indipendente conferma
i claim limitati della prima esecuzione; il secondo risultato è stato verificato
tramite manifest, token, sequenza degli eventi e uscite registrate.

Gate eseguito: exit 78; SHA256 invariato
`687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.
Nessun codice della vera app Cascade modificato. Il riavvio obbligatorio dell'app
è registrato separatamente in `restart.json` nell'archivio.
