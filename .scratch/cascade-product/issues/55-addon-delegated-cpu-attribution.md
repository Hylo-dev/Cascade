# Definire l’attribuzione CPU dei servizi ai consumatori

ID: 55
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 54

## Question

Come attribuire ai consumatori il consumo CPU misurato nel processo di un provider condiviso, senza fingere una misura precisa del singolo lavoro?

## Contesto

La specifica richiede di contare una volta il processo nel totale globale e di attribuire anche ai consumatori il lavoro delegato, per impedire che aggirino la propria quota. Le decisioni sul credito e sulle violazioni hanno lasciato espressamente separata questa attribuzione. Il lettore corrente misura CPU user+system dell’intero processo: un intervallo può includere invocazioni di consumatori diversi, sorgenti condivise e lavoro interno. Non misura direttamente la quota causata da ciascuno.

Dopo il rifiuto dei nuovi lavori e il collegamento delle scadenze, il prossimo incremento deve scegliere una regola di addebito, con conseguenze visibili su disponibilità e quarantena dei consumatori. La regola non modifica il credito del provider né moltiplica il consumo globale fisicamente misurato.

## Alternative da valutare con l’utente

1. **Attribuzione conservativa (raccomandazione iniziale).** L’intero consumo dell’intervallo interessato viene addebitato anche a ciascun consumatore con lavoro/interesse attivo per quel provider. Evita di concedere credito ulteriore attraverso la condivisione, ma può penalizzare un consumatore per lavoro richiesto da un altro.
2. **Ripartizione fra consumatori attivi.** Il costo dell’intervallo viene diviso fra i consumatori interessati secondo una regola esplicita uniforme. Riduce la penalizzazione della condivisione, ma può sottostimare il consumatore che ha causato quasi tutto il lavoro. È una policy contabile, non una misura per richiesta.

Esempio: 40 ms CPU del provider con due consumatori attivi significano 40 ms per ciascuno con la prima regola, 20 ms ciascuno con la seconda; il totale globale resta 40 ms in entrambi i casi. Il comportamento di intervalli senza consumatori e campioni incompleti deve restare esplicito. Non implementare nessuna alternativa prima della scelta; completare prima la tranche già autorizzata.


La raccomandazione privilegia il requisito di non aggirare le quote attraverso la condivisione; il costo è l’eventuale penalizzazione di un altro consumatore. La ripartizione uniforme può invece diluire il costo aggiungendo interessi poco attivi. In entrambi i casi, gli interessi e il lavoro devono provenire dal registro canonico host e riferirsi all’intervallo osservato; assenza di consumatori attribuibili non crea un addebito inventato, e misure sconosciute/incomplete non diventano consumo zero.

Riferimenti: [specifica delle risorse](../../../docs/superpowers/specs/2026-09-09-addon-runtime-design.md), [esclusione dalla scelta sul burst](46-addon-cpu-burst-policy.md), [esclusione dalla scelta sul conteggio](49-addon-cpu-violation-counting.md). La revisione indipendente del 21 settembre conferma che nessuna di quelle scelte ha già risolto la ripartizione.


## Answer

Il22settembre2026 l’utente ha scelto **1, attribuzione conservativa**: l’intero consumo CPU misurato del provider è attribuito anche a ogni consumatore con lavoro/interesse canonico attivo nell’intervallo. Il costo fisico globale resta contato una volta; il conto del provider resta invariato. Si accetta la possibile penalizzazione di un consumatore per lavoro altrui nello stesso intervallo condiviso. Più interessi dello stesso consumatore non moltiplicano il medesimo intervallo; misure incomplete restano sconosciute, non zero. Il tracciamento deve conservare il lavoro concluso fra due campioni, senza dedurlo soltanto dagli interessi ancora presenti al momento della lettura. Attuazione interna circoscritta, launcher sempre bloccato.
