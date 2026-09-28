# RAM dei provider — 23 settembre 2026

Stato: implementazione interna verificata, build firmata e avvio aggiornato riusciti.

La scelta «1» approva il [profilo progressivo64/96MiB](../../../.scratch/cascade-product/issues/65-addon-provider-memory-policy.md), limitato al proprietario fisico già deciso. Wayfinder è usato soltanto per gli addon. Terra medium implementa il [classificatore](../../../.scratch/cascade-product/issues/66-provider-memory-episodes.md); Sol medium implementa la [composizione nel runtime](../../../.scratch/cascade-product/issues/67-runtime-provider-memory.md). Root e un Sol indipendente revisionano i risultati.

## Contratto

Il moderato RAM apre un episodio oltre64MiB e fino96MiB inclusi, senza moltiplicare incidenti durante la permanenza. Il recupero richiede una misura propria corrente a64MiB o meno. Oltre96MiB prevale la richiesta di stop atteso; nessun retry crash e nessuna liberazione fisica anticipata. Una misura mancante o obsoleta non vale zero. Wake e nuova registrazione non azzerano l’episodio della stessa incarnazione; una nuova incarnazione non rimuove da sola la pausa per owner.

CPU e RAM hanno pause indipendenti e condividono lo storico: un solo moderato per owner/giro, quarantena per versione conservata. La RAM non è propagata ai consumer. Nuove ammissioni e nuovi interessi rispettano entrambe le pause; lavoro già ammesso e riuso canonico conservano i contratti precedenti.

## Evidenze

- [Baseline e ledger](../../../.scratch/codex-addon/20260923-provider-memory/ledger.md):497 input iniziali,1.209 test/113 suite della precedente consegna.
- [Classificatore: implementazione e test](../../../.scratch/codex-addon/20260923-provider-memory/task-66-report.md),3 test PASS.
- [Revisione root66](../../../.scratch/codex-addon/20260923-provider-memory/task-66-root-review.md) e [revisione indipendente66](../../../.scratch/codex-addon/20260923-provider-memory/task-66-independent-review.md): PASS.
- [Disegno runtime](../../../.scratch/codex-addon/20260923-provider-memory/task-67-design.md) e [brief esecutivo](../../../.scratch/codex-addon/20260923-provider-memory/task-67-brief.md).

## Verifica finale e consegna

[Report runtime67](../../../.scratch/codex-addon/20260923-provider-memory/task-67-report.md):10 test RAM e176 test mirati PASS. La revisione ha corretto test di lifecycle che usavano il punto d’ingresso sbagliato, attivato interessi reali nella catena e limitato la memoria dei registratori di stop dei test. Non è stata modificata la policy per soddisfare i test. Il report distingue il classificatore test-first dall’integrazione testata dopo l’implementazione e conserva il fallimento intermedio della fixture.

[Revisione root67](../../../.scratch/codex-addon/20260923-provider-memory/task-67-root-review.md) e [revisione indipendente67](../../../.scratch/codex-addon/20260923-provider-memory/task-67-independent-review.md) documentano i controlli del contratto. La [suite completa finale](../../../.scratch/codex-addon/20260923-provider-memory/full-package-summary.json) passa con1.222 test in115 suite: Runtime832/73, Contracts112/11, Kit170/19, SDK91/10, Tools17/2.

Comando finale con Xcode-beta: `xcrun swift test --disable-sandbox --skip-build --package-path CascadeKit --scratch-path /private/tmp/cascade-addon-tests --no-parallel`, dopo la compilazione mirata dei file definitivi. Le cache esplicite e gli esiti sono conservati nell’evidenza della tranche.

La [verifica degli input](../../../.scratch/codex-addon/20260923-provider-memory/build-input-verification.json) confronta500 file della copia di build con il checkout: tre file modificati, tre aggiunti e nessuno rimosso rispetto alla baseline. `scripts/build-development.sh` ha completato la build ufficiale firmata e aggiornato `/Applications/Cascade.app`.

[Avvio verificato](../../../.scratch/codex-addon/20260923-provider-memory/delivery.json): Cascade era già chiusa; avviata la build aggiornata con PID21839, firma e percorso eseguibile verificati, processo stabile dopo5secondi. Quota settimanale residua77%; nessun credito reset consumato.

## Frontiera

L’[audit successivo](../../../.scratch/codex-addon/20260923-provider-memory/post-67-frontier-audit.md), inclusa la sua correzione sulla baseline UI, non individua un altro incremento di codice addon già deciso e indipendente. I passaggi residui dipendono dalle prove di piattaforma dei ticket19/22, ancora sospese. Il blocco del launcher approvato resta valido; non si riapre la stessa scelta né si inventa un classificatore UI prima delle misure richieste.

## Limiti

Nessun launcher, nuovo protocollo, profilo UI/audio o controllo nativo abilitato. I test con adapter controllati non qualificano identità OS, footprint di un addon reale o arresto fisico. Il budget UI resta condiviso con il provider; la calibrazione e le semantiche del profilo continuo attendono le misure previste. Nessun commit, reset, cancellazione del checkout o consumo di crediti reset.
