# Cascade Addon Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Subagent-driven execution is optional only when separately selected; planning this work does not dispatch agents.

**Goal:** Realizzare una piattaforma nativa di addon autonomi dall'app sorgente, con contenuti conservati dall'host e un unico SDK usato obbligatoriamente anche dai widget Cascade.

**Architecture:** Cascade conserva e disegna i contenuti ordinari con SwiftUI; i provider eseguono codice in processi separati su domanda. REQUIRES, servizi condivisi, azioni, piani temporali, lease e budget passano da un runtime comune. Scene SwiftUI remote offrono UI avanzata soltanto quando richiesta e visibile.

**Tech Stack:** Swift tools 6.2, macOS 14, SwiftUI/AppKit, Foundation, Swift Concurrency/Dispatch, XPC, ExtensionFoundation/ExtensionKit attraverso API compatibili verificate; Swift Testing, XCTest e strumenti Apple di profilazione.

**Spec:** [architettura approvata](../specs/2026-09-09-addon-runtime-design.md), da leggere insieme a questo piano.

## Global Constraints

- macOS 14 come minimo dell'app. Non si alza implicitamente il deployment target.
- Sistema interamente nativo: nessun WebAssembly, JavaScriptCore, interprete generale o dipendenza terza senza motivazione nuova.
- Cascade deve essere aperta. L'app sorgente può essere chiusa o assente se le funzioni dell'addon sono autosufficienti.
- Tutti i futuri widget, avvisi e attività sviluppati dal team usano lo stesso SDK, manifest, REQUIRES, modello di contenuti/azioni, catalogo, lifecycle e controllo delle risorse degli addon esterni.
- Il codice personalizzato degli addon non viene caricato nel processo grafico dell'host, inclusi gli addon del team. Sostituti in-process ammessi solo nei test.
- Renderer e adapter di sistema sono infrastruttura condivisa. Nessuna esenzione di quote o accesso diretto al motore in base al produttore del widget.
- Un contenuto visibile non richiede un provider residente. La chiusura prevista del provider non conclude la pubblicazione.
- SwiftUI dell'SDK significa componenti con descrizione serializzabile; non serializzazione arbitraria di AnyView. La scena remota ha un lifecycle distinto.
- Nessun polling per addon, attesa IPC sincrona sul MainActor o chiamata al provider nel display link. Code e collezioni hanno limiti.
- Budget numerici nella specifica: valori iniziali da misurare, non prestazioni già ottenute. Quote applicative e soglie CPU/RAM sorvegliate restano distinte.
- Congelamento dei processi escluso dal comportamento ordinario v1; eventuale esperimento separato dopo misure di attesa IPC/riavvio.
- Preservare identità di firma/TCC e comportamenti visivi/di input esistenti durante la migrazione; nessuna concessione automatica dei permessi macOS.
- Dopo modifiche al codice app: build riuscita, aggiornamento di /Applications/Cascade.app attraverso lo script del progetto, riavvio e verifica del nuovo processo. In caso di blocco, dichiarare l'impedimento.

## Stato e perimetro

**Esecuzione residua dal 10 settembre:** seguire il [piano di completamento](2026-09-10-addon-runtime-completion.md), che riusa P1, corregge le firme proposte rispetto al codice presente e organizza il lavoro in cinque consegne verificabili. La successiva [decisione approvata sul lavoro delegato](../specs/2026-09-10-addon-control-policy.md) risolve il punto di prodotto: restano da qualificare arresto e identità dei processi gestiti.

Il 9 settembre 2026 è iniziata l'implementazione. **P0 non ha superato il gate del launcher**: il percorso ExtensionKit autentica i processi ma non arresta il worker bloccato mentre l'host resta aperto. Il successivo prototipo con figlio diretto risolve l'arresto e le metriche, ma consente avvii delegati a Launch Services fuori dal supervisore. Entrambi restano sperimentali. Risultati e comandi sono nel [rapporto P0](../verification/2026-09-09-addon-runtime-P0.md).

P1 introduce contratti, builder/renderer SwiftUI, SDK provider, REQUIRES e pubblicazioni possedute dall'host. Le verifiche automatiche e le revisioni sono registrate nel [rapporto P1](../verification/2026-09-09-addon-runtime-P1.md). P2/P3/P4 restano aperte: non è stato incorporato un launcher non verificato né migrato un widget attraverso un'esenzione privata. Le caselle sotto indicano il completamento dell'intera fase, comprese le prove desktop ancora mancanti.

Il piano è diviso in **5 fasi, 19 task**, ciascuno con file, interfacce, casi di verifica e risultato atteso. P0 risolve prima le incognite della piattaforma; i dettagli dell'adapter macOS si fissano dalle sue evidenze, senza inventare oggi API o garanzie di lancio. Per i contratti indipendenti dalla piattaforma, P1/P2 definiscono già i valori e le firme da condividere.

Il working tree contiene lavoro precedente non committato. All'avvio di ogni fase leggere git status, conservare quelle modifiche, isolare il lavoro se necessario e non usare comandi di ripristino globali. I percorsi seguenti sono relativi alla radice del repository. Nessun file proposto è dichiarato già esistente.

La mappa di prodotto resta [qui](../../../.scratch/cascade-product/map.md). Questo piano rende eseguibile il sottosistema addon; non dichiara conclusi i ticket su routing audio, file shelf o tutte le future funzioni dell'app.

## Ordine di esecuzione

| Fase | Piano operativo | Uscita verificabile |
| --- | --- | --- |
| P0 | [Fattibilità del processo e delle scene](2026-09-09-addon-runtime-00-platform.md) | Addon standalone nativo, connessione autenticata, uscita dopo morte dell'host e scena remota provati sulle combinazioni disponibili |
| P1 | [Contratti, SDK e contenuti](2026-09-09-addon-runtime-01-contracts.md) | Manifest e contenuti limitati, builder Swift, resolver, renderer e snapshot indipendenti dalla connessione |
| P2 | [Runtime, servizi e risorse](2026-09-09-addon-runtime-02-execution.md) | Processi su domanda, azioni affidabili, lease, servizi condivisi, storage e supervisione |
| P3 | [Integrazione e widget del team](2026-09-09-addon-runtime-03-adoption.md) | Clock, timer, avvisi e media attraverso l'SDK comune; UI remota gestita dallo stesso runtime |
| P4 | [Distribuzione e qualificazione](2026-09-09-addon-runtime-04-release.md) | Installazione/aggiornamento, esempio esterno, strumenti SDK e prove di prestazioni/guasti |

- [ ] P0 completata con matrice e scelta del launcher documentate.
- [ ] P1 completata con test puri, anteprime e prima prova di contenuto conservato.
- [ ] P2 completata con guasti di processi reali e nessun processo dopo uscita dell'host.
- [ ] P3 completata con i widget del team sul percorso pubblico e vecchi bypass rimossi.
- [ ] P4 completata con un addon costruito in un progetto indipendente e misure riproducibili.

P1 può avanzare sui modelli puri mentre P0 verifica la piattaforma, ma P2 non incorpora un launcher non verificato. P3 non usa scorciatoie in-process per aggirare P2. La scena remota è parte dell'obiettivo: può essere integrata dopo il percorso ordinario, ma non omessa per dichiarare finito l'intero piano.

## Struttura dei file e responsabilità

Si estende inizialmente lo Swift package esistente, senza aprire repository aggiuntivi.

| Percorso | Responsabilità |
| --- | --- |
| CascadeKit/Package.swift | Prodotti pubblici SDK e target interni; dipendenze verificabili |
| CascadeKit/Sources/CascadeContracts/ | Valori wire, manifest, identità, errori, contenuto, versioni e risorse richieste |
| CascadeKit/Sources/CascadePresentation/ | Builder Swift a componenti e renderer SwiftUI condiviso con le anteprime |
| CascadeKit/Sources/CascadeAddonSDK/ | API sviluppatore per handler, azioni, pubblicazioni, storage e servizi |
| CascadeKit/Sources/CascadeTransport/ | Codec/connessioni native, verifica del peer e adapter piattaforma |
| CascadeKit/Sources/CascadeRuntime/ | Catalogo, risoluzione, processi, pubblicazioni, scheduler, broker e supervisione |
| CascadeKit/Sources/CascadeKit/Core/AddonPresentation/ | Unico adattamento dal contenuto runtime al motore del notch |
| Cascade/Addons/ | Catalogo degli addon distribuiti con Cascade, senza implementazioni private dei widget |
| Addons/Clock/, Addons/FocusTimer/, Addons/SystemNotices/, Addons/Media/ | Manifest, provider, eventuali scene e risorse dei widget del team |
| Cascade/Integrations/ | Adapter di sistema esistenti, esposti al broker come servizi condivisi |
| Examples/StandaloneFocus/ | Progetto che dipende soltanto dai prodotti pubblici SDK |
| Prototypes/AddonPlatform/ | Prova isolata di packaging, lancio, firme e scene; non dipendenza della produzione |
| scripts/test-addon-*.sh | Verifiche riproducibili introdotte nei rispettivi task |

I moduli Runtime e Transport non importano CascadeKit, né nomi dei widget concreti. CascadeKit può consumare Contracts e Presentation. Il prodotto SDK non esporta engine, finestre, monitor hardware o il catalogo interno. La dipendenza Transport dell'SDK espone solo il canale client, senza API host privilegiate.

## Vocabolario di interfaccia comune

Le firme nei sottopiani sono contratti di implementazione proposti, non API già esistenti. I tipi di valore vanno definiti in P1 prima di usarli in produzione:

| Tipo | Campi / significato |
| --- | --- |
| AddonID | Stringa reverse-DNS validata |
| PublicationID | AddonID autenticato, instanceID e sessionID; non coincide col PID |
| ConnectionGeneration | UUID nuovo a ogni avvio/handshake |
| AddonManifest | Identità, versione, compatibility, execution, sourceApp, bundledLibraries, REQUIRES, PROVIDES, features, permissions, resources della specifica |
| ContentDocument | schemaVersion, nodo radice, accessibilityLabel, privacy, asset referenziati |
| ContentNode | Text, symbol, image, row, column, progress, countdown, clock, action; figli e stringhe limitati |
| PresentationSet | Mappa limitata delle rappresentazioni widget, compactLeading, compactTrailing, minimal, expanded verso ContentDocument; sotto la stessa identità/revisione |
| Publication | ID, revisione, tipo widget/activity/notice, PresentationSet oppure piano temporale, policy di scadenza e obsolescenza |
| ScheduledEntry | Date, PresentationSet; massimo 32 voci / 256 KiB per istanza |
| ActionRequest | UUID richiesta, PublicationID, actionID, input limitato, deadline e revisione osservata; la generazione viene aggiunta dall'host all'invio, dopo l'eventuale avvio |
| ActionOutcome | completed(payload), rejected(reason), outcomeUnknown; accepted è un ack separato |
| Grant / Lease | Proprietario, servizio, scope, scadenza, generazione, costo concesso; dati assegnati dall'host. I token di connessione sono distinti dalle sottoscrizioni di interesse possedute dall'host |
| ServiceInvocation / ServiceResponse | ID richiesta, contratto/operazione e payload limitato; il broker autentica e instrada chiamate/risposte senza passare privilegi del chiamante al provider |
| InvocationCompletion | Risultato correlato action(requestID, outcome) oppure service(requestID, response), distinto dagli aggiornamenti di stato |
| ProviderOutput | Pubblicazioni, richieste di operazioni/lease, eventuale InvocationCompletion e checkpoint limitati; nessuna closure nel payload |
| StopReason | idle, disabled, permissionRevoked, resourceExceeded, hostStopping, updated |

Stato connessione, stato lavoro e stato pubblicazione sono distinti. Una pubblicazione valida sopravvive all'uscita prevista del provider; handle e risultati vecchi no. Un crash può rendere il contenuto obsoleto, mentre un disable elimina anche voci future e azioni.

## Verifica e registrazione dell'esito

Ogni task: aggiungere la prova comportamentale indicata, osservarne il fallimento pertinente, implementare, eseguire le verifiche nominate e revisionare il diff. Un file di test inesistente o un errore di configurazione non è un fallimento comportamentale valido. Commit limitato ai file del task quando lo stato del checkout lo consente; non includere modifiche pregresse.

Comando base dei test package, con cache scrivibili anche nell'ambiente ristretto:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-addon-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cascade-addon-swift-cache \
xcrun swift test --disable-sandbox --package-path CascadeKit \
  --scratch-path /private/tmp/cascade-addon-tests --filter NOME_SUITE
```

NOME_SUITE è l'argomento operativo da sostituire con la suite nominata nel task; non cambiare tutti i target a Swift 6 in un colpo. Preferire controlli di concorrenza completi nei nuovi target, mantenendo il comportamento dei target esistenti fino alla relativa migrazione.

Per una fase che modifica l'app:

```sh
/bin/zsh scripts/build-development.sh
/usr/bin/codesign --verify --deep --strict /Applications/Cascade.app
```

Lo script aggiorna il collegamento gestito in /Applications. Solo dopo successo chiudere Cascade, verificare che sia uscita, rilanciare quel percorso e verificare nuovo PID/percorso. Salvare esito, revisioni, comandi, OS e casi non eseguiti in docs/superpowers/verification/2026-09-09-addon-runtime-PN.md, dove PN è la fase. Non dichiarare supporto sulla base di soli mock o API presenti nell'SDK.

## Copertura della specifica

| Requisito | Task |
| --- | --- |
| App sorgente assente, Cascade obbligatoria | 00.1–00.2, 02.1, 03.2, 04.1 |
| REQUIRES, versioni, cicli, feature e binding | 01.1, 01.3, 02.3, 04.1 |
| Componenti SwiftUI e contenuto persistente senza provider | 01.2, 01.4, 02.2, 03.1–03.2 |
| Scene SwiftUI remote | 00.3, 03.4 |
| Azioni, revisioni, riconnessioni e risultati incerti | 01.1, 02.1–02.2 |
| Scheduler, servizi condivisi, privacy e permessi | 02.2–02.3, 03.3–03.4 |
| Quote, CPU/RAM, flooding, crash e quarantena | 00.2, 02.4, 04.3 |
| Asset, storage, migrazioni e rollback | 01.4, 02.5, 04.1 |
| Stesso sistema per i nostri widget | 01.2, 03.1–03.4, 04.2 |
| Compatibilità, pacchetto indipendente, guide e strumenti | 00.1–00.3, 04.1–04.3 |

## Definizione di completamento

La piattaforma è completa quando un addon esterno e gli addon del team usano gli stessi contratti e controlli, i contenuti ordinari sopravvivono all'uscita dei provider, le scene remote seguono la visibilità, le dipendenze si risolvono senza effetti nascosti e guasti/pressione di risorse non richiedono il riavvio di Cascade. Servono evidenze di processo reale e misure; non bastano documenti, protocolli dichiarati o esempi eseguiti dentro l'host.
