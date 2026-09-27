# Cascade — mappa del prodotto modulare

ID: cascade-product
Labels: wayfinder:map
Status: open
Updated: 2026-09-27

## Destination

Definire il piano applicativo globale di Cascade, basato sul codice esistente: un notch macOS modulare con widget e Live Activities forniti da app esterne. La destinazione globale è un insieme coerente di decisioni che consenta di scrivere le specifiche dei sottosistemi e ordinare i rilasci senza inventare requisiti. Per le tranche esecutive ammesse nelle Notes, la destinazione comprende implementazione, valutazione indipendente e consegna verificata degli incrementi addon autorizzati.

## Notes

- Redesign `48e682c` revisionato dal root: ripiano entro la misura standard, richiudibile, drop centrato e fila orizzontale. Suite 1.447/1.447, test app 9/9 e preview native verificati; build firmata riavviata al PID 97319. I [ticket UI](issues/92-file-shelf-primary-and-clear.md) e [drag](issues/91-file-shelf-native-drop-regression.md) restano aperti solo per la QA nativa descritta nel [verbale](../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md). Riserva settimanale 87%.

- Revisione UI/UX del 27 settembre: il [ticket 92](issues/92-file-shelf-primary-and-clear.md) segue il riferimento Musica e i principi Impeccable/Taste registrati in PRODUCT.md. Ripiano prioritario ma richiudibile, misura standard, top-band laterale e centro libero, drop centrato, ingresso centro→sinistra→ventaglio, elenco orizzontale senza pulsanti di azione e ritorno con freccia. Questa decisione sostituisce l'apertura permanente e Svuota nell'elenco descritti nello storico del 26 settembre. Il [ticket 91](issues/91-file-shelf-native-drop-regression.md) include la verifica del drop rapido prima dell'animazione.

- Nuova richiesta esplicita dell'utente: [rendere il ripiano la pagina principale e semplificarne le carte](issues/92-file-shelf-primary-and-clear.md) finché contiene file, con **Svuota** sotto Converti in mazzo ed elenco, originali intatti, sola icona e nome senza sfondo e animazioni conservate. Integrazione `5d852e7` revisionata, 7 test app firmati e suite 1.443/1.443 passati; resa nel notch reale e Svuota attendono prova utente. La [regressione del drag](issues/91-file-shelf-native-drop-regression.md) resta un ticket distinto.

- Prova utente successiva alla consegna parziale: le build `c43b7af` e `43e83eb` non acquisivano; Finder sottostante proponeva «Sostituisci». Nell'A/B temporaneo senza pin SkyLight, il PID 69502 ha ricevuto callback nativi e drop `accepted=true`; l'utente ha visto file nel ripiano e il manifest registra `entries=1`, `revision=3`. La [soluzione finale del drag](issues/91-file-shelf-native-drop-regression.md) `5d852e7` conserva pin visuale e aggiunge ricevitore nello Space attivo; review, test, build e riavvio PID 74874 verificati, nuovo drop ancora senza prova utente. Il conteggio dei file gestiti esclude gli originali esterni. Il selettore Ripiano/Attività è stato rimosso su richiesta. [La verifica finale](issues/90-file-shelf-local-delivery.md) rimane bloccata.

- Consegna locale parziale del 26 settembre 2026: [verifica finale del ripiano](issues/90-file-shelf-local-delivery.md) resta aperta e attende la correzione dell'acquisizione in ingresso. Build firmata, app aggiornata e riavvio PID 52683 verificati; suite SwiftPM 1.416/1.416 e test app 6/6 passati. QA Finder e del notch aperto non conclusa per errore ScreenCaptureKit `-3812` e mancata apertura ai click AX; non dedurre da queste prove drag reale, carte, persistenza UI o accessibilità. Conversione e promise in ingresso ancora indisponibili; launcher esterno bloccato.

- Decisione del 26 settembre 2026: l'utente autorizza il [ripiano file direttamente integrato](../../docs/superpowers/specs/2026-09-26-file-shelf-design.md#9-inserimento-in-cascade), come la pagina Musica, mentre il launcher addon esterno resta bloccato. Il [piano locale](../../docs/superpowers/plans/2026-09-26-local-file-shelf.md) e i relativi ticket fissano il primo incremento: drag-in con battito, mazzo animato quattro carte +N, elenco animato, persistenza, originali conservati, copia in uscita e rimozione per sola consegna riuscita. Il ripiano occupato è la pagina iniziale predefinita senza impedire la navigazione manuale. Conversione differita fino a supervisione, annullamento e recupero; nessuna UI la dichiara disponibile in anticipo. Eccezione circoscritta al ripiano, senza codice addon esterno nel processo host né modifiche a grant, quote o gate nativo.

- Tranche ripiano file del 26 settembre 2026: l’utente chiede di mappare tutti i task residui del [piano approvato](../../docs/superpowers/plans/2026-09-26-file-shelf.md) ed eseguirli in più ticket consecutivi con subagenti, GPT-6 Sol per task semplici e GPT-5.6 Sol per task complessi, revisione obbligatoria del root e riserva settimanale almeno 80%. Questa autorizzazione è prioritaria sulle soglie e sui modelli storici delle tranche precedenti per il solo ripiano file. Il [percorso interno già verificato](../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md) non qualifica il montaggio nativo: launcher e gate restano bloccati, senza bypass. I task di persistenza, presentazione e bundle FFmpeg possono avanzare indipendentemente dalla qualifica nativa. Il routing del ripiano segue la specifica approvata; [l’arbitraggio generale fra attività, pagine e contesti](issues/08-context-arbitration.md) resta una decisione distinta e aperta.

- Prosecuzione esplicita del 25 settembre 2026: mappare e implementare il notch multi-display secondo il piano del 24 settembre con subagenti, test e revisione. Questa tranche è autorizzata oltre i limiti storici delle tranche addon e ammette più ticket esecutivi consecutivi. Le proposte della specifica diventano impostazioni iniziali reversibili; focus finestra attiva confermato. Nessuna modifica al launcher addon. Modello complesso GPT-5.6 Sol; modello semplice in chiarimento perché «GPT-6 Sol» non è disponibile.

- Prosecuzione corrente del 20 settembre: Wayfinder esclusivamente per il sistema addon; ticket esecutivi consecutivi affidati a Sol medium o Terra secondo difficoltà, con revisione del root e correzioni prima della chiusura. Fermarsi a una nuova scelta progettuale necessaria oppure sotto il 75% di budget settimanale disponibile (oltre il 25% consumato). Questa soglia sostituisce il precedente tetto 20%; launcher bloccato e garanzie native invariati. Nessun lavoro sui ticket di altri sottosistemi.

- Prosecuzione del20settembre, istruzione ribadita: lavorare su più ticket esecutivi consecutivi nella stessa sessione; fermarsi soltanto a una decisione progettuale necessaria o al margine del tetto settimanale20%. Il limite storico di un ticket decisionale non limita gli incrementi esecutivi autorizzati.

- Prosecuzione del20settembre: più incrementi ammessi fino a una decisione progettuale necessaria o al tetto20% settimanale, conservando il margine operativo. Decisione ricevuta: [mantenere il launcher bloccato e la garanzia di uscita integrale](issues/22-managed-process-exit-proof.md). Scelta di policy risolta; prova tecnica ancora aperta, nessuna eccezione e nessun ticket chiuso. Il termine alle00:00 riportato sotto appartiene alla precedente esecuzione del18settembre.

- Ripresa del19settembre: continuare con Ponytail, modelli Sol medium/Terra secondo difficoltà e valutazione del root prima di ogni seguito. Nuovo limite20% settimanale Codex, che sostituisce per questa ripresa la precedente deroga senza riserva. Un solo incremento circoscritto alla volta; requisiti e gate nativi invariati.


- Termine della prosecuzione corrente imposto dall’utente: fermare il lavoro alle 00:00 italiane del 19 settembre 2026 (18 settembre,22:00 UTC), oppure prima se arriva il limite Codex. Il termine riguarda anche gli agenti; non chiude automaticamente i ticket incompleti.

- Prosecuzione esecutiva autorizzata il 18 settembre: dopo il completamento asset, l’utente chiede di continuare le tranche residue del piano addon fino al limite Codex, esclusivamente con agenti Codex e senza la riserva35%. Le tranche implementative successive possono essere tracciate qui; la precedente eccezione limitata agli asset è estesa da questa istruzione. Ogni consegna richiede prove e revisione; questa autorizzazione non converte limiti di piattaforma in garanzie né accetta nuovi rischi. Pubblicazione esterna e rilassamento dei requisiti nativi restano separati.

- Per impostazione predefinita questa mappa indicizza le decisioni; le implementazioni e le verifiche sono nel [piano addon corrente](../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md). Il riallineamento del 14 settembre conserva la destinazione globale.
- Eccezione esecutiva circoscritta del 15 settembre, per la richiesta di continuare con astra-pipeline in pi: il task «Collegare i messaggi asset al runtime e al client SDK» porta l'esecuzione nella mappa e termina soltanto con implementazione e valutazione indipendente superate. Routing aggiornato su richiesta esplicita del 18 settembre: solo Codex, con 5.6 Sol medium o altri modelli secondo difficoltà; revisione indipendente in sola lettura. La precedente pipeline DeepSeek resta documentata come storico. Non chiude né riapre le altre decisioni e non abilita launcher, C0d, scene remote o release.
- L’architettura addon approvata e i contratti successivi sono contestualizzati in [Definire i contratti di widget e Live Activity](issues/06-public-contract.md); i ticket globali restano aperti dove mancano prove o scelte residue.
- Requisiti e ricognizione iniziale: [Base del progetto](../../docs/wayfinder/context/project-baseline.md). Le risposte dell'utente nell'avvio sono vincoli d'ingresso, non ticket risolti artificialmente.
- Lingua: italiano. Preferire contratti piccoli, risorse contenute e nessun lavoro bloccante sul thread principale.
- Consultare wayfinder, grilling e domain-modeling; research per i ticket di ricerca e prototype per i prototipi. Skill complementari consultabili dalle fonti in [Guida alla mappa](../../docs/wayfinder/README.md).
- Per la UI consultare impeccable quando si affronta un prototipo. Nessun prototipo è autorizzato a trasformarsi implicitamente in implementazione.
- Tracker: [convenzioni locali](../../docs/agents/issue-tracker.md). Le questioni aperte si trovano interrogando i figli; non sono duplicate qui.
- Chiudere al massimo un ticket decisionale per sessione di avanzamento; le ricerche sono l'eccezione. La sessione iniziale ha tracciato la mappa e risolto solo ricerche. Gli avanzamenti successivi sono registrati nei ticket senza chiudere prove non eseguite.
- Le altre funzioni di Sapphire sono riferimenti da valutare, non requisiti automatici.

## Decisions so far

- [Comporre la pagina locale e il drag in uscita per elemento](issues/89-file-shelf-local-composition.md): integrazione app e consegna per voce accettate dopo review root e 6 test app firmati; build finale, riavvio e QA nativa nel ticket di consegna.

- [Instradare il ripiano locale e riconoscere il drag in ingresso](issues/88-file-shelf-local-routing.md): pagina contestuale e preview drag accettate dopo review root e 71 test mirati; composizione e QA nativa restano successive.

- [Preparare l'host locale e le copie verificate del ripiano](issues/87-file-shelf-local-host.md): facade e consegna verificata per voce accettate dopo review root e 73 test indipendenti; pagina e drag nativi seguono nel ticket successivo, senza attivazione addon.

- [Preparare formati e avanzamento della conversione](issues/86-file-workspace-conversion-planning.md): parser e preset interni limitati e revisionati, 64 test passati; esecuzione e recupero dei job restano separati.

- [Preparare FFmpeg e ffprobe verificati nel bundle](issues/81-file-workspace-ffmpeg-bundle.md): sorgenti autenticati, helper arm64 firmati e conversione reale verificati; nessuna attivazione nativa.

- [Aggiungere il componente condiviso e la lista animata del ripiano](issues/80-file-workspace-presentation.md): schema 3 e renderer condiviso revisionati, 86 test mirati e preview native locali; montaggio nel notch distinto.

- [Persistire voci e ricevute del ripiano file](issues/78-file-workspace-persistence.md): conservazione e consegne per elemento implementate e revisionate, con 50 test mirati passati; integrazione nativa separata.

- [Definire raccolta e durata dei file nel ripiano](issues/10-file-shelf.md): specifica approvata per acquisizione al drop, originali conservati, riferimenti persistenti e consegna verificata per elemento; arbitraggio generale dei contesti distinto.

- [Contratti e confine autorizzato del ripiano file](issues/76-file-workspace-contracts.md): modelli pubblici, client SDK e autorità host interni verificati da 21 test mirati e review; qualifica nativa separata.

- [Seguire la finestra attiva con fallback al puntatore](issues/70-focused-display.md): resolver e monitor a eventi implementati; 11 test e revisione PASS, integrazione successiva.

- [Persistenza dei display e modalità delle Live Activities](issues/69-display-identity-routing.md): identità, preferenze e inventario logico implementati; 13 test e revisione corretta, wiring successivo.

- [Definire monitor, focus e interazioni del notch](issues/14-displays-input.md): presenza permanente, apertura esclusiva, due stili software e tre destinazioni delle attività; focus finestra attiva con fallback puntatore.

- [Disegnare stati e superfici del notch](issues/07-notch-surfaces.md): contratti visivi consolidati e Spotlight nativo confermato; verifica locale di focus, calcolo e ripristino, con qualifica generale ancora distinta.

- [Definire compatibilità macOS e integrazioni ammesse](issues/04-platform-policy.md): approvato il percorso pubblico predefinito con eccezioni private singolarmente decise; minimo di progetto14 conservato, qualifica distinta.

- [Caricare widget SwiftUI esterni: meccanismi e limiti](issues/01-swiftui-extensions.md): bundle in processo e UI remota ExtensionKit sono percorsi distinti; formato, compatibilità e installazione richiedono una scelta e una prova.
- [Integrare Spotlight, notifiche e attività di macOS: fattibilità](issues/02-macos-integrations.md): personalizzazione di Spotlight e notifiche universali non hanno un contratto pubblico verificato; media, audio, Bluetooth e ActivityKit vanno trattati come capacità distinte.
- [Valutare glass e audio dai sorgenti di Sapphire e FineTune](issues/03-sapphire-finetune.md): renderer e motore audio sono individuati; versioni minime, API interne e comportamento a runtime vanno distinti dai requisiti di Cascade.

- [Scegliere il trasferimento delle immagini tra addon e host](issues/21-asset-transfer.md): approvati blocchi da 64 KiB tramite messaggi.

- [Collegare i messaggi asset al runtime e al client SDK](issues/23-asset-message-integration.md): percorso interno import/share/release implementato e revisionato, 883 test passati e consegna firmata verificata; trasporto nativo e C0d restano separati.

- [Generare un progetto addon SDK compilabile](issues/24-sdk-source-scaffold.md): generatore sorgente revisionato, build indipendente e896 test passati; consegna firmata e riavvio verificati.

- [Osservare le risorse di un processo senza abilitare il launcher](issues/25-process-resource-observations.md): lettore e riduttore revisionati, 929 test passati e consegna verificata; enforcement nativo ancora separato.

- [Creare l’esempio Focus con il solo SDK pubblico](issues/26-standalone-focus-source.md): libreria indipendente revisionata, 37 test passati e build esterna; contenitore e parità nativi restano da qualificare.

- [Mostrare il consumo di un servizio tramite SDK pubblico](issues/27-service-consumer-source.md): coppia sorgente sintetica revisionata, build indipendente e 16 test passati; nessuna disponibilità di un servizio reale o autorità nativa dedotta.

- [Collegare il client storage SDK al percorso a messaggi](issues/28-storage-message-client.md): client concreto revisionato, 955 test / 87 suite, esempi aggiornati e consegna firmata verificata.

- [Gestire il ciclo SDK delle invocazioni ai servizi](issues/29-service-invocation-lifecycle.md): correlazione e incertezza revisionate con bridge canonico, 978 test / 89 suite e consegna firmata verificata.

- [Definire e implementare i messaggi dedicati alle invocazioni dei servizi](issues/30-service-invocation-frames.md): codec limitati revisionati, 990 test / 90 suite e consegna firmata; nessuna attivazione del protocollo.

- [Verificare indipendentemente le unità delle metriche CPU](issues/32-process-cpu-calibration.md): confronto POSIX su copie esatte del lettore/riduttore revisionato PASS, limitato a macOS27 arm64/self-process.

- [Collegare le invocazioni dei servizi al runtime e allo scambio SDK](issues/31-service-invocation-host.md): percorso interno revisionato, 1034 test / 93 suite e consegna firmata con riavvio verificato; client completo e native separati.

- [Definire i messaggi di controllo e aggiornamento dei servizi](issues/33-service-subscription-frames.md): contratti chiusi revisionati, 1048 test / 94 suite e consegna firmata; nessuna attivazione1.4.

- [Documentare compatibilità, prestazioni e distribuzione degli addon](issues/36-addon-developer-guides.md): tre guide collegate, fonti verificate e revisione indipendente PASS; qualifiche native distinte.

- [Verificare i confini pubblici dell’SDK e degli esempi](issues/35-sdk-boundary-check.md): controllo sorgente consegnato,20 test e revisione PASS; audit originario3 package/9 target/88 sorgenti/132 import, ampliato con StandaloneClock nel successivo incremento.

- [Verificare le dipendenze reali dei manifest ServiceConsumer](issues/38-service-consumer-manifest-resolution.md):7 test/8 casi col resolver reale e revisione PASS; prova sorgente distinta dalla parità nativa.

- [Completare client servizi, sottoscrizioni e aggiornamenti](issues/34-service-subscriptions-host-sdk.md): revisione finale PASS,1084 test/96 suite, Release e consegna firmata con riavvio verificato;1.4 solo per assembly completo, native aperto.

- [Eseguire il controllo SDK prima della build di sviluppo](issues/37-required-sdk-build-check.md): quattro fixture e revisione PASS; controllo obbligatorio3 package/9 target/88 sorgenti/132 import seguito da build firmata positiva e riavvio.

- [Verificare offline l’interruzione del bootstrap prima del tracing](issues/39-bootstrap-abort-offline.md):31 test e revisione PASS; modello e osservazioni soltanto sintetici, uscita fisica e gate nativo invariati.

- [Implementare il bootstrap C con interruzione prima del tracing](issues/40-bootstrap-abort-c.md): candidato compilato e check C con sanitizzatori PASS dopo revisione root; main POSIX non eseguito, gate nativo invariato.

- [Collegare il contatore remoto al canale autenticato del prototipo](issues/41-remote-scene-counter.md): logica locale e build firmata dei tre target verificate, con revisione root; attivazione e qualifica della scena restano separate.

- [Verificare e completare il ciclo del contatore nel provider](issues/42-counter-provider-lifecycle.md): difetto di terminalità riprodotto e corretto; callback reali verificate in memoria, build separata firmata; qualifica nativa distinta.
- [Verificare e completare il ciclo del ricevitore del contatore](issues/43-counter-host-lifecycle.md): difetto di terminalità riprodotto e corretto; callback reali verificate in memoria, build separata firmata; qualifica nativa distinta.

- [Preparare il provider Clock con il solo SDK pubblico](issues/44-standalone-clock-source.md): build indipendente,3 test Swift,21 test checker e5 fixture build PASS dopo revisione root; audit esteso a4 package, nessuna qualifica nativa.

- [Campionare insieme i processi addon attivi](issues/45-process-metrics-coordinator.md): coordinatore interno revisionato,47 test metriche e1.098 test completi PASS, build firmata e riavvio verificati; binding/enforcement nativi separati.

- [Chiarire come il burst CPU consuma il budget addon](issues/46-addon-cpu-burst-policy.md): approvato credito condiviso 100 ms con ricarica 5 ms/s, conservato fra job e riavvii del provider, al posto della finestra mobile rigida.

- [Implementare il credito CPU condiviso dell’addon](issues/47-addon-cpu-credit.md): conto interno con ricarica monotona, debito conservato e 12 test; collegamento osservativo separato.

- [Collegare il credito CPU alle osservazioni comuni](issues/48-addon-cpu-accounting.md): conti condivisi e conservati nel coordinatore, misure incomplete distinte e fallimenti persistenti; revisioni PASS, 71 test mirati e 1.122 test completi.

- [Definire quando gli sforamenti CPU diventano violazioni distinte](issues/49-addon-cpu-violation-counting.md): approvato il conteggio del nuovo consumo oltre credito, una volta per addon e giro; debito residuo senza nuovo consumo escluso.

- [Classificare il nuovo consumo CPU oltre credito](issues/50-addon-cpu-violation-classification.md): classificazione per owner e giro, debito inattivo escluso e dati parziali espliciti; revisioni PASS e 76 test mirati.

- [Collegare gli sforamenti CPU alla salute del runtime](issues/51-addon-runtime-cpu-health.md): composizione interna con sessioni per incarnazione, cronologia conservata e cleanup comune; revisioni PASS, 100 test mirati e 1.135 test completi. Riduzione delle nuove ammissioni da definire.

- [Definire la riduzione dei nuovi lavori dopo uno sforamento CPU](issues/52-addon-cpu-reduced-admission.md): approvato rifiuto immediato fino a credito positivo provato da misure complete, senza nuova coda/replay; lavoro già ammesso conservato.

- [Applicare il rifiuto temporaneo dei nuovi lavori addon](issues/53-addon-cpu-admission.md): nuove ammissioni bloccate fino a credito positivo misurato, lavoro già ammesso e sorgenti attive preservati; revisioni PASS e191 test mirati.

- [Collegare le misure addon alla scadenza comune](issues/54-addon-metrics-deadline.md): quinto aggregato senza timer, wake coalescente e letture obsolete protette; revisioni PASS,118 test mirati e1.153 test completi/104 suite.

- [Definire l’attribuzione CPU dei servizi ai consumatori](issues/55-addon-delegated-cpu-attribution.md): scelta conservativa approvata; intervallo integrale a ciascun consumatore attivo, processo contato una sola volta nel totale fisico.

- [Addebitare gli intervalli CPU ai consumatori verificati](issues/56-addon-delegated-cpu-accounting.md): coordinatore esteso senza conti o misure duplicate, preflight atomico e debito persistente; revisioni PASS,126 test mirati e1.161 completi/105 suite. Producer canonico ancora separato.

- [Decidere l’attribuzione CPU nelle catene di servizi](issues/57-addon-transitive-cpu-attribution.md): propagazione conservativa approvata lungo interessi contemporaneamente attivi, deduplicata per identità e processo; niente dipendenze statiche inutilizzate.

- [Conservare i destinatari CPU delle catene attive](issues/58-addon-cpu-attribution-ledger.md): registro temporale limitato revisionato,9 test nuovi e29 mirati PASS; deduplicazione e assenza di catene fantasma verificate.

- [Collegare il registro delle catene alle misure CPU](issues/59-addon-coordinator-attribution-ledger.md): preflight del dominio, osservazioni sincronizzate e provenienza per processo; revisioni senza rilievi e49 test mirati PASS.

- [Collegare gli interessi canonici alla contabilità CPU](issues/60-addon-broker-attribution-ledger.md): commit/rimozioni collegati al registro, conservazione oltre disconnect/exit e pausa dei soli interessi nuovi;39 test mirati PASS, revisioni senza rilievi.

- [Preparare domanda e ticket per i retry dopo crash](issues/62-addon-crash-retry-projections.md): proiezioni/cancellazione limitate e domanda canonica revisionate,4 test dedicati PASS; nessun rilancio autonomo ancora collegato.

- [Applicare la CPU delegata alle ammissioni e alla salute addon](issues/61-addon-runtime-transitive-cpu.md): integrazione interna revisionata, ack v1.4 preservato,1.195 test/112 suite PASS; consegna finale della tranche firmata e avvio aggiornato verificati.

- [Collegare i retry dopo crash alla scadenza comune](issues/63-addon-runtime-crash-retry.md): composizione interna1/5/30secondi con domanda corrente e consumo monouso, revisioni PASS e1.209 test/113 suite; launcher invariato.

- [Definire a chi attribuire la memoria osservata dei servizi](issues/64-addon-memory-attribution.md): il footprint osservato appartiene soltanto al proprietario del processo fisico e non ai consumer diretti o transitivi; soglie, episodi e azioni del solo provider sono definiti dal ticket65; UI e gate nativo restano separati.

- [Definire soglie e incidenti RAM dei provider](issues/65-addon-provider-memory-policy.md): profilo progressivo64/96MiB approvato, implementato e verificato nei ticket66/67; launcher bloccato.

- [Classificare gli episodi di memoria dei provider](issues/66-provider-memory-episodes.md): classificatore per incarnazione verificato, tre test e doppia revisione PASS; integrazione runtime verificata nel67.

- [Collegare memoria, salute e ammissioni dei provider](issues/67-runtime-provider-memory.md): composizione owner-only verificata, revisioni PASS,1.222 test/115 suite e consegna firmata; nessuna attivazione nativa.

- [Verificare la gestione della durata tramite launchd](issues/68-launchd-managed-lifetime-research.md): fonti e SDK non stabiliscono il vincolo richiesto; ricerca conclusa, prova nativa ancora bloccata senza modifica della policy.

- [Condividere selezione e ciclo di vita delle Live Activities](issues/71-shared-live-activity.md): selezioni indipendenti, attivazione condivisa per istanza e revoca delle copie terminate verificate.

- [Mantenere i pannelli e arbitrare una sola apertura](issues/72-persistent-display-panels.md): superfici persistenti, un solo proprietario e interazioni ausiliarie arbitrate; revisione e prove mirate superate.

- [Disegnare Notch software e Dynamic Island a goccia](issues/73-software-notch-geometry.md): sagome, transizioni e contesti verificati; revisione PASS e confronto del renderer approvato.

- [Collegare preferenze display e superfici ausiliarie](issues/74-display-settings.md): preferenze native, ancore contestuali e riserve Spotlight integrate; revisione positiva, verifica completa di consegna separata.

- [Verificare e consegnare il notch multi-display](issues/75-multi-display-verification.md): revisione trasversale positiva, build firmata e riavvio verificati; esiti dei test e limiti nativi registrati nel verbale.

## Not yet specified

- Dettagli delle migrazioni di dati e preferenze dei futuri moduli: gli schemi applicativi si precisano quando saranno definiti i moduli e i loro consumatori reali. La persistenza addon già scelta non va riaperta qui.
- Combinazioni eccezionali di capacità e permessi delle future estensioni, da far emergere durante le prove di integrazione e la definizione dei moduli.

## Out of scope

- Pubblicazione esterna dell’app o dell’SDK e creazione di una release Homebrew senza il relativo incarico; le tranche locali del piano addon sono ammesse dalla prosecuzione nelle Notes.
- Parità indiscriminata con tutte le funzioni di Sapphire o FineTune: oltre alle funzioni richieste, ogni aggiunta richiede una scelta esplicita.

## Commenti

- 15 settembre 2026 — La valutazione Astra di [Collegare i messaggi asset al runtime e al client SDK](issues/23-asset-message-integration.md) è PARTIAL. Pipeline in pausa su richiesta dell'utente dopo il primo worker correttivo; il ticket conserva evidenze, limiti e punto di ripresa. Nessuna decisione o qualifica globale è chiusa da questo avanzamento.
- 15 settembre 2026, ripresa — L'utente ha nuovamente autorizzato la prosecuzione del task [Collegare i messaggi asset al runtime e al client SDK](issues/23-asset-message-integration.md), con riserva GPT del 35% e credito DeepSeek disponibile. Si riparte dal checkpoint, senza riaprire scelte già risolte.
- 15 settembre 2026, arresto budget — [Collegare i messaggi asset al runtime e al client SDK](issues/23-asset-message-integration.md) è sospeso alla riserva GPT del 35%. Ultima valutazione PARTIAL; il ticket collega checkpoint e dettagli del worker interrotto. Nessun subagent attivo e nessuna consegna approvata.

- 17 settembre 2026 — Ripresa di [Collegare i messaggi asset al runtime e al client SDK](issues/23-asset-message-integration.md) autorizzata con deroga esplicita alla riserva GPT del 35%; resta richiesta la valutazione indipendente prima della consegna.

- 18 settembre 2026 — Per [Collegare i messaggi asset al runtime e al client SDK](issues/23-asset-message-integration.md), l’utente sostituisce la pipeline DeepSeek con agenti Codex scelti secondo difficoltà; deroga 35% attiva, criteri tecnici invariati.
