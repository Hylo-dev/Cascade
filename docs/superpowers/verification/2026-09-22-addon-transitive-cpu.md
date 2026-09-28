# CPU transitiva e recupero dopo crash — 22 settembre 2026

**Stato: implementazione interna, revisioni, suite completa e consegna firmata PASS.** La [decisione sulle catene](../../../.scratch/cascade-product/issues/57-addon-transitive-cpu-attribution.md) attribuisce la CPU ai consumatori raggiungibili attraverso interessi contemporaneamente attivi, deduplicando identità/processo/intervallo. Il launcher resta bloccato.

## Ambito e revisioni CPU

Wayfinder usato soltanto per addon. Sol medium implementa registro, coordinatore e runtime; Terra medium integra broker e proiezioni della domanda; root e un Sol distinto revisionano. Checkout dirty preservato, nessun commit/reset, nessuna pulizia delle cache. Il knowledge graph non contiene Cascade; discovery tramite fallback rg.

Il [registro](../../../.scratch/cascade-product/issues/58-addon-cpu-attribution-ledger.md) accumula l’unione delle chiusure istantanee fra osservazioni, evitando catene costruite con archi mai sovrapposti. Il [coordinatore](../../../.scratch/cascade-product/issues/59-addon-coordinator-attribution-ledger.md) preammette atomicamente il dominio verificato e conserva i contributori fisici esatti. Il [broker](../../../.scratch/cascade-product/issues/60-addon-broker-attribution-ledger.md) pubblica e ritira gli interessi allo stesso confine canonico, conservandoli dove previsto oltre disconnect/exit.

Il [runtime](../../../.scratch/cascade-product/issues/61-addon-runtime-transitive-cpu.md) condivide il registro e verifica nuovamente autorità di destinatari e contributori dopo ogni lettura. Un consumatore senza processo può ricevere addebiti delegati; un processo presente senza propria misura valida non riapre le ammissioni grazie al solo credito del provider. Nuove acquisizioni e invocazioni rispettano la pausa di consumatore e provider, preservando lavoro accettato e riuso degli interessi.

La revisione ha corretto un avvio prematuro dei provider prima del rifiuto del consumatore. Ha inoltre conservato l’ack v1.4 dopo un commit seguito da rollback, prima del terminale indeterminato: adeguare il test all’assenza dell’ack sarebbe stato un cambiamento errato del protocollo. Tre aspettative esatte di memoria sono state aggiornate di4KiB, pari alla riserva aggiuntiva per owner, conservando la verifica del rimborso. [Revisione root](../../../.scratch/codex-addon/20260922-transitive-cpu/root-review.md), [revisione runtime indipendente](../../../.scratch/codex-addon/20260922-transitive-cpu/task-61-independent-review.md).

Test mirati: registro29/3suite, coordinatore49/5, broker39/3, runtime152/15. La mutazione deliberata che eliminava la transitività ha fatto fallire le asserzioni attese; non è una prova TDD iniziale. Suite completa prima dei retry: **1.195 test/112 suite PASS**, exit0, somma dei cinque prodotti805/70,112/11,170/19,91/10,17/2. [Log completo](../../../.scratch/codex-addon/20260922-transitive-cpu/package-tests-before-retry-fixed.log).

## Recupero dopo crash

Il [supporto domanda e ticket](../../../.scratch/cascade-product/issues/62-addon-crash-retry-projections.md) espone proiezioni limitate e cancellazione dei soli retry pendenti. Il [collegamento al runtime](../../../.scratch/cascade-product/issues/63-addon-runtime-crash-retry.md) passa revisione root e [indipendente](../../../.scratch/codex-addon/20260922-transitive-cpu/task-63-independent-review.md). Solo un’uscita inattesa classificata dall’host usa la sessione emessa al handoff per applicare1/5/30secondi con domanda corrente e quarantena al quarto crash con domanda. Il chiamante predefinito resta non classificato. Nessun replay del lavoro già consegnato.

La decisione di crash è serializzata dalla pulizia comune dopo la riconciliazione del broker. Durante l’attesa, il token esatto impedisce avvii e sessioni CPU sostitutive. Un comando in coda deve essere non scaduto; per gli interessi broker si confronta la scadenza canonica con un istante fresco dopo l’attesa. I ticket usano il medesimo identificatore delle azioni/cold start. Il controllo della domanda prima delle risorse e quello successivo condividono la stessa ammissione del lancio. Consumo e binding sono preparati su una copia dello store e resi canonici subito prima del handoff. Rifiuti precedenti restituiscono le riserve; una consegna rifiutata spende il tentativo. Nessuna domanda elimina il ticket senza avviare un processo.

Stop, disable e risveglio annullano anche decisioni sospese; il risveglio preserva salute dei processi attivi e debito CPU. La CPU delegata di un consumatore senza processo durante il backoff attraversa un’operazione autorizzata dal ticket esatto, conservato su `keep` e rimosso in quarantena. Le correzioni di revisione comprendono token orfani, rimborso dopo crescita del pool, falso esito “senza domanda” concorrente con un nuovo interesse e pulizia differita dopo stop durante il precontrollo.

Verifica finale mirata: **230 test/20 suite PASS**, exit0 (228/19 del runtime e2/1 trasporto). [Report e sette hash congelati](../../../.scratch/codex-addon/20260922-transitive-cpu/task-63-report.md), [log mirato](../../../.scratch/codex-addon/20260922-transitive-cpu/task-63-final-cleanup-broad.log). I gate sono deterministici; le attese temporali limitano soltanto il watchdog. Il test dello stop verifica anche lo svuotamento della pulizia e l’assenza di riserve del provider.

## Verifiche finali e consegna

Suite completa root: **1.209 test/113 suite PASS**, exit0. Totali dei cinque prodotti819/71,112/11,170/19,91/10,17/2. [Log completo finale](../../../.scratch/codex-addon/20260922-transitive-cpu/package-tests.log). I sette hash congelati coincidono con il report del worker e quello indipendente. La build precedente alle ultime correzioni è conservata separatamente nelle evidenze, non è quella consegnata.

Lo script ufficiale `scripts/build-development.sh` esegue il controllo dei confini SDK e termina **BUILD SUCCEEDED**, exit0, con firma Apple Development verificata. Snapshot finale497 input identici al checkout anche dopo la compilazione:7 file modificati,9 aggiunti,nessuno rimosso rispetto alla baseline della tranche. Il dirty checkout precedente è preservato. `/Applications/Cascade.app` punta alla build aggiornata in DerivedData/CascadeDevelopment. [Log build](../../../.scratch/codex-addon/20260922-transitive-cpu/application-build.log), [verifica input](../../../.scratch/codex-addon/20260922-transitive-cpu/build-input-verification.json).

Cascade risultava già chiusa al momento della consegna. La versione aggiornata è stata avviata, verificando il percorso esatto dell’eseguibile, la firma e la stabilità per5secondi: PID **62002**. [Prova dell’avvio](../../../.scratch/codex-addon/20260922-transitive-cpu/delivery.json). Nessuna chiusura normale viene dichiarata eseguita su un processo già assente.

Tracker:64 ticket,47risolti,17aperti non assegnati,7disponibili/10bloccati; nessun claim residuo e dipendenze acicliche. Quota settimanale finale21% consumata, **79% residua**; nessun reset. Il lavoro si ferma alla nuova scelta RAM, non alla soglia75%.

## Limiti e frontiera

Le prove usano binding host e adapter controllati. Non qualificano identità OS, classificazione nativa dell’uscita, arresto dei processi, C0d o profili continui UI/audio. I conti CPU persistono nella durata del runtime, non attraverso il riavvio di Cascade.

La successiva [attribuzione della RAM osservata](../../../.scratch/cascade-product/issues/64-addon-memory-attribution.md) è una decisione distinta. Il footprint residente non è un intervallo CPU e le decisioni precedenti non autorizzano a trasferirlo ai consumatori. Soglie candidate, aggregazione e conteggio degli episodi restano da definire; nessuna implementazione RAM aggiunta in questa tranche.
