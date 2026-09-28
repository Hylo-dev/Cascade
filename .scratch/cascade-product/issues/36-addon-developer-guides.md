# Documentare compatibilità, prestazioni e distribuzione degli addon

ID: 36
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex-01a0b0f2
Blocked by: 24, 25, 26, 27, 28, 31, 32, 33

## Question

Completare le tre guide sviluppatore ancora mancanti previste da C12/04.2, descrivendo API, limiti e prove effettivamente consegnati e mantenendo espliciti i requisiti nativi aperti.

## Context

Il [piano addon](../../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md) permette documentazione e validazione prima della qualifica completa. Compatibilità del package, negoziazione interna, misure osservate e packaging distribuibile sono ambiti distinti; le guide non possono trasformare le proposte in funzionalità implementate.

## Progress

Presa in carico per esecuzione Codex su tre soli nuovi documenti. Baseline immutabile: consegna contratti sottoscrizioni del18settembre; sorgenti live/cache del worker servizi esclusi. Revisione del task principale prima dell’integrazione nell’indice. Nessuna build, processo addon, firma o distribuzione da parte del worker documentale.

## Answer

Consegnate le guide [compatibilità](../../../docs/addons/compatibility.md), [prestazioni](../../../docs/addons/performance.md) e [distribuzione](../../../docs/addons/distribution.md), collegate dall’indice addon. Revisione indipendente del task principale PASS:32 link locali validi e sei sorgenti confrontati con gli hash della consegna immutabile. Precisata la distinzione fra ammissione ordinaria e debito disco osservato. [Revisione ed evidenze](../../codex-addon/20260918-continuation/addon-developer-guides-independent-review.md).

Documentazione soltanto: nessuna nuova build o qualifica nativa, nessun formato o comando di installazione inventato. La compatibilità si riferisce alla baseline consegnata; verrà aggiornata all’effettiva consegna del client completo in lavorazione. C11/C12 globali restano aperti.
