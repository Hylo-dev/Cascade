# Definire installazione e isolamento delle estensioni

ID: 05
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: open
Assignee: none
Blocked by: 01, 04, 19, 22

## Question

Come devono arrivare i widget all'utente: installati automaticamente dall'app sorgente, moduli aggiunti a una cartella, o entrambi? L'utente vuole SwiftUI e ha proposto import o caricamento da cartella: precisare il significato di import e decidere formato, discovery, attivazione, origine verificabile, aggiornamento, rimozione, revoca e comportamento dopo un crash. Scegliere il confine di processo e documentare se il codice esterno possa bloccare l'host. Il risultato deve rendere concreta la promessa «integra il protocollo e compare un widget».

## Avanzamento del 9 settembre 2026

Approvato il confine nativo in processi su domanda, con contenuti ordinari conservati dall'host e scene SwiftUI remote. L'addon può includere le librerie necessarie e funzionare senza l'app sorgente; Cascade deve rimanere aperta. Preferenza per il contenitore registrabile dal sistema, da provare prima di fissare il formato. Nessun percorso speciale per i widget del team.

La [specifica approvata](../../../docs/superpowers/specs/2026-09-09-addon-runtime-design.md) è resa eseguibile in [P0](../../../docs/superpowers/plans/2026-09-09-addon-runtime-00-platform.md), [P2](../../../docs/superpowers/plans/2026-09-09-addon-runtime-02-execution.md) e [P4](../../../docs/superpowers/plans/2026-09-09-addon-runtime-04-release.md). Il ticket resta aperto per le prove effettive di discovery, firma, sandbox, arresto dopo crash host e aggiornamento sulle versioni macOS supportate.

## Riallineamento del 14 settembre 2026

Il [piano corrente](../../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md) documenta contratti, resolver, coordinatore runtime, servizi, risorse e storage interni implementati. L'ultimo percorso completo verificato resta una suite del package, non l'installazione e l'esecuzione di un addon esterno.

La [politica di controllo approvata](../../../docs/superpowers/specs/2026-09-10-addon-control-policy.md) accetta il rischio del lavoro autonomamente delegato a macOS; conserva i requisiti sui processi gestiti. La qualificazione del launcher resta aperta. Il distinto impedimento C0d è ora tracciato in [Definire una prova sicura di uscita dei processi gestiti](22-managed-process-exit-proof.md); le prove delle scene restano nel [ticket UI SwiftUI](19-extension-host-probe.md).

Restano da completare e provare trasporto/provider nativi, discovery e attivazione reali, identità nel lifecycle di aggiornamento, installazione/distribuzione e integrazione nell'app. Questo aggiornamento conserva il ticket aperto e non abilita alcun launcher.
