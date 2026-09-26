# Verificare e consegnare il notch multi-display

ID: 75
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/multi-display
Blocked by: 74

## Question

Implementare e verificare il task 7 del [piano multi-display](../../../docs/superpowers/plans/2026-09-24-multi-display-notch.md) rispettando la [specifica](../../../docs/superpowers/specs/2026-09-24-multi-display-notch-design.md). La tranche esecutiva è autorizzata dalla richiesta del 25 settembre; chiudere solo con prove e revisione.

## Answer

Implementazione consegnata il 26 settembre 2026. Aggiunta la verifica di lifecycle/scadenza condivisa su tre display, aggiornati i contratti e completata la revisione trasversale. L’unico finding finale, perdita anticipata dell’istanza ancora montata durante sostituzione, è stato riprodotto con il controller reale e corretto tramite union delle radici correnti/uscenti e riconciliazione prima/dopo l’applicazione. [Revisione conclusiva](../../../.superpowers/sdd/2026-09-24-multi-display-notch/final-rereview-1.md): PASS/PASS.

Build ufficiale Apple Development riuscita, firma verificata e `/Applications/Cascade.app` aggiornato alla build canonica. Riavvio reale verificato: processo finale 39220 usa l’eseguibile CascadeDevelopment aggiornato. UI Appearance, tre modalità, target specifico e ricerca verificati sul display integrato; preferenza iniziale Segui il focus ripristinata.

Settings 17/17; nuove regressioni lifecycle passano. Il full package finale (1.325 test) resta exit 1: timeout/assertion confrontati puntualmente con la baseline e moduli runtime indipendenti immutati. Non si dichiara una suite integralmente verde. Hardware esterno/mirroring e altre condizioni native non disponibili, Spotlight end-to-end non osservabile tramite CUA e profiling non eseguito restano limiti espliciti della qualificazione, non prove riuscite. [Verbale completo](../../../docs/superpowers/verification/2026-09-24-multi-display-notch.md), [piano](../../../docs/superpowers/plans/2026-09-24-multi-display-notch.md). Nessun commit o merge; snapshot e prove conservate per la consegna in-place autorizzata.
