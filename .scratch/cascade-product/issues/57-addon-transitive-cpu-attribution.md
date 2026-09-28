# Decidere l’attribuzione CPU nelle catene di servizi

ID: 57
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 56

## Question

Se A usa B e B usa C nello stesso intervallo, il consumo misurato di C viene attribuito anche ad A oppure soltanto al consumatore diretto B?

## Contesto

[Definire l’attribuzione CPU dei servizi ai consumatori](55-addon-delegated-cpu-attribution.md) ha risolto la formula: intervallo completo a ciascun consumatore canonico attivo, senza dividere il costo e senza moltiplicare il totale fisico. Non ha risolto la propagazione attraverso più servizi. Il coordinatore aritmetico può ricevere un insieme deduplicato; il prossimo collegamento al broker deve invece produrre quell’insieme secondo una regola esplicita.

La specifica richiede di non scaricare costi fuori dalla propria quota, ma non definisce la chiusura transitiva. Il percorso statico del resolver ordina i processi da avviare e non prova il lavoro effettivamente delegato. Un provider condiviso può usare un altro servizio per lavoro proprio o per un consumatore diverso: nemmeno una catena di interessi attivi dimostra la causalità della singola richiesta.

## Alternative

1. **Propagazione conservativa lungo gli interessi attivi (consigliata).** Nell’esempio,40ms CPU di C si addebitano a C, B e A. Evita che A aggiri la quota inserendo un intermediario; accetta di attribuire ad A anche lavoro interno di B o richiesto da altri suoi consumatori. Si seguono soltanto relazioni canoniche attive nell’intervallo, non dipendenze installate ma inutilizzate. Ogni identità paga al massimo una volta per processo/intervallo, anche se più percorsi conducono alla stessa dipendenza.
2. **Solo consumatori diretti.** I40ms di C si addebitano a C e B. A paga la CPU di B, ma non quella che B delega ulteriormente; minore penalizzazione indiretta, con il limite esplicito che la quota di A può essere aggirata usando intermediari.

In entrambi i casi il totale fisico resta40ms. Nessuna alternativa è implementata prima della risposta. La revisione delle fonti effettuata da Terra e root conferma che questa scelta non è già stata risolta; la sincronizzazione fra registri e campioni resta un problema tecnico separato.


## Answer

Il22settembre2026 l’utente ha scelto1: **propagazione conservativa lungo le catene canoniche attive**. In A→B→C, il consumo di C ricade su C, B e A, una volta per identità/processo/intervallo anche in presenza di più percorsi. Si accetta il costo della condivisione e del lavoro interno del provider intermedio. Non si usano dipendenze statiche prive di interessi attivi. Le relazioni della catena devono essere contemporaneamente attive almeno in un tratto dell’intervallo: l’unione di archi esistiti in momenti disgiunti non inventa una catena. Globale fisico sempre contato una volta.
