# Frontiera delle decisioni di Cascade

Aggiornata al 26 settembre 2026 e derivata dai metadati dei ticket. La [mappa](../../.scratch/cascade-product/map.md) resta canonica; questa vista non conserva le risoluzioni.

85 ticket: 64 risolti, 1 in corso, 5 disponibili, 15 bloccati.

Decisione del20settembre: l’utente mantiene il launcher bloccato e il requisito integrale di uscita dei processi gestiti. La [scelta è registrata](../../.scratch/cascade-product/issues/22-managed-process-exit-proof.md); resta aperta la prova tecnica, senza nuova richiesta della stessa eccezione.


Nel checkpoint del 20 settembre sono concluse le decisioni sulle superfici e la verifica nativa locale di Spotlight/impostazioni: campo e calcolo nativi, focus e ripristino osservati. Toggle riportato disattivato, launcher bloccato, ultimo riavvio verificato PID10620. [Esiti e limiti](../superpowers/verification/2026-09-20-spotlight-native-continuation.md). Resta aperto [l’arbitraggio generale fra attività, pagine e contesti](../../.scratch/cascade-product/issues/08-context-arbitration.md); il comportamento del ripiano segue la sua specifica approvata.

## Decisioni e task disponibili

La decisione di conservazione e il routing limitato al ripiano sono fissati dalla specifica approvata; la precedenza generale tra attività e contesti rimane aperta. Il launcher resta bloccato. Persistenza e componente condiviso sono conclusi, il bundle FFmpeg è in corso; la qualifica nativa attende le prove di piattaforma.

- [Decidere priorità tra attività, pagine e contesto](../../.scratch/cascade-product/issues/08-context-arbitration.md)
- [Definire il collegamento tra Spotlight e notch](../../.scratch/cascade-product/issues/12-spotlight-experience.md)
- [Provare una UI SwiftUI esterna dentro il notch](../../.scratch/cascade-product/issues/19-extension-host-probe.md)
- [Provare routing per app e output simultanei](../../.scratch/cascade-product/issues/20-audio-routing-probe.md)
- [Definire una prova sicura di uscita dei processi gestiti](../../.scratch/cascade-product/issues/22-managed-process-exit-proof.md)

«Disponibile» significa che il ticket può essere preso in carico. Le prove dei processi gestiti e della scena SwiftUI restano distinte; nessuna disponibilità apre il gate nativo.

## Tranche file-shelf mappata

In corso: [Preparare FFmpeg e ffprobe verificati nel bundle](../../.scratch/cascade-product/issues/81-file-workspace-ffmpeg-bundle.md), assegnato a codex/file-shelf.

[Piano approvato](../superpowers/plans/2026-09-26-file-shelf.md): confine interno del servizio completato; persistenza e presentazione completate, bundle FFmpeg in corso. Drag reale, conversioni, composizione e verifica integrata seguono il DAG nella tabella. La [verifica runtime](../superpowers/verification/2026-09-26-file-workspace-runtime.md) non qualifica il percorso produttivo.

## Tranche multi-display conclusa

[Piano del notch multi-display](../superpowers/plans/2026-09-24-multi-display-notch.md): tutti i sette ticket esecutivi della tranche sono risolti; build e riavvio della consegna sono registrati nel ticket finale.

## Ricerca addon precedente

[Gestione della durata tramite launchd](research/2026-09-23-launchd-managed-lifetime.md): ricerca Sol medium e revisione root concluse. Non stabilisce il vincolo di uscita già richiesto; nessun codice o gate modificato. Riavvio della build invariata verificato PID22870, quota residua77%.

## Consegne addon precedenti

[RAM dei provider](../superpowers/verification/2026-09-23-addon-provider-memory.md): Terra/Sol medium, revisioni root e indipendenti PASS,1.222 test/115 suite, build firmata da500 input e avvio aggiornato PID21839 verificato; app già chiusa. Quota residua77%. Seguono soltanto attività dipendenti dalle prove native sospese; launcher bloccato.


[CPU transitiva e recupero dopo crash](../superpowers/verification/2026-09-22-addon-transitive-cpu.md): sei incrementi esecutivi con Sol/Terra medium, revisioni root e indipendenti PASS.1.209 test/113 suite, build ufficiale firmata da497 input verificati e avvio aggiornato PID62002; app già chiusa prima della consegna. Quota residua79%. Prossima scelta: attribuzione RAM; launcher bloccato.

[Contabilità CPU delegata](../superpowers/verification/2026-09-22-addon-delegated-cpu.md): formula conservativa approvata e coordinatore implementato daSol medium, revisioni root/Sol indipendente PASS.126 test mirati,1.161 test completi/105 suite, build ufficiale firmata da488 input verificati e riavvio PID46952. Budget residuo86%. Il collegamento al broker attende [la scelta sulle catene di servizi](../../.scratch/cascade-product/issues/57-addon-transitive-cpu-attribution.md); launcher bloccato.

[Ammissione CPU e scadenze comuni](../superpowers/verification/2026-09-21-addon-cpu-admission.md): due ticket implementati con Sol/Terra medium e revisioni root/indipendenti PASS.1.153 test/104 suite, build ufficiale firmata da487 input verificati e avvio stabile PID42941; Cascade era già chiusa prima dell’avvio. Residuo settimanale87%. Prossima scelta: [attribuzione CPU dei servizi ai consumatori](../../.scratch/cascade-product/issues/55-addon-delegated-cpu-attribution.md). Launcher bloccato.

[Violazioni CPU e salute del runtime](../superpowers/verification/2026-09-21-addon-cpu-violations.md): 100 test mirati e 1.135 test package in 101 suite PASS, revisioni root e indipendenti, build ufficiale firmata e riavvio verificato PID 32112. Residuo settimanale 90%; prossimo punto: rifiuto e riapertura dei nuovi lavori dopo uno sforamento. Quarantena per ora interna, launcher bloccato.

[Credito CPU condiviso e collegamento osservativo](../superpowers/verification/2026-09-20-addon-cpu-credit.md): 71 test mirati, 1.122 test package in 99 suite, revisioni root e indipendenti PASS; build ufficiale firmata, link Applications aggiornato e riavvio verificato PID 25071. Budget residuo 92%; launcher bloccato e sanzioni non ancora collegate.

[Campionare insieme i processi addon attivi](../../.scratch/cascade-product/issues/45-process-metrics-coordinator.md):47 test metriche,1.098 test package/97 suite, revisione root e indipendente PASS; build ufficiale firmata e riavvio verificato. Il componente non abilita il launcher o l’enforcement.

[Preparare il provider Clock con il solo SDK pubblico](../../.scratch/cascade-product/issues/44-standalone-clock-source.md):3 test Swift,21 test checker,5 fixture build e revisione root PASS; audit4 package/11 target/90 sorgenti/140 import. Riavvio della build firmata esistente verificato. La successiva [scelta delle dimensioni native di Spotlight](context/2026-09-20-notch-surfaces-checkpoint.md) è stata approvata; resta la qualifica, senza riaprire il launcher.

[Client servizi completo e host sottoscrizioni](../../.scratch/cascade-product/issues/34-service-subscriptions-host-sdk.md):1084 test/96 suite e Release PASS, revisione finale, build Apple Development e riavvio PID85871 verificati. Il protocollo1.4 richiede l’assembly cumulativo completo; la qualifica nativa resta aperta.

[Controllo SDK obbligatorio nella build](../../.scratch/cascade-product/issues/37-required-sdk-build-check.md): quattro fixture e revisione PASS; la build consegnata controlla3 package/9 target/88 sorgenti/132 import prima di Xcode.

## Stato completo

| Decisione, ricerca o attività | Stato | Attende |
| --- | --- | --- |
| [Caricare widget SwiftUI esterni: meccanismi e limiti](../../.scratch/cascade-product/issues/01-swiftui-extensions.md) | Risolto | — |
| [Integrare Spotlight, notifiche e attività di macOS: fattibilità](../../.scratch/cascade-product/issues/02-macos-integrations.md) | Risolto | — |
| [Valutare glass e audio dai sorgenti di Sapphire e FineTune](../../.scratch/cascade-product/issues/03-sapphire-finetune.md) | Risolto | — |
| [Definire compatibilità macOS e integrazioni ammesse](../../.scratch/cascade-product/issues/04-platform-policy.md) | Risolto | — |
| [Definire installazione e isolamento delle estensioni](../../.scratch/cascade-product/issues/05-extension-distribution.md) | Bloccato | [Caricare widget SwiftUI esterni: meccanismi e limiti](../../.scratch/cascade-product/issues/01-swiftui-extensions.md); [Definire compatibilità macOS e integrazioni ammesse](../../.scratch/cascade-product/issues/04-platform-policy.md); [Provare una UI SwiftUI esterna dentro il notch](../../.scratch/cascade-product/issues/19-extension-host-probe.md); [Definire una prova sicura di uscita dei processi gestiti](../../.scratch/cascade-product/issues/22-managed-process-exit-proof.md) |
| [Definire i contratti di widget e Live Activity](../../.scratch/cascade-product/issues/06-public-contract.md) | Bloccato | [Definire installazione e isolamento delle estensioni](../../.scratch/cascade-product/issues/05-extension-distribution.md) |
| [Disegnare stati e superfici del notch](../../.scratch/cascade-product/issues/07-notch-surfaces.md) | Risolto | — |
| [Decidere priorità tra attività, pagine e contesto](../../.scratch/cascade-product/issues/08-context-arbitration.md) | Disponibile | — |
| [Definire griglia, pagine e personalizzazione dei widget](../../.scratch/cascade-product/issues/09-grid-pages.md) | Bloccato | [Definire i contratti di widget e Live Activity](../../.scratch/cascade-product/issues/06-public-contract.md); [Disegnare stati e superfici del notch](../../.scratch/cascade-product/issues/07-notch-surfaces.md) |
| [Definire raccolta e durata dei file nel ripiano](../../.scratch/cascade-product/issues/10-file-shelf.md) | Risolto | — |
| [Definire notifiche di altre app e avvisi dei dispositivi](../../.scratch/cascade-product/issues/11-notification-experience.md) | Bloccato | [Integrare Spotlight, notifiche e attività di macOS: fattibilità](../../.scratch/cascade-product/issues/02-macos-integrations.md); [Definire compatibilità macOS e integrazioni ammesse](../../.scratch/cascade-product/issues/04-platform-policy.md); [Decidere priorità tra attività, pagine e contesto](../../.scratch/cascade-product/issues/08-context-arbitration.md) |
| [Definire il collegamento tra Spotlight e notch](../../.scratch/cascade-product/issues/12-spotlight-experience.md) | Disponibile | — |
| [Definire il gestore audio contestuale](../../.scratch/cascade-product/issues/13-audio-experience.md) | Bloccato | [Valutare glass e audio dai sorgenti di Sapphire e FineTune](../../.scratch/cascade-product/issues/03-sapphire-finetune.md); [Definire compatibilità macOS e integrazioni ammesse](../../.scratch/cascade-product/issues/04-platform-policy.md); [Decidere priorità tra attività, pagine e contesto](../../.scratch/cascade-product/issues/08-context-arbitration.md); [Provare routing per app e output simultanei](../../.scratch/cascade-product/issues/20-audio-routing-probe.md) |
| [Definire monitor, focus e interazioni del notch](../../.scratch/cascade-product/issues/14-displays-input.md) | Risolto | — |
| [Disegnare impostazioni e gestione delle integrazioni](../../.scratch/cascade-product/issues/15-settings-experience.md) | Bloccato | [Definire installazione e isolamento delle estensioni](../../.scratch/cascade-product/issues/05-extension-distribution.md); [Definire griglia, pagine e personalizzazione dei widget](../../.scratch/cascade-product/issues/09-grid-pages.md); [Definire raccolta e durata dei file nel ripiano](../../.scratch/cascade-product/issues/10-file-shelf.md); [Definire notifiche di altre app e avvisi dei dispositivi](../../.scratch/cascade-product/issues/11-notification-experience.md); [Definire il collegamento tra Spotlight e notch](../../.scratch/cascade-product/issues/12-spotlight-experience.md); [Definire il gestore audio contestuale](../../.scratch/cascade-product/issues/13-audio-experience.md); [Definire monitor, focus e interazioni del notch](../../.scratch/cascade-product/issues/14-displays-input.md) |
| [Definire budget, isolamento e recupero dai guasti](../../.scratch/cascade-product/issues/16-resource-contract.md) | Bloccato | [Definire installazione e isolamento delle estensioni](../../.scratch/cascade-product/issues/05-extension-distribution.md); [Definire i contratti di widget e Live Activity](../../.scratch/cascade-product/issues/06-public-contract.md); [Definire il gestore audio contestuale](../../.scratch/cascade-product/issues/13-audio-experience.md) |
| [Ordinare i rilasci e definire i criteri di completamento](../../.scratch/cascade-product/issues/17-delivery-roadmap.md) | Bloccato | [Definire i contratti di widget e Live Activity](../../.scratch/cascade-product/issues/06-public-contract.md); [Decidere priorità tra attività, pagine e contesto](../../.scratch/cascade-product/issues/08-context-arbitration.md); [Definire griglia, pagine e personalizzazione dei widget](../../.scratch/cascade-product/issues/09-grid-pages.md); [Definire raccolta e durata dei file nel ripiano](../../.scratch/cascade-product/issues/10-file-shelf.md); [Definire notifiche di altre app e avvisi dei dispositivi](../../.scratch/cascade-product/issues/11-notification-experience.md); [Definire il collegamento tra Spotlight e notch](../../.scratch/cascade-product/issues/12-spotlight-experience.md); [Definire il gestore audio contestuale](../../.scratch/cascade-product/issues/13-audio-experience.md); [Definire monitor, focus e interazioni del notch](../../.scratch/cascade-product/issues/14-displays-input.md); [Disegnare impostazioni e gestione delle integrazioni](../../.scratch/cascade-product/issues/15-settings-experience.md); [Definire budget, isolamento e recupero dai guasti](../../.scratch/cascade-product/issues/16-resource-contract.md); [Definire Now Playing e le prime Live Activities](../../.scratch/cascade-product/issues/18-media-live-activities.md) |
| [Definire Now Playing e le prime Live Activities](../../.scratch/cascade-product/issues/18-media-live-activities.md) | Bloccato | [Integrare Spotlight, notifiche e attività di macOS: fattibilità](../../.scratch/cascade-product/issues/02-macos-integrations.md); [Definire compatibilità macOS e integrazioni ammesse](../../.scratch/cascade-product/issues/04-platform-policy.md); [Definire i contratti di widget e Live Activity](../../.scratch/cascade-product/issues/06-public-contract.md); [Decidere priorità tra attività, pagine e contesto](../../.scratch/cascade-product/issues/08-context-arbitration.md) |
| [Provare una UI SwiftUI esterna dentro il notch](../../.scratch/cascade-product/issues/19-extension-host-probe.md) | Disponibile | — |
| [Provare routing per app e output simultanei](../../.scratch/cascade-product/issues/20-audio-routing-probe.md) | Disponibile | — |
| [Scegliere il trasferimento delle immagini tra addon e host](../../.scratch/cascade-product/issues/21-asset-transfer.md) | Risolto | — |
| [Definire una prova sicura di uscita dei processi gestiti](../../.scratch/cascade-product/issues/22-managed-process-exit-proof.md) | Disponibile | — |
| [Collegare i messaggi asset al runtime e al client SDK](../../.scratch/cascade-product/issues/23-asset-message-integration.md) | Risolto | — |
| [Generare un progetto addon SDK compilabile](../../.scratch/cascade-product/issues/24-sdk-source-scaffold.md) | Risolto | — |
| [Osservare le risorse di un processo senza abilitare il launcher](../../.scratch/cascade-product/issues/25-process-resource-observations.md) | Risolto | — |
| [Creare l’esempio Focus con il solo SDK pubblico](../../.scratch/cascade-product/issues/26-standalone-focus-source.md) | Risolto | — |
| [Mostrare il consumo di un servizio tramite SDK pubblico](../../.scratch/cascade-product/issues/27-service-consumer-source.md) | Risolto | — |
| [Collegare il client storage SDK al percorso a messaggi](../../.scratch/cascade-product/issues/28-storage-message-client.md) | Risolto | — |
| [Gestire il ciclo SDK delle invocazioni ai servizi](../../.scratch/cascade-product/issues/29-service-invocation-lifecycle.md) | Risolto | — |
| [Definire e implementare i messaggi dedicati alle invocazioni dei servizi](../../.scratch/cascade-product/issues/30-service-invocation-frames.md) | Risolto | — |
| [Collegare le invocazioni dei servizi al runtime e allo scambio SDK](../../.scratch/cascade-product/issues/31-service-invocation-host.md) | Risolto | — |
| [Verificare indipendentemente le unità delle metriche CPU](../../.scratch/cascade-product/issues/32-process-cpu-calibration.md) | Risolto | — |
| [Definire i messaggi di controllo e aggiornamento dei servizi](../../.scratch/cascade-product/issues/33-service-subscription-frames.md) | Risolto | — |
| [Completare client servizi, sottoscrizioni e aggiornamenti](../../.scratch/cascade-product/issues/34-service-subscriptions-host-sdk.md) | Risolto | — |
| [Verificare i confini pubblici dell'SDK e degli esempi](../../.scratch/cascade-product/issues/35-sdk-boundary-check.md) | Risolto | — |
| [Documentare compatibilità, prestazioni e distribuzione degli addon](../../.scratch/cascade-product/issues/36-addon-developer-guides.md) | Risolto | — |
| [Eseguire il controllo SDK prima della build di sviluppo](../../.scratch/cascade-product/issues/37-required-sdk-build-check.md) | Risolto | — |
| [Verificare le dipendenze reali dei manifest ServiceConsumer](../../.scratch/cascade-product/issues/38-service-consumer-manifest-resolution.md) | Risolto | — |
| [Verificare offline l’interruzione del bootstrap prima del tracing](../../.scratch/cascade-product/issues/39-bootstrap-abort-offline.md) | Risolto | — |
| [Implementare il bootstrap C con interruzione prima del tracing](../../.scratch/cascade-product/issues/40-bootstrap-abort-c.md) | Risolto | — |
| [Collegare il contatore remoto al canale autenticato del prototipo](../../.scratch/cascade-product/issues/41-remote-scene-counter.md) | Risolto | — |
| [Verificare e completare il ciclo del contatore nel provider](../../.scratch/cascade-product/issues/42-counter-provider-lifecycle.md) | Risolto | — |
| [Verificare e completare il ciclo del ricevitore del contatore](../../.scratch/cascade-product/issues/43-counter-host-lifecycle.md) | Risolto | — |
| [Preparare il provider Clock con il solo SDK pubblico](../../.scratch/cascade-product/issues/44-standalone-clock-source.md) | Risolto | — |
| [Campionare insieme i processi addon attivi](../../.scratch/cascade-product/issues/45-process-metrics-coordinator.md) | Risolto | — |
| [Chiarire come il burst CPU consuma il budget addon](../../.scratch/cascade-product/issues/46-addon-cpu-burst-policy.md) | Risolto | — |
| [Implementare il credito CPU condiviso dell’addon](../../.scratch/cascade-product/issues/47-addon-cpu-credit.md) | Risolto | — |
| [Collegare il credito CPU alle osservazioni comuni](../../.scratch/cascade-product/issues/48-addon-cpu-accounting.md) | Risolto | — |
| [Definire quando gli sforamenti CPU diventano violazioni distinte](../../.scratch/cascade-product/issues/49-addon-cpu-violation-counting.md) | Risolto | — |
| [Classificare il nuovo consumo CPU oltre credito](../../.scratch/cascade-product/issues/50-addon-cpu-violation-classification.md) | Risolto | — |
| [Collegare gli sforamenti CPU alla salute del runtime](../../.scratch/cascade-product/issues/51-addon-runtime-cpu-health.md) | Risolto | — |
| [Definire la riduzione dei nuovi lavori dopo uno sforamento CPU](../../.scratch/cascade-product/issues/52-addon-cpu-reduced-admission.md) | Risolto | — |
| [Applicare il rifiuto temporaneo dei nuovi lavori addon](../../.scratch/cascade-product/issues/53-addon-cpu-admission.md) | Risolto | — |
| [Collegare le misure addon alla scadenza comune](../../.scratch/cascade-product/issues/54-addon-metrics-deadline.md) | Risolto | — |
| [Definire l’attribuzione CPU dei servizi ai consumatori](../../.scratch/cascade-product/issues/55-addon-delegated-cpu-attribution.md) | Risolto | — |
| [Addebitare gli intervalli CPU ai consumatori verificati](../../.scratch/cascade-product/issues/56-addon-delegated-cpu-accounting.md) | Risolto | — |
| [Decidere l’attribuzione CPU nelle catene di servizi](../../.scratch/cascade-product/issues/57-addon-transitive-cpu-attribution.md) | Risolto | — |
| [Conservare i destinatari CPU delle catene attive](../../.scratch/cascade-product/issues/58-addon-cpu-attribution-ledger.md) | Risolto | — |
| [Collegare il registro delle catene alle misure CPU](../../.scratch/cascade-product/issues/59-addon-coordinator-attribution-ledger.md) | Risolto | — |
| [Collegare gli interessi canonici alla contabilità CPU](../../.scratch/cascade-product/issues/60-addon-broker-attribution-ledger.md) | Risolto | — |
| [Applicare la CPU delegata alle ammissioni e alla salute addon](../../.scratch/cascade-product/issues/61-addon-runtime-transitive-cpu.md) | Risolto | — |
| [Preparare domanda e ticket per i retry dopo crash](../../.scratch/cascade-product/issues/62-addon-crash-retry-projections.md) | Risolto | — |
| [Collegare i retry dopo crash alla scadenza comune](../../.scratch/cascade-product/issues/63-addon-runtime-crash-retry.md) | Risolto | — |
| [Definire a chi attribuire la memoria osservata dei servizi](../../.scratch/cascade-product/issues/64-addon-memory-attribution.md) | Risolto | — |
| [Definire soglie e incidenti RAM dei provider](../../.scratch/cascade-product/issues/65-addon-provider-memory-policy.md) | Risolto | — |
| [Classificare gli episodi di memoria dei provider](../../.scratch/cascade-product/issues/66-provider-memory-episodes.md) | Risolto | — |
| [Collegare memoria, salute e ammissioni dei provider](../../.scratch/cascade-product/issues/67-runtime-provider-memory.md) | Risolto | — |
| [Verificare la gestione della durata tramite launchd](../../.scratch/cascade-product/issues/68-launchd-managed-lifetime-research.md) | Risolto | — |
| [Persistenza dei display e modalità delle Live Activities](../../.scratch/cascade-product/issues/69-display-identity-routing.md) | Risolto | — |
| [Seguire la finestra attiva con fallback al puntatore](../../.scratch/cascade-product/issues/70-focused-display.md) | Risolto | — |
| [Condividere selezione e ciclo di vita delle Live Activities](../../.scratch/cascade-product/issues/71-shared-live-activity.md) | Risolto | — |
| [Mantenere i pannelli e arbitrare una sola apertura](../../.scratch/cascade-product/issues/72-persistent-display-panels.md) | Risolto | — |
| [Disegnare Notch software e Dynamic Island a goccia](../../.scratch/cascade-product/issues/73-software-notch-geometry.md) | Risolto | — |
| [Collegare preferenze display e superfici ausiliarie](../../.scratch/cascade-product/issues/74-display-settings.md) | Risolto | — |
| [Verificare e consegnare il notch multi-display](../../.scratch/cascade-product/issues/75-multi-display-verification.md) | Risolto | — |
| [Contratti e confine autorizzato del ripiano file](../../.scratch/cascade-product/issues/76-file-workspace-contracts.md) | Risolto | — |
| [Qualificare il percorso nativo del servizio files.workspace](../../.scratch/cascade-product/issues/77-file-workspace-native-path.md) | Bloccato | [Provare una UI SwiftUI esterna dentro il notch](../../.scratch/cascade-product/issues/19-extension-host-probe.md); [Definire una prova sicura di uscita dei processi gestiti](../../.scratch/cascade-product/issues/22-managed-process-exit-proof.md) |
| [Persistire voci e ricevute del ripiano file](../../.scratch/cascade-product/issues/78-file-workspace-persistence.md) | Risolto | — |
| [Acquisire e consegnare file con drag nativo per elemento](../../.scratch/cascade-product/issues/79-file-workspace-native-drag.md) | Bloccato | [Qualificare il percorso nativo del servizio files.workspace](../../.scratch/cascade-product/issues/77-file-workspace-native-path.md); [Persistire voci e ricevute del ripiano file](../../.scratch/cascade-product/issues/78-file-workspace-persistence.md) |
| [Aggiungere il componente condiviso e la lista animata del ripiano](../../.scratch/cascade-product/issues/80-file-workspace-presentation.md) | Risolto | — |
| [Preparare FFmpeg e ffprobe verificati nel bundle](../../.scratch/cascade-product/issues/81-file-workspace-ffmpeg-bundle.md) | In corso | — |
| [Eseguire conversioni file in job recuperabili](../../.scratch/cascade-product/issues/82-file-workspace-conversion-jobs.md) | Bloccato | [Qualificare il percorso nativo del servizio files.workspace](../../.scratch/cascade-product/issues/77-file-workspace-native-path.md); [Persistire voci e ricevute del ripiano file](../../.scratch/cascade-product/issues/78-file-workspace-persistence.md); [Preparare FFmpeg e ffprobe verificati nel bundle](../../.scratch/cascade-product/issues/81-file-workspace-ffmpeg-bundle.md) |
| [Instradare il ripiano come pagina contestuale e battito del notch](../../.scratch/cascade-product/issues/83-file-workspace-routing.md) | Bloccato | [Acquisire e consegnare file con drag nativo per elemento](../../.scratch/cascade-product/issues/79-file-workspace-native-drag.md); [Aggiungere il componente condiviso e la lista animata del ripiano](../../.scratch/cascade-product/issues/80-file-workspace-presentation.md) |
| [Comporre il provider del ripiano e i comandi di conversione](../../.scratch/cascade-product/issues/84-file-workspace-provider-composition.md) | Bloccato | [Qualificare il percorso nativo del servizio files.workspace](../../.scratch/cascade-product/issues/77-file-workspace-native-path.md); [Aggiungere il componente condiviso e la lista animata del ripiano](../../.scratch/cascade-product/issues/80-file-workspace-presentation.md); [Eseguire conversioni file in job recuperabili](../../.scratch/cascade-product/issues/82-file-workspace-conversion-jobs.md); [Instradare il ripiano come pagina contestuale e battito del notch](../../.scratch/cascade-product/issues/83-file-workspace-routing.md) |
| [Verificare e consegnare il ripiano file integrato](../../.scratch/cascade-product/issues/85-file-workspace-integration.md) | Bloccato | [Persistire voci e ricevute del ripiano file](../../.scratch/cascade-product/issues/78-file-workspace-persistence.md); [Acquisire e consegnare file con drag nativo per elemento](../../.scratch/cascade-product/issues/79-file-workspace-native-drag.md); [Aggiungere il componente condiviso e la lista animata del ripiano](../../.scratch/cascade-product/issues/80-file-workspace-presentation.md); [Preparare FFmpeg e ffprobe verificati nel bundle](../../.scratch/cascade-product/issues/81-file-workspace-ffmpeg-bundle.md); [Eseguire conversioni file in job recuperabili](../../.scratch/cascade-product/issues/82-file-workspace-conversion-jobs.md); [Instradare il ripiano come pagina contestuale e battito del notch](../../.scratch/cascade-product/issues/83-file-workspace-routing.md); [Comporre il provider del ripiano e i comandi di conversione](../../.scratch/cascade-product/issues/84-file-workspace-provider-composition.md) |

## Collegamento al lavoro addon

Il [piano di completamento](../superpowers/plans/2026-09-10-addon-runtime-completion.md) conserva consegne, evidenze e attività esecutive. L’ultima [verifica SDK/runtime asset](../superpowers/verification/2026-09-18-addon-asset-message-integration.md) registra 883 test / 83 suite, revisione indipendente PASS, build firmata e riavvio aggiornato verificato; non qualifica il trasporto OS, launcher o addon esterni reali.

[Scegliere il trasferimento delle immagini tra addon e host](../../.scratch/cascade-product/issues/21-asset-transfer.md) è risolto dalla risposta dell’utente. Anche [Collegare i messaggi asset al runtime e al client SDK](../../.scratch/cascade-product/issues/23-asset-message-integration.md) è ora completato nel suo ambito interno. Gli altri ticket globali mantengono aperte le proprie domande residue.

Consegna precedente: [client completo, sottoscrizioni e build protetta](../superpowers/verification/2026-09-18-addon-service-subscriptions-host-sdk.md),1084 test/96 suite PASS, revisione, build firmata e riavvio verificato. [Controllo SDK obbligatorio](../superpowers/verification/2026-09-18-addon-required-sdk-build-check.md) e [matrice sorgente dei manifest](../superpowers/verification/2026-09-18-service-consumer-manifest-resolution.md) hanno prove distinte.

Restano launcher e trasporto autenticato, prova sicura di uscita dei processi, collegamento all’app, migrazioni, UI remota, catalogo/installazione e qualifica nativa. Il candidato C del bootstrap è compilato e verificato localmente; le questioni disponibili sopra rappresentano la frontiera corrente.

[Modello offline del bootstrap](../../.scratch/cascade-product/issues/39-bootstrap-abort-offline.md): completato con31 test e revisione PASS, senza esecuzione nativa o apertura del gate.

[Contatore della scena remota](../../.scratch/cascade-product/issues/41-remote-scene-counter.md): check locale, build Release e firme PASS dopo revisione root; nessuna attivazione nativa eseguita. La policy delle nuove integrazioni è ora risolta: pubblico predefinito, ogni nuova eccezione privata decisa singolarmente.
