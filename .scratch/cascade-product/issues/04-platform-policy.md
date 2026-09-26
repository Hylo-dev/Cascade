# Definire compatibilità macOS e integrazioni ammesse

ID: 04
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 01, 02, 03

## Question

Qual è il minimo macOS del prodotto e quali funzionalità possono essere disponibili solo su versioni più recenti? Il codice parte da macOS 14 e usa già SkyLight privato; la distribuzione diretta con Homebrew è confermata. Alla luce delle ricerche, quali API private o tecniche fragili sono ammesse, con quali fallback e impegni di compatibilità? Decidere per singola capacità, includendo glass, media, notifiche, ricerca, caricamento moduli e audio, senza assumere che fuori dallo Store tutto sia automaticamente fattibile.

## Riallineamento del 14 settembre 2026

Per il sottosistema addon il piano corrente conserva macOS 14 come minimo e API native pubbliche, senza caricare codice addon nel processo grafico. È un vincolo di progetto, non una qualificazione su macOS 14. Le decisioni globali sulle altre integrazioni e la matrice effettivamente verificata rimangono aperte. Riferimento: [vincoli e stato del piano addon](../../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md).

## Scelta presentata — 20 settembre 2026

Il minimo macOS14 e le API pubbliche per il sottosistema addon sono già vincoli approvati; il launcher resta bloccato per decisione esplicita. Non vanno richiesti nuovamente.

Per le nuove integrazioni generali del prodotto resta da scegliere se ammettere soltanto percorsi pubblici (accettando copertura funzionale ridotta dove necessario), oppure valutare singolarmente anche tecniche private con fallback e compatibilità da verificare. Il codice privato già presente non costituisce un'autorizzazione generale ad aggiungerne altro. La scelta non autorizza letture di dati personali, nuovi permessi macOS o deroghe al lifecycle degli addon.

La raccomandazione è usare API pubbliche come percorso predefinito e sottoporre ogni eventuale eccezione privata come decisione circoscritta, con beneficio, fallback e costo di manutenzione espliciti. Questo conserva la possibilità di valutare le capacità richieste senza approvare in blocco tecniche fragili. Il ticket resta aperto e non attribuisce questa preferenza all'utente.

## Answer — 20 settembre 2026

L'utente approva la raccomandazione: API pubbliche per impostazione predefinita; ogni nuova eccezione privata richiede una decisione circoscritta con beneficio, fallback, compatibilità e costo di manutenzione. Nessuna autorizzazione generale a nuove API private. Le integrazioni esistenti e già approvate rimangono tali; questa scelta non le riscrive né le estende implicitamente.

Si conserva macOS14 come minimo di progetto già confermato nella [specifica interattiva approvata](../../../docs/superpowers/specs/2026-09-04-interactive-notch-design.md), senza dichiarare una qualificazione su tutte le versioni/hardware. Le capacità più recenti devono avere disponibilità esplicita e un percorso di fallback; assenza o permesso negato non diventano successo simulato.

| Capacità | Regola per i prossimi incrementi |
| --- | --- |
| Glass e presentazione | Conservare motore e contratti approvati; nuove integrazioni pubbliche e fallback coerente con le preferenze di accessibilità. |
| Media, notifiche, ricerca | Conservare le integrazioni già approvate. Valutare separatamente qualsiasi nuovo accesso privato; nessuna lettura universale o parità Spotlight dedotta. |
| Audio e dispositivi | Privilegiare percorsi pubblici; disponibilità, consenso, hardware e qualità richiedono le prove dei ticket dedicati. |
| Moduli addon | Confine di processo già approvato; nessun codice esterno nel processo grafico. Launcher bloccato finché manca la prova conforme di uscita. |

Questa è una policy di progetto risolta, non il superamento delle prove native. Le scelte delle singole esperienze restano nei ticket dedicati; nessun accesso a dati personali o cambiamento dei permessi è implicito.
