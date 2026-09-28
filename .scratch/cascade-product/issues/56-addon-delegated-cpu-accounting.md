# Addebitare gli intervalli CPU ai consumatori verificati

ID: 56
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 55

## Question

Estendere la contabilità del coordinatore con destinatari verificati per ogni binding fisico, prodotti in seguito dal registro canonico del runtime. L’intero intervallo va al provider e a ogni consumatore distinto; stesso conto CPU, nessuna duplicazione di letture o del totale fisico. Preflight limitato e atomico, errori e intervalli incompleti propagati, una classificazione per owner/giro. Mantenere comportamento preesistente quando non esistono attribuzioni. Sol medium implementa; root e revisione indipendente verificano. Questa unità non dichiara collegata l’attribuzione al broker o all’app.


## Answer

Completato il22settembre2026 daSol medium con revisione root e Sol indipendente PASS. Il coordinatore accetta destinatari verificati per binding esatto e li addebita nello stesso giro fisico: deduplica self/duplicati, stesso conto persistente, una classificazione finale per owner, nessuna duplicazione delle misure. Validazione completa e ammissione dei nuovi conti prima di qualsiasi lettura o modifica; input non dovuto non crea conti. Incompletezza e fallimento restano espliciti. Conservato l’intervallo aritmetico originale usando charge per riga, inclusa regressioneUInt64.max+1 ancora valida entrocredito; fallimento del vero limite del debito resta persistente.

Otto nuovi test;126 test mirati e1.161 test completi/105 suite PASS, exit0. [Revisione indipendente](../../codex-addon/20260922-delegated-cpu/task-56-independent-review.md), [evidenze e consegna](../../../docs/superpowers/verification/2026-09-22-addon-delegated-cpu.md). Il producer broker/runtime non è implementato: resta la scelta sui destinatari indiretti in [Decidere l’attribuzione CPU nelle catene di servizi](57-addon-transitive-cpu-attribution.md). Nessuna attivazione nativa o modifica SDK.
