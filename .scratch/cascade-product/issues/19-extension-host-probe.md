# Provare una UI SwiftUI esterna dentro il notch

ID: 19
Parent: cascade-product
Type: prototype
Labels: wayfinder:prototype
Mode: HITL
Status: open
Assignee: none
Blocked by: 01

## Question

Quale esperienza di installazione e quale isolamento sono ottenibili ospitando una scena SwiftUI ExtensionKit nel pannello del notch, sulle versioni macOS candidate? Creare una prova minima e separata dal prodotto con app sorgente e host distinti: discovery e abilitazione, resize, trasparenza, focus, click, drag e accessibilità. Osservare anche crash o blocco della UI remota senza attendere risposte sincrone nell'host. Verificare le firme di sviluppatori diversi solo se le identità necessarie sono disponibili; registrare esplicitamente ciò che non è stato testato. Il prototipo e le misure permettono all'utente di valutare il compromesso rispetto al caricamento di bundle da cartella, senza trasformare automaticamente l'alternativa in architettura approvata.

## Avanzamento del 9 settembre 2026

La direzione è ora approvata: contenuti ordinari nell'host e scene remote per SwiftUI avanzato. [P0](../../../docs/superpowers/plans/2026-09-09-addon-runtime-00-platform.md) trasforma questo ticket in prove operative di packaging, peer autenticato, arresto anche dopo crash host, metriche e scena nel pannello. Il prototipo rimane separato dalla produzione.

Il ticket resta aperto perché le prove non sono state eseguite. Una compilazione locale non dimostra macOS diversi, isolamento effettivo o firme di editori distinti. Eventuali impedimenti devono precedere il congelamento delle API e non autorizzano un fallback a codice addon dentro l'host.

## Riallineamento del 14 settembre 2026

Le prove di piattaforma non sono più tutte ineseguite: il [rapporto sul launcher](../../../docs/superpowers/verification/2026-09-10-addon-launcher-decision.md) registra limiti osservati delle alternative; il piano corrente distingue il prototipo RemoteUI soltanto compilato dalla qualificazione di una scena reale nel notch. Non risultano concluse le prove di interazione, accessibilità, firme di editori diversi e matrice macOS richieste da questo ticket.

La [diagnostica C0d](../../../docs/superpowers/verification/2026-09-12-addon-managed-death.md) è verificata offline, con prova nativa sospesa. Il disegno necessario per il requisito di uscita dei processi è ora nel distinto [ticket sui processi gestiti](22-managed-process-exit-proof.md), evitando di confonderlo con l'esperienza della UI remota.

Questo ticket rimane aperto per il prototipo UI e la valutazione con l'utente. Essere disponibile nella frontiera significa che il tema può essere affrontato: non autorizza a rimuovere il gate C0d o ad aggirarlo durante la prova.

## Incremento sorgente — 20 settembre 2026

Il [contatore del prototipo](41-remote-scene-counter.md) ora pubblica eventi correlati sul canale autenticato e riceve conferme dall'host. Check del riduttore e build firmata dei tre target PASS, con revisione/correzioni root. Nessuna attivazione nativa eseguita: questo ticket rimane aperto per la prova effettiva della scena, interazioni, accessibilità e matrice richiesta. Il blocco del launcher è confermato dall'utente.

I successivi check delle callback effettive di [provider](42-counter-provider-lifecycle.md) e [host](43-counter-host-lifecycle.md) sono completati con correzioni riprodotte. Non sono prove di XPC o di scena attivata: questo ticket rimane aperto.
