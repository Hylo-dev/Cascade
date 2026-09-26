# Cascade — base per la mappa applicativa

Ricognizione del 4 settembre 2026. Questo documento raccoglie requisiti ricevuti e riscontri sul codice; non è ancora la mappa Wayfinder né una specifica approvata.

## Destinazione richiesta

Definire il piano globale di Cascade: un notch modulare per macOS, estendibile da altre app mediante un protocollo/SDK. La mappa dovrà chiarire prodotto, architettura, contratti, fattibilità delle integrazioni, dipendenze e ordine delle successive specifiche di implementazione.

## Requisiti espressi dall'utente

- Apertura in hover, con feedback aptico sul trackpad una volta aperto.
- Presentazione compatta estesa ai lati per attività in corso, ispirata alla Dynamic Island; anche le attività devono essere estendibili tramite protocollo.
- Allineamento al notch fisico; sui display senza notch deve sporgere leggermente.
- Due stili: nero e glass ispirato alla nuova Siri e a Sapphire.
- Prime integrazioni: musica e media del browser, notifiche e connessioni Bluetooth, ricerca dal notch, raccolta temporanea di file trascinati, gestione audio contestuale ispirata a FineTune.
- Pagine con widget di dimensioni differenti su una griglia; selezione anche in base al contesto.
- Impostazioni sotto il notch, con linguaggio visivo dei settings di macOS: aspetto, dimensioni anche per singolo display, attività attive e schermate contestuali.
- Sapphire è anche un riferimento funzionale; le sue altre funzioni non diventano automaticamente requisiti di Cascade.
- L'allegato è un riferimento visivo per la ricerca: campo superiore arrotondato e superficie dei risultati separata, scura e traslucida. Le voci e il microfono nell'immagine non sono da soli requisiti funzionali.
- Chiedere all'utente quando manca una scelta di prodotto; non sostituire le preferenze mancanti con assunzioni definitive.

## Stato del progetto riscontrato

| Area | Evidenza nel codice | Conseguenza per il piano |
| --- | --- | --- |
| Separazione app/motore | `Cascade` usa il package locale `CascadeKit` attraverso `NotchEngine`. | Conservare il confine pubblico esistente e valutare dove debba vivere l'SDK per app esterne. |
| Overlay e animazione | `NotchPanel`, `NotchController`, `DisplayLinkMorphEngine`, `NotchHostView`; geometria con molle e `CAShapeLayer`. | Esiste un motore da evolvere, non serve presumere una riscrittura. |
| Widget | `NotchWidget` espone identità, tipo, dimensione, `AnyView`, attivazione e sospensione; registrazione diretta di oggetti nel processo dell'host. | La modularità interna esiste; discovery, comunicazione tra processi e contratto per estensioni esterne non sono implementati. |
| Griglia e pagine | `GridSpan`, `WidgetPlacement`, `NotchLayoutResolver`, `NotchScreen`; `WidgetHost` usa una pagina e un indice interno. | Esistono modelli e posizionamento; navigazione tra pagine, editor, persistenza e selezione contestuale restano da definire. |
| Stato del notch | `NotchState` è un `OptionSet` per i lati leading/trailing; il morph interpola verso apertura/chiusura. | Non equivale ancora a un modello completo di attività compatte, espansione, notifiche e superfici che prendono il focus. |
| Input | `NotchPanel` ignora gli eventi mouse e non può diventare key/main; l'hover arriva da monitor degli eventi. | Click dei widget, drag-and-drop e digitazione nella ricerca richiedono un progetto esplicito di input e focus. |
| Display | Resolver basato sul puntatore; riposizionamento sul cambio di identificativo del display; configurazione unica. | Vanno decisi comportamento con più display e profili dimensionali per display. |
| Aspetto | Riempimento del renderer con un colore; l'app avvia la configurazione rossa di debug. | Glass e impostazioni dell'aspetto non sono implementati. |
| Impostazioni | La scena SwiftUI Settings contiene `EmptyView`. | L'interfaccia richiesta è da progettare. |
| Integrazioni | L'app registra il widget demo orologio; non risultano servizi musica, notifiche, Bluetooth, ricerca o audio mixer nei sorgenti esaminati. | Queste aree richiedono contratti e ricerche di fattibilità prima delle specifiche esecutive. |
| Compatibilità | Deployment target macOS 14; package con tools Swift 6.2; sandbox dell'app disabilitata. | Distinguere requisiti attuali, scelte future e disponibilità delle API per singola funzione. |
| Spaces | `SkyLightWindowPinner` carica simboli privati di SkyLight con fallback se non disponibili. | La strategia di distribuzione e compatibilità è una decisione iniziale. |
| Verifica | Test presenti per geometria, segmenti, molle, stato e layout; test app prevalentemente scaffold. | Non considerare già verificati lifecycle, interazioni, prestazioni o integrazioni. Nessuna build o test eseguiti in questa ricognizione. |

### Differenze rispetto alla documentazione precedente

`CLAUDE.md` descrive il notch invisibile sui display senza ritaglio fisico. La richiesta attuale prevede invece una piccola sporgenza e ha precedenza. Il default del codice segue ancora la descrizione precedente; la configurazione di debug mostra già il chrome ovunque.

Le regole sulle risorse dei widget restano un vincolo da incorporare nei contratti. La sospensione della UI non va confusa con la cessazione delle sorgenti di eventi necessarie alle attività compatte. Non è stato verificato che nascondere l'hosting view interrompa da solo ogni aggiornamento della vista demo.

## Chiarimenti dell'utente durante la definizione iniziale

Questi sono vincoli d'ingresso della mappa, raccolti prima di lavorare i suoi ticket decisionali.

1. **Distribuzione**: download diretto fuori dal Mac App Store, con supporto Homebrew.
2. **Estensioni**: preferenza per SwiftUI e moduli ottenibili tramite «import» o caricamento da cartella. Non è stata ancora scelta la forma tecnica: package compilato nell'host, bundle dinamico e sorgenti importati non sono equivalenti.
3. **Ricerca**: esperienza identica a Spotlight di sistema; preferenza per modificare quello vero se tecnicamente fattibile. La scelta tra integrazione di Spotlight e ricerca propria è subordinata alla ricerca, non ancora chiusa. Nessun assistente AI distinto è stato richiesto.
4. **Notifiche**: includere anche quelle delle altre app non integrate con Cascade.
5. **Audio iniziale**: volume e mute per app, routing per app e output multipli. L'equalizzazione non è stata selezionata come requisito iniziale.
6. **File**: presentare il ripiano durante il trascinamento e acquisire i file soltanto quando vengono rilasciati sul notch. Il tipo di conservazione e la durata rimangono da decidere.

Questi chiarimenti non approvano automaticamente tecniche private, carico di risorse, copia di codice esterno o limiti funzionali non ancora discussi.

## Altre domande già identificabili per la mappa

- Quali modalità compatte e quali attività sono comprese nella prima versione di «come la Dynamic Island»?
- Come si risolvono le priorità tra attività simultanee, notifiche, ricerca, scelta manuale di pagina e suggerimenti contestuali?
- Quando la raccolta file si presenta, quando acquisisce i file e quanto dura la conservazione? Riferimenti, copie, spostamenti e file promessi richiedono una decisione esplicita.
- Quale parte di FineTune è richiesta all'inizio: volume per app, routing per app, output multipli, equalizzazione?
- Come si registrano, autorizzano, aggiornano e rimuovono le estensioni, e cosa succede se l'app sorgente si chiude o smette di rispondere?
- Come convivono griglia, dimensioni supportate dal widget, dimensioni del notch e profili per display?
- Quali soglie misurabili di CPU, memoria, energia e latenza devono superare host, glass e moduli?
- Quali permessi servono alle funzioni richieste e quale comportamento deve rimanere disponibile quando sono negati?

## Riferimenti esterni consultati

- [Sapphire](https://github.com/cshariq/Sapphire): il README descrive Now Playing, audio per app, file shelf e avvisi Bluetooth, tra le altre funzioni. Va ancora analizzato il codice del trattamento glass; non viene dichiarata una corrispondenza visiva verificata.
- [FineTune](https://github.com/ronitsingh10/FineTune): il README descrive volume per app, routing, output multipli ed EQ e indica macOS 15 come minimo. Non implica che tutte queste funzioni debbano entrare nel primo rilascio di Cascade o che abbiano lo stesso requisito minimo se implementate separatamente.

## Stato degli strumenti di pianificazione

- Skill `wayfinder` letta da `/Users/c4v4h/.codex/skills/wayfinder/SKILL.md`.
- Nessun tracker specifico o documento delle operazioni Wayfinding trovato nel repository; la skill prevede il fallback local-markdown e indica `/setup-matt-pocock-skills` per il setup.
- Le skill complementari `grilling`, `domain-modeling`, `research` e il template local-markdown non erano installati: sono stati successivamente letti dal repository originale `mattpocock/skills`. Le fonti sono nella guida alla mappa; non è stata effettuata un'installazione globale.
- Il grafo MCP non contiene un indice di Cascade: dopo la risposta di progetto assente è stata usata la lettura diretta dei file, come consentito dalle istruzioni del repository.
- Modifica preesistente in `Cascade.xcodeproj/project.pbxproj` rilevata e lasciata intatta. Nessuna modifica al codice applicativo.
