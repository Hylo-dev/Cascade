# Rifiuto temporaneo dei nuovi lavori addon — 21 settembre 2026

**Stato: implementazione, revisioni, suite completa e consegna firmata PASS.** L’utente ha scelto la prima alternativa in [Definire la riduzione dei nuovi lavori dopo uno sforamento CPU](../../../.scratch/cascade-product/issues/52-addon-cpu-reduced-admission.md). Si applica un rifiuto immediato fino a credito strettamente positivo provato da misure complete, senza coda o replay aggiuntivo. I lavori già ammessi mantengono deadline e completamenti.

## Ambito

Il [ticket esecutivo](../../../.scratch/cascade-product/issues/53-addon-cpu-admission.md) riguarda nuove azioni e nuovi lavori del provider, usando le metriche e la salute interne già verificate. Il journal e lo scheduler considerano già ammesse le azioni accettate anche se ancora in attesa: il pump non diventa una seconda ammissione. Il bootstrap host resta possibile per ottenere misure dopo l’uscita del provider, conservando debito e blocco dei nuovi lavori. Nessuna attivazione nativa o cambiamento dei limiti.

## Evidenze

Baseline: 1.135 test in 101 suite, 484 input congelati, residuo settimanale90%. [Analisi delle ammissioni](../../../.scratch/codex-addon/20260921-cpu-admission/admission-design-review.md), [brief](../../../.scratch/codex-addon/20260921-cpu-admission/task-53-brief.md). Wayfinder soltanto addon, Sol medium implementa; root e revisione indipendente verificano prima della consegna.


## Ammissione verificata

Sol medium ha completato il controllo delle nuove ammissioni; root e Sol medium hanno revisionato il delta congelato: PASS. Otto nuovi test verificano rifiuto senza conservazione, duplicati, azioni già accettate, credito zero e credito positivo inferiore a100ms, misure mancanti, quarantena, owner distinti, riavvio, invocazioni già ammesse e nuove invocazioni, riuso di sorgenti, rifiuto effettivo v1.4 e una gara durante la crescita delle riserve.

Il controllo nel broker è un overload interno: l’API pubblica preesistente conserva il suo comportamento. Evita sia di rifiutare riusi privi di nuovo lavoro provider, sia di accettare un nuovo avvio già vietato e trasformarlo inutilmente in esito indeterminato. I quattro file della tranche sono congelati e confrontati con i preimage, senza commit/reset del checkout dirty.

Run mirato finale: **191 test** (189 in12suite, due in una suite trasporto), exit0. La prova red disabilita temporaneamente il controllo per dimostrare la sensibilità del test e viene seguita dal ripristino/green; non è presentata come una sequenza TDD iniziale. [Rapporto](../../../.scratch/codex-addon/20260921-cpu-admission/task-53-report.md), [revisione](../../../.scratch/codex-addon/20260921-cpu-admission/task-53-independent-review.md), [root](../../../.scratch/codex-addon/20260921-cpu-admission/root-review.md).

Il seguito [collega le misure alla scadenza comune](../../../.scratch/cascade-product/issues/54-addon-metrics-deadline.md), senza timer o attivazione nell’app. Il prossimo punto progettuale distinto è [l’attribuzione CPU dei servizi ai consumatori](../../../.scratch/cascade-product/issues/55-addon-delegated-cpu-attribution.md), espressamente lasciata aperta dalle decisioni precedenti.


## Scadenze e risveglio verificati

Terra medium ha collegato il quinto aggregato alla coda comune e Sol medium ha scritto i test concorrenti. Root e un Sol indipendente hanno verificato tutti i tre file congelati: PASS. Dieci nuovi test coprono cadenza, campioni espliciti, precedenza della scadenza azione, migrazione owner, ultima uscita, cold start, nuova baseline, debito negativo, lettura interrotta da wake, secondo wake durante reset e runtime fermato. Il primo tentativo Terra ha usato comando/scratch errati; le verifiche valide successive usano Xcode-beta e lo scratch temporaneo ufficiale. Non sono stati eliminati artefatti.

Run mirato: **118 test** (116/10suite e2 trasporto), exit0. [Rapporto produzione](../../../.scratch/codex-addon/20260921-cpu-admission/task-54-report.md), [rapporto wake](../../../.scratch/codex-addon/20260921-cpu-admission/task-54-wake-report.md), [revisione indipendente](../../../.scratch/codex-addon/20260921-cpu-admission/task-54-independent-review.md). La prova red wake omette temporaneamente l’evento nel test e osserva sei fallimenti comportamentali, quindi ripristina il test. Non modifica la produzione e non viene descritta come TDD iniziale.

Suite completa root: **1.153 test in104 suite PASS**, exit0. Totali dei cinque prodotti:763/62,112/11,170/19,91/10,17/2. [Log](../../../.scratch/codex-addon/20260921-cpu-admission/package-tests.log). I487 input della build sono copiati e verificati byte per byte in uno snapshot locale, preservando il checkout dirty e tutti i lavori preesistenti.

L’incremento riguarda il runtime interno dormiente. Restano il binding nativo qualificato, la consegna degli eventi macOS, l’attesa esterna delle scadenze e gli arresti fisicamente osservati. Il launcher resta bloccato. Il seguito richiede la scelta sull’attribuzione CPU condivisa ai consumatori; nessuna alternativa è stata implementata.


## Consegna verificata

Lo script ufficiale `scripts/build-development.sh`, eseguito sullo snapshot esatto, conclude **BUILD SUCCEEDED** e verifica la firma Apple Development. Il controllo SDK obbligatorio precede Xcode. `/Applications/Cascade.app` punta alla build appena prodotta in DerivedData/CascadeDevelopment. Tutti i487 input dello snapshot e del checkout originale coincidono dopo la build; rispetto alla baseline tre file cambiano e tre test vengono aggiunti, nessun file rimosso.

Alla verifica finale Cascade era già chiusa (`beforePIDs: []`); è stata avviata dal collegamento Applications, senza terminazioni forzate. PID **42941**, percorso dell’eseguibile corrispondente alla build aggiornata, firma verificata e processo stabile per5secondi. [Log build](../../../.scratch/codex-addon/20260921-cpu-admission/application-build.log), [identità degli input](../../../.scratch/codex-addon/20260921-cpu-admission/build-input-verification.json), [prova di avvio](../../../.scratch/codex-addon/20260921-cpu-admission/delivery.json).

Tracker aggiornato:55 ticket,38 risolti,17 aperti non assegnati,7 disponibili/10 bloccati,nessun claim residuo e dipendenze acicliche. Budget Codex finale:13% consumato, **87% residuo**; nessun reset utilizzato. Arresto alla scelta progettuale successiva, non alla soglia75%. Nessuna modifica fuori dal sistema addon e dai relativi documenti in questa tranche; il checkout preesistente è conservato.
