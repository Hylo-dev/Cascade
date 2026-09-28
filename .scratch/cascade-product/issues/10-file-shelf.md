# Definire raccolta e durata dei file nel ripiano

ID: 10
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: none

## Question

Il ripiano si presenta durante il drag e acquisisce i file soltanto al drop sul notch, come confermato dall'utente: quali eventi di drag lo presentano e come si torna alla schermata precedente? Chiarire riferimenti contro copie, persistenza dopo riavvio, file spostati o rimossi, file promessi, elementi cloud, duplicati, limiti di spazio e rimozione dal ripiano. Nessuno spostamento o cancellazione del file originale deve essere dedotto dalla sola espressione «tiene da parte».

## Answer

La [specifica approvata](../../../docs/superpowers/specs/2026-09-26-file-shelf-design.md) registra la conferma dell’utente «esatto, continua» e le scelte F1–F11: il drag file presenta il notch e acquisisce solo al drop valido; l’annullamento torna alla pagina precedente; il ripiano occupato resta pagina predefinita senza cancellare la scelta manuale. Gli originali rimangono dove sono, con riferimenti persistenti; promesse e risultati sono copie gestite persistenti. File mancanti, cloud non materializzati o permessi persi restano visibili come non disponibili, ricollegabili o rimovibili. Identità distinte per omonimi e deduplica del medesimo originale; limiti di spazio e quote già esistenti. La consegna è per elemento: solo una copia verificata permette di rimuovere la voce; una rimozione volontaria dell’unica copia gestita richiede conferma. Il [piano esecutivo](../../../docs/superpowers/plans/2026-09-26-file-shelf.md) rende verificabili questi confini nei task 2, 3 e 7. La precedenza generale tra contesti e Spotlight resta aperta in [Decidere priorità tra attività, pagine e contesto](08-context-arbitration.md), che blocca il solo routing contestuale, non la decisione di conservazione del ripiano.
