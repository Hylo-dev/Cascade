# Decidere priorità tra attività, pagine e contesto

ID: 08
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: open
Assignee: none
Blocked by: 02, 07

## Question

Quando contesto, notifica, hover, drag e scelta manuale chiedono contenuti diversi, chi prevale e per quanto tempo? Decidere suggerimento contro apertura automatica, preemption, eventuale blocco manuale della pagina, ritorno alla pagina precedente, timeout e gestione di eventi simultanei. Stressare lo scenario musica + timer + collegamento cuffie durante un drag, e l'arrivo di una notifica mentre l'utente scrive nella ricerca.

## Frontiera dopo le superfici — 20 settembre 2026

Claim preso dopo la risoluzione del ticket delle superfici. Consultate grilling e domain-modeling dalle fonti indicate nella guida. I contratti delle attività già approvati proteggono l’interazione manuale dagli avvisi, scelgono l’avviso più recente e scartano quelli ricevuti durante espansione/blocco, senza riproporli. Non si richiede una nuova scelta su queste regole.

Resta da precisare la precedenza tra due intenzioni manuali: una superficie già aperta (pagina, attività o ricerca) e il trascinamento di un file sul notch. È già richiesto che il ripiano compaia durante il drag e acquisisca file soltanto al rilascio. Il ritorno dopo il drag e l’interruzione della ricerca non sono ancora definiti.

Proposta da sottoporre all’utente: il drag sul notch mostra temporaneamente il ripiano; al termine si torna al contenuto precedente, senza far prevalere nel frattempo un avviso. Se Spotlight contiene una ricerca, conservarla invece di chiuderla automaticamente; il ripiano resta un bersaglio temporaneo nel notch. Non si promette ancora la fattibilità di questa composizione nativa: dopo la scelta servono verifica e specifica prima del codice. Nessuna nuova implementazione o modifica dei requisiti del launcher.

Punto decisionale presentato all’utente: ripiano temporaneo conservando la ricerca, oppure sostituzione della ricerca con il ripiano. Raccomandata la prima opzione, subordinata alla verifica tecnica dopo la scelta. Claim rilasciato in attesa della risposta; nessun codice o contratto nuovo approvato implicitamente.
