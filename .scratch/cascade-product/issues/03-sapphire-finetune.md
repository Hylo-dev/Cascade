# Valutare glass e audio dai sorgenti di Sapphire e FineTune

ID: 03
Parent: cascade-product
Type: research
Labels: wayfinder:research
Mode: AFK
Status: resolved
Assignee: codex-research-03
Blocked by: none

## Question

Come realizzano Sapphire il trattamento glass e FineTune la gestione audio per app? Leggere i sorgenti, oltre ai README. Individuare renderer, API, permessi, minimi di sistema, eventuale driver/helper, routing, EQ, limiti del percorso audio e costi quando inattivo o attivo. Identificare anche le integrazioni pertinenti di Sapphire senza importare tutta la sua lista di funzioni nel prodotto. Riportare fatti verificati e riferimenti a commit/file; distinguere ispirazione funzionale da possibile riuso, annotando le licenze dichiarate senza dare per autorizzata una copia.

## Answer

Ricerca risolta il 4 settembre 2026 da codex-research-03. [Report sui sorgenti con riferimenti ai commit](../../../docs/wayfinder/research/sapphire-finetune.md).

- Sapphire usa NSGlassEffectView su macOS 26, con manipolazioni interne aggiuntive; sui sistemi precedenti adotta un fallback NSVisualEffectView. La somiglianza esatta alla Siri dell'allegato resta da valutare visivamente.
- FineTune usa process taps e aggregate HAL per volume per app, routing e output multipli, senza un driver aggiuntivo nel percorso studiato. Il motore audio deve rimanere indipendente dalla visibilità del widget.
- La primitiva Core Audio taps richiede macOS 14.2; il progetto FineTune esaminato imposta 15.4, mentre il README indica 15.0. Nessuna compatibilità completa di quel codice con Cascade su macOS 14 è stata dimostrata.
- Il codice studiato comprende API private, percorsi di recupero e gestione della concorrenza che non costituiscono garanzie trasferibili. La documentazione Apple corregge inoltre un commento del sorgente sul dispatch del callback audio.

Contesto riproducibile: branch `codex/research/cascade-references-20260904`, commit `6de9c6635dfa54db5eea4a073ad85a950d1612e1`, worktree `/private/tmp/cascade-wayfinder-references`. Nessuna app di riferimento è stata eseguita; nessun test audio o di compatibilità effettuato. Le prove necessarie restano decisioni/prototipi successivi.
