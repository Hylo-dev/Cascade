# Superfici del notch: stato e scelta residua

Ricognizione del 20 settembre 2026 per [Disegnare stati e superfici del notch](../../../.scratch/cascade-product/issues/07-notch-surfaces.md). Documento di confronto, non un nuovo prototipo eseguito né una specifica approvata.

## Decisioni già acquisite

| Stato | Contratto da conservare |
| --- | --- |
| Riposo | Allineamento al notch fisico, chrome anche sul display senza notch; pannello non attivante. |
| Hover | Aptica all'inizio dell'hover, come nella specifica approvata; il testo iniziale del ticket «dopo l'apertura» è storico. |
| Compatto | Attività primaria a sinistra; seconda attività nel cerchio destro distinto. |
| Espanso | Hover sulla primaria; click o azione accessibile sulla secondaria. L'interazione manuale non viene sostituita da un avviso. |
| Avviso | Occupa entrambe le ali; il più recente sostituisce il precedente. Hover lo rimuove. Nessuna riproduzione degli avvisi scartati durante espansione o blocco schermo. |
| Widget | Pagina ospitata nell'espanso; editor, personalizzazione e priorità contestuali restano nei propri ticket. |
| Nero e glass | Conservare il renderer esistente; luci glass nell'espanso, ferme quando non servono e con Reduce Motion. |
| Ricerca | Campo e risultati del vero Spotlight, con dimensioni native, confermati dall’utente. Integrazione già presente; restano prove native di focus, raccordo e ripristino. |
| Impostazioni | Sotto il notch, linguaggio macOS. Sidebar, Form, ricerca e collegamento al focus già presenti; resta la verifica visiva della build corrente. Gli scope funzionali dipendono dai rispettivi ticket. |

Fonti: [specifica interattiva approvata](../../superpowers/specs/2026-09-04-interactive-notch-design.md), [contratti delle attività](../../architecture/live-activity-contracts.md), [glass](../../architecture/glass-lighting.md), [requisiti ricevuti](project-baseline.md). Non si ripropongono come scelte aperte le prime sei righe.

## Confronto che ha portato alla scelta della ricerca

La [prova locale del 9 settembre](../research/spotlight-notch-live-probe-macos27.md) ha spostato il vero Spotlight sotto il notch tramite Accessibility su macOS27 beta. Il campo interno non risultava ridimensionabile; focus/IME/VoiceOver, ripristino dopo chiusura, altri display/OS e composizione visiva completa non sono qualificati. Non è stata rieseguita oggi.

| Percorso | Cosa vede e usa la persona | Conseguenza |
| --- | --- | --- |
| **Prima tranche con Spotlight originale (raccomandata)** | Campo e risultati di sistema, dimensioni native; Cascade studia soltanto il raccordo al notch. La tastiera resta a Spotlight. | Conserva la preferenza per il vero Spotlight. Accetta che il campo non segua le dimensioni personalizzate di Cascade. AX richiede consenso e verifica; se indisponibile, Spotlight resta nella sua posizione normale. |
| Campo ridisegnato come parte del notch | Un campo con geometria e stile Cascade che dovrebbe continuare a comandare i risultati originali. | La prova disponibile non dimostra sostituzione del campo, IME, selezione, tastiera o accessibilità. Serve una ricerca distinta; un'eventuale nuova API privata richiede la singola eccezione appena approvata come policy. Non è implementabile come semplice rifinitura del primo percorso. |

**Decisione presentata (ora approvata):** accettare per la prima tranche il campo originale di Spotlight, con dimensioni proprie, invece di esigere subito un campo ridisegnato dentro il notch. Questa è una scelta sul risultato visibile; non un'approvazione a qualificare anticipatamente AX o a usare API private.

La scelta è stata approvata. La successiva ricognizione ha trovato il raccordo già implementato: il passo seguente è verificarne il ciclo nativo di chiusura/ripristino e focus, senza produrre un prototipo duplicato. Anche le impostazioni sono già implementate; la verifica della loro posizione non sostituisce le decisioni funzionali dei rispettivi ticket.

## Risposta acquisita

Il20settembre l’utente conferma «sì esatto»: prima tranche con campo Spotlight originale e dimensioni native. La decisione canonica è registrata nel ticket delle superfici. Rimangono da provare raccordo, ripristino, focus/accessibilità e combinazioni di display/OS.

## Correzione successiva alla conferma

La ricerca nel codice ha individuato SpotlightCoordinator, SpotlightAccessibilityMonitor e SpotlightDropletPanel già integrati in CascadeServices, con [piano e prove del9settembre](../../superpowers/plans/2026-09-09-spotlight-droplet.md). Il riferimento precedente alla sola prova usa informazioni incomplete. Il percorso con campo originale esiste già; il lavoro residuo riguarda qualifica e ripristino, non la sua prima implementazione. I dettagli correnti sono nel ticket delle superfici.

## Esito della prosecuzione

Il ticket delle superfici è risolto come decisione/prototipo. La [verifica locale](../../superpowers/verification/2026-09-20-spotlight-native-continuation.md) osserva campo nativo, focus, calcolo via AX e ripristino nei due cicli, oltre alle impostazioni. Le qualifiche generali rimangono elencate nel rapporto; non giustificano un nuovo prototipo delle stesse superfici. Il successivo arbitraggio è nel proprio ticket.
