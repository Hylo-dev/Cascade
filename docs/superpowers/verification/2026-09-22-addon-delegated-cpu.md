# Contabilità CPU delegata — 22 settembre 2026

**Stato: coordinatore, revisioni, suite completa e consegna firmata PASS. Integrazione broker ancora separata.** L’utente ha scelto l’attribuzione conservativa in [Definire l’attribuzione CPU dei servizi ai consumatori](../../../.scratch/cascade-product/issues/55-addon-delegated-cpu-attribution.md): intero costo del processo a ogni consumatore canonico attivo nell’intervallo, processo contato una volta nel totale fisico.

## Ambito

[Addebitare gli intervalli CPU ai consumatori verificati](../../../.scratch/cascade-product/issues/56-addon-delegated-cpu-accounting.md) estende il coordinatore interno con destinatari verificati associati a binding completi. Sol medium implementa; root e Sol indipendente revisionano. La contabilità usa i conti già esistenti, con credito100ms e ricarica5ms/s, conserva debito, validazione e classificazione per owner/giro. Identità ripetute e owner diretto sono deduplicati per riga fisica. Campioni incompleti non diventano zero né autorizzano una riapertura.

L’input interno non è prova della causalità: il futuro producer host dovrà dimostrare interesse nell’intervallo e autorità. **L’attribuzione non è ancora collegata automaticamente al broker/runtime.** Il nuovo percorso non attiva il launcher, non modifica l’SDK pubblico e non dichiara qualificata la misura nativa degli addon.

## Revisione

Baseline consegnata:1.153 test/104 suite,487 input. Budget iniziale87%. Il graph non contiene Cascade; discovery tramite fallback rg. Checkout dirty preservato, nessun commit/reset o rimozione di cache. [Brief](../../../.scratch/codex-addon/20260922-delegated-cpu/task-56-brief.md), [rapporto worker](../../../.scratch/codex-addon/20260922-delegated-cpu/task-56-report.md), [revisione root](../../../.scratch/codex-addon/20260922-delegated-cpu/root-review.md).

Il primo delta sommava i consumi inUInt64 prima di chiamare il conto: root e revisore hanno rilevato una riduzione impropria dell’intervallo valido, perché il saldo con credito può sostenere un totale appena superiore aUInt64.max. La correzione verificata riusa gli addebiti sequenziali del conto originale, mantenendo una sola classificazione finale. Il delta finale corretto e congelato supera la revisione indipendente e la suite completa.

## Frontiera

Gli audit dei registri canonici e delle specifiche hanno identificato una scelta residua: [Decidere l’attribuzione CPU nelle catene di servizi](../../../.scratch/cascade-product/issues/57-addon-transitive-cpu-attribution.md). La regola conservativa approvata determina quanto addebitare a un consumatore, ma non decide se A debba pagare la CPU di C quando A usa B e B usa C. La composizione broker deve conoscere tale regola prima di produrre il set dei destinatari.

La [ricognizione dell’integrazione](../../../.scratch/codex-addon/20260922-delegated-cpu/integration-audit.md) conserva anche i vincoli tecnici: interessi che sopravvivono ai processi, lavoro concluso fra campioni, finestre temporali, salute senza processo e sincronizzazione. Nessuna delle alternative tecniche è implementata o presentata come garanzia nativa.


## Verifiche finali del codice

Root e [revisore indipendente](../../../.scratch/codex-addon/20260922-delegated-cpu/task-56-independent-review.md): PASS, nessun rilievo aperto. Otto nuovi test; run mirato finale **126 test PASS** (124/11suite e2trasporto), exit0. La prova red disabilita temporaneamente l’inclusione dei destinatari, rileva il fallimento atteso e ripristina il codice; è sensibilità comportamentale dopo implementazione, non TDD iniziale. [Log mirato finale](../../../.scratch/codex-addon/20260922-delegated-cpu/task-56-fix-green.log).

Suite completa root: **1.161 test in105 suite PASS**, exit0. Totali dei cinque prodotti771/63,112/11,170/19,91/10,17/2. [Log completo](../../../.scratch/codex-addon/20260922-delegated-cpu/package-tests.log). Snapshot della build:488 input verificati byte per byte, con checkout dirty preesistente preservato.


## Consegna verificata

Lo script ufficiale `scripts/build-development.sh` ha eseguito il controllo dei confini SDK prima di Xcode e concluso **BUILD SUCCEEDED**, exit0, con firma Apple Development verificata. `/Applications/Cascade.app` punta alla build appena prodotta in DerivedData/CascadeDevelopment. Tutti i488 input coincidono fra snapshot e checkout originale dopo la build: rispetto alla baseline cambia soltanto ProcessMetricsCoordinator.swift e si aggiunge la suite ProcessMetricsDelegatedCPUAccountingTests.swift; nessun file rimosso.

Cascade chiusa normalmente e riavviata: PID **42941 → 46952**, percorso dell’eseguibile corrispondente alla build aggiornata e stabilità verificata per5secondi. [Log build](../../../.scratch/codex-addon/20260922-delegated-cpu/application-build.log), [verifica input](../../../.scratch/codex-addon/20260922-delegated-cpu/build-input-verification.json), [prova riavvio](../../../.scratch/codex-addon/20260922-delegated-cpu/delivery.json).

Tracker aggiornato:57 ticket,40 risolti,17 aperti non assegnati,7 disponibili e10 bloccati,nessun claim residuo,dipendenze acicliche. Budget finale14% consumato, **86% residuo**; nessun reset. Il lavoro si ferma alla scelta progettuale sulle catene, non alla soglia75%. Sol/Terra hanno eseguito audit distinti, Sol ha implementato e un Sol separato ha revisionato; root ha controllato il delta, corretto il rilievo aritmetico attraverso il worker e verificato la consegna. Nessuna modifica a sottosistemi esterni agli addon in questa tranche.
