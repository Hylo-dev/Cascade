# Laboratorio macOS piccolo per la prova sospesa

Preparazione iniziata il 25 settembre 2026, autorizzata dall'utente dopo aver
liberato spazio. **Il 26 settembre la VM piccola è avviabile, SIP è stato ripristinato
e l'arresto completo dall'host è qualificato. La prova sospesa resta bloccata prima
del primo HELLO: il broker non ottiene l'identità dell'estensione su questo guest.**
Nessuna sospensione è stata armata e il gate produttivo resta invariato (exit 78).

Il guest osservato è macOS **14.3, build 23D56**, non la versione 14.1 indicata dal
tag scelto. La causa della discrepanza del tag non è stabilita; le conclusioni si
riferiscono al sistema effettivamente misurato. Al checkpoint nativo: 2 CPU, 4 GiB di RAM e disco allocato
17.855.008.768 byte (16,63 GiB). **Successivamente, su richiesta esplicita
dell'utente, la VM è stata eliminata e la strada VM sospesa.** Rimossi anche
Tart portatile, cache/state e credenziali SSH create per il guest; prove conservate
nel repository. Liberati circa 18 GB, con 21.872.640.000 byte liberi al controllo.

## Configurazione scelta

- Un solo guest Sonoma vanilla, selezionato dal tag 14.1 ma osservato come 14.3,
  senza Xcode, 2 CPU e 4 GiB di RAM.
- Immagine fissata a
  `ghcr.io/cirruslabs/macos-sonoma-vanilla@sha256:a6dc5a325aae43a90244953af0a85091fbe93e8f58583138c5ac96dd707fd700`.
  Download compresso 14,76 GiB; il disco virtuale da 50 GB è sparse. Lo spazio
  realmente occupato deve essere misurato, non dedotto dalla capacità virtuale.
- Tart 2.38.0 portatile verificato con codesign strict e Gatekeeper, in
  `/private/tmp/cascade-addon-vm`; cache e clone limitati alla stessa directory.
  Nessuna installazione di Tart in Applicazioni, Homebrew o toolchain nel guest.
- Controllo dello spazio libero durante download e avvio. Il primo limite di
  4,5 GiB ha interrotto il trasferimento al 99%; il tentativo successivo riserva
  3 GiB durante il download e inizialmente 3,5 GiB per l'avvio. Dopo il primo
  arresto in Recovery per spazio, anche l'avvio usa una riserva di 3 GiB.
  Nessuna cancellazione di dati personali; il controller conserva i dati parziali.
- Rete NAT standard; dopo il primo accesso SSH, rimozione delle route predefinite
  nel solo guest e controllo IPv4/IPv6. Non è una rete host-only.
- Stessa fixture firmata già archiviata nella prova esterna: nessuna modifica
  agli entitlement del provider e nessuna chiave di firma trasferita.

La scelta dell'immagine, la provenienza e il comportamento dei retry sono
documentati nella [ricerca](../../wayfinder/research/2026-09-25-small-macos-vm.md).

## Preparazione eseguita

Il payload estratto misura circa 32 MB e contiene fixture, osservatore, runner
e un runtime Python minimo già disponibile sull'host. L'archivio di trasferimento
misura 10.743.365 byte, SHA256
`4da64e8ea598e196ab32ce727f1f128713a5ca5b1d0f9211f9c4f73aae9d2333`.
Gli hash dei sorgenti e dei binari della fixture corrispondono al manifest
originale; le firme dei bundle estratti sono state verificate.

Il [runner](../../../Prototypes/AddonPlatform/ExternalIdentity/run_vm_suspended.py)
rifiuta l'esecuzione fuori da un guest VirtualMac esplicitamente dichiarato,
richiede l'attestazione dell'arresto esterno già provato, autentica il processo
sospeso e congela la classificazione prima del cleanup. Otto controlli automatici
passano; questo risultato riguarda il runner, non il comportamento nativo macOS.
La [procedura](../../../Prototypes/AddonPlatform/ExternalIdentity/VM-SUSPENDED.md)
specifica controlli e limiti.

Il runner successivo aggiunge una diagnostica opzionale `--stackshot`, ammessa
solo dopo il controllo baseline e solo nel modo `release-control`. I dodici
test del runner aggiornato passano. Il payload baseline resta quello originale:
la diagnostica opzionale non è stata inclusa nell'archivio né eseguita. Un rapporto
di spindump, da solo, non dimostra la fase di prima istruzione.

Verificato anche il rifiuto reale sull'host: pur con la variabile diagnostica
impostata, il runner termina con exit 78 prima di creare la directory risultati
o avviare una fixture, perché il modello hardware non è VirtualMac.

## Limite di spazio misurato

Il trasferimento iniziale ha raggiunto il 99%, poi il controller ha terminato il
proprio processo Tart con SIGTERM alla soglia configurata: 4.813.242.368 byte
liberi, contro una riserva di 4.831.838.208 byte. Ha rimosso soltanto la propria
directory `state` incompleta, riportando lo spazio libero a 22.428.499.968 byte.
La VM non era stata creata né avviata. Non è un fallimento di ExtensionFoundation.

La cancellazione automatica ha reso necessario ripetere il download. Nel secondo
controller questa politica è corretta: anche a soglia o timeout conserva lo stato
parziale. Il nuovo tentativo usa la stessa immagine fissata, sei trasferimenti,
riserva di 3 GiB e limite di quattro ore. Il margine rende plausibile completare
il trasferimento, ma non costituisce una verifica dell'avvio o dello spazio
necessario durante l'esecuzione.

Il tentativo a sei flussi esaurisce i retry di alcuni segmenti e viene fermato
con stato preservato. La ripresa a quattro flussi termina con exit 0 in
5.876,598 secondi. L'immagine locale è un file regolare indipendente dalla cache;
dopo la rimozione del riferimento OCI resta una sola VM, ferma. Configurazione
confermata: 2 CPU, memoria 4.294.967.296 byte, display 1024×768 pixel.

Il 26 settembre la compattazione offline dei blocchi interamente zero da 64 KiB
riduce l'allocazione da 17.812.783.104 a 17.584.783.360 byte. Dimensione logica
invariata a 50.000.000.000 byte; SHA256 completo prima e dopo identico:
`0c0d46984b170fe9f40bbcfc1ef3a490a878fbd95d8fdd3d6b051c677d085721`.
Sono state rimosse anche soltanto copie temporanee del payload e cache/intermedi
della build eseguita per questo lavoro. App compilata e archivio immutabile delle
prove sono conservati. Il successivo passaggio da 4 KiB recupera altri 77.402.112 byte, portando
l'allocazione a 17.507.381.248 byte con lo stesso SHA256 completo. Le variazioni
dello spazio libero dell'host sono maggiori: non vengono attribuite tutte alla
compattazione. Dopo avvii, importazione e log, il disco arriva a 17.855.008.768 byte.

## Prove native del 26 settembre

Il primo avvio risponde via SSH come `VirtualMac2,1`, account di laboratorio
`admin`, SIP disabilitato e authenticated root abilitato. Non vengono avviate
fixture in quel profilo. Dalla Recovery del solo guest viene eseguito
`csrutil enable`; due avvii normali successivi confermano SIP e authenticated root
abilitati. Nessuna protezione dell'host viene cambiata.

L'arresto esterno viene richiesto al processo Tart conservato dal controller:
SIGINT, messaggio `Stopping VM...`, exit 0 senza fallback SIGKILL, stato `stopped`.
Il successivo avvio della stessa configurazione cambia UUID da
`FBA4BFDB-27B7-497E-86CA-315E8104ECE1` a
`70146061-7758-48BA-AB56-0CED74AE20F9`. La
[prova di cleanup](evidence/2026-09-25-addon-small-vm/cleanup-evidence.json)
precede la creazione del marker richiesto dal runner. Questo qualifica il
contenimento di laboratorio osservato, non la morte dei processi addon o ogni
possibile guest bloccato.

Le route predefinite vengono rimosse dentro il guest. Le route IPv6 con scope
richiedono `-ifscope`: i primi tentativi incompleti sono conservati; i controlli
prima delle fixture confermano assenza di default sia IPv4 sia IPv6. La share
host resta in sola lettura. L'archivio originale da 10,7 MB passa il confronto
SHA256 nel guest; Python portatile funziona senza toolchain.

Il browser pubblico della fixture abilita `CascadeProbeProvider`. Dopo la
registrazione di `BrokerRecovery.app`, anche Impostazioni di Sistema → Extensions
→ BrokerRecovery mostra la stessa estensione già selezionata. Non sono stati
usati database di consenso, API private o modifiche agli entitlement.

| Controllo | Esito osservato |
| --- | --- |
| Baseline originale | FAIL prima di avviare figli: requirement con CDHash ARM verificato implicitamente su tutte le architetture |
| Matrice firma ARM | Requirement originale completo PASS con `--arch arm64`; pin errato e slice Intel respinti; nessuna modifica alla fixture |
| Baseline con selezione ARM | Firma/input PASS, root e broker autenticati; primo HELLO scade dopo 10 s, prima di armare `launchctl debug` |
| Diagnosi ordinaria | Cinque risposte `broker-info` durante HELLO mostrano `startupPhase=idle`; root termina con comando `quit` |
| Registrazione app del broker | Stesso blocco dopo `lsregister -f` dell'app esatta |
| Avvio tramite Launch Services | Stesso blocco con `open -W -n`, FIFO e vero PID root ottenuto da `ping` |
| Controllo diretto dall'app GUI | Discovery trova il provider, che raggiunge il proprio codice; la connessione viene correttamente respinta dal requisito broker-only (`-67050`) |

La correzione del preflight seleziona esclusivamente la slice ARM già fissata nel
manifest; la verifica d'integrità di tutte le slice rimane. È applicata al runner
nel repository. Nel guest è trasferita una copia separata della baseline con
**questa sola correzione**, SHA256
`0f6fb4c590bb2647b1ee961917530d34bd168be7d1e64d0ba47e7ef3b1385522`.
Archivio originale, manifest, requisito, binari, deadline e classificatore sono
immutati. La diagnostica stackshot del runner successivo non viene eseguita.

I log di discovery del broker riportano `-10814`, impossibilità di risolvere il
record dell'estensione per il suo audit token, e query con extension point nullo.
Il risultato resta invariato dopo registrazione del contenitore e avvio applicativo
LS. Questo circoscrive il problema al contesto broker su questa immagine/OS;
**non prova l'impossibilità generale su ogni macOS 14**. Il controllo GUI non è un
HELLO riuscito né un difetto nuovo del provider: la fixture originale ammette
come peer soltanto `hylo.Cascade.AddonProbe.DiscoveryBroker` e respinge la GUI.

Tutte le sequenze native si concludono con l'arresto completo del guest verificato.
Nessun processo è stato sospeso, nessun fault case è stato eseguito; un cleanup
riuscito non modifica la classificazione FAIL precedente.

## Frontiera ancora aperta

Ottenere il primo HELLO autenticato dal broker in un guest rappresentativo resta
prerequisito per il controllo di ripresa e i quattro casi di morte root/broker.
Non si aumenta implicitamente il minimo macOS 14 dell'app e non si allentano le
garanzie sui processi gestiti. La disponibilità dichiarata di un'API nel deployment
target non qualifica questa composizione in esecuzione.

Le [evidenze archiviate](evidence/2026-09-25-addon-small-vm/integrity.json) includono
manifest, controller, hash, log e risultati, senza immagini del sistema operativo,
chiavi SSH private o toolchain. Il gate finale restituisce exit 78 e mantiene SHA256
`687fb3086d41e821af684d49109c9c95f8d555cf88450bdcf809b2a708b1ddaa`.

Un eventuale PASS riguarda la seconda richiesta EF e l'immagine provider
autenticata. Non implica automaticamente copertura del primo avvio o
dell'intervallo precedente con xpcproxy, né ammissione del launcher in produzione.

Il contratto di `POSIX_SPAWN_START_SUSPENDED` colloca la sospensione prima
dell'esecuzione user-space, inclusa dyld; il manuale indica SIGCONT per la ripresa.
L'help di `launchctl debug --start-suspended` non specifica altrettanto precisamente
il passaggio di exec interessato nella catena EF. Pertanto firma, token,
`suspendCount > 0` e successivo HELLO della stessa istanza costituiscono osservazioni
dirette, ma non una lettura del program counter. La fase «prima della prima
istruzione» non verrà dichiarata provata soltanto da questi dati.
[Manuale Apple](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man3/posix_spawnattr_getflags.3.html),
[implementazione XNU della famiglia macOS 14](https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/kern/kern_exec.c#L1862-L1873).


## Verifica conclusiva dell'app e revisione

La revisione indipendente non rileva P1/P2 nel rapporto e nella nuova sezione
dell'issue 22; i primi 139 file del manifest sono confrontati con gli originali.
Dopo la correzione ARM, 12 test puri passano (attestazione del transcript, non un
nuovo log di stdout). La matrice statica conserva i negativi Intel e pin errato.

La build ufficiale di Cascade eseguita durante la preparazione è riuscita e il
link `/Applications/Cascade.app` punta a `CascadeDevelopment/Build/Products/Debug`.
L'intervento successivo modifica soltanto runner diagnostico e documentazione.
Nel riavvio conclusivo Cascade passa dal PID 39220 al nuovo PID documentato in
[cascade-restart-final.json](evidence/2026-09-25-addon-small-vm/cascade-restart-final.json),
stabile dopo tre secondi e con eseguibile corrispondente al link Applicazioni.


## Chiusura del laboratorio su richiesta dell'utente

L'utente chiede di fermare la strada VM, liberare lo spazio della macchina attuale
e riesaminare le possibilità senza VM. `tart delete cascade-addon-small` termina
con exit 0 dopo il controllo stopped; la lista successiva è vuota e non rimane
alcuna `disk.img` nello state. Vengono rimossi anche runtime portatile, state/cache,
archivio di trasferimento e sole credenziali SSH generate per questo laboratorio.
I risultati delle prove e la fixture firmata originale già archiviata sono
conservati. Non vengono scaricate immagini nuove né modificate decisioni di
architettura/minimo OS. [Rimozione VM](evidence/2026-09-25-addon-small-vm/vm-removal.json),
[rimozione residui](evidence/2026-09-25-addon-small-vm/runtime-removal.json).

Cascade viene chiusa e riaperta nuovamente dopo la rimozione: eseguibile della
build corrente verificato e nuovo PID stabile dopo tre secondi. Il record
[cascade-restart-after-removal.json](evidence/2026-09-25-addon-small-vm/cascade-restart-after-removal.json)
conferma anche assenza del disco e del runtime VM.

La prossima prova candidata senza VM è un recupero diagnostico sul job esatto di
un provider ordinario autenticato, con broker ancora vivo e guardia temporale
attiva. Non è ancora eseguita. `launchctl kill` individua un servizio, non una
capability della sua specifica incarnazione; un eventuale PASS non prova il
recupero dopo morte root/broker o il comportamento prima della prima istruzione.
SIGSTOP/SIGCONT resta un esperimento distinto: fermare il processo può impedire
alla guardia temporale di intervenire e non equivale a START_SUSPENDED.
