# Verificare le dipendenze reali dei manifest ServiceConsumer

ID: 38
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 27

## Question

Collegare i manifest pubblicati di ServiceConsumer e del provider esempio alla matrice REQUIRES del vero ResolutionPlanner, senza aggiungere dipendenze private agli esempi o modificare codice produttivo.

## Context

[C12](../../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md#c12--sdk-distribuibile-strumenti-ed-esempi-indipendenti) richiede la prova delle dipendenze fra i due esempi. I test pubblici attuali validano dichiarazioni e propagano esiti simulati; il resolver è già testato su fixture generiche. L’[audit residuo](../../codex-addon/20260918-continuation/addon-remaining-work-audit.md) individua questo collegamento mancante.

## Scope e prova finita

Verifica AFK in harness temporaneo e archiviato, non nuova feature o modifica della suite del package. Copiare esattamente i due manifest, i tre file del resolver e Contracts; registrare hash e fixture. Gli originali e il package restano invariati, così la suite pubblica non acquisisce dipendenze dall’host o da percorsi esterni. L’harness è autosufficiente e conserva dati e comandi riproducibili.

Eseguire il resolver reale per presenza compatibile/ordine provider-consumer, assenza, provider disabilitato, major incompatibile, ciclo derivato e consenso fra publisher sintetici seguito da rimozione del consenso con binding precedente. Verificare binding e feature effettive, motivi specifici e assenza di effetti di un binding precedente revocato. Le varianti sono derivate esplicitamente dai manifest di partenza, non offerte come nuovi manifest distribuibili.

Nessuna firma, autenticazione, concessione reale, launcher, revoca durante IPC o parità nativa è dimostrata. La prova si chiude con esecuzione registrata, controllo degli originali invariati e revisione indipendente; C12 globale resta aperto. Non inventare un RED per comportamento produttivo già implementato.

## Answer

Matrice sorgente completata:7 funzioni/8 casi/1 suite PASS con decoder e resolver reali,65 input archiviati e63 originali verificati identici. Revisione indipendente PASS, senza correzioni richieste. [Verifica e limiti](../../../docs/superpowers/verification/2026-09-18-service-consumer-manifest-resolution.md). Nessun codice produttivo/package/esempio modificato: soltanto harness archiviato e documentazione del risultato. C12 e qualificazione nativa restano aperti.
