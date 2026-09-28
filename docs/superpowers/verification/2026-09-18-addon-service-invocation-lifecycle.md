# Verifica del ciclo SDK delle invocazioni ai servizi — 18 settembre 2026

**PASS nel perimetro del componente interno e del bridge al runtime reale.** Tre nuovi file implementano `ServiceInvocationLifecycle`, i test SDK e l’integrazione canonica con runtime/broker. Nessun nuovo client pubblico o protocollo attivato; i 483 input preesistenti catturati sono rimasti invariati.

## Evidenze finali

- **978 test in 89 suite passati** dopo la correzione della revisione: Runtime 634/51, Presentation 92/9, Kit 170/19, Contracts 65/8 e Tool 17/2. Test seriali nella sessione GUI richiesta da AppKit.
- Le nuove suite comprendono 23 dichiarazioni e 52 esecuzioni espanse. Il primo handoff includeva inoltre 22 test broker e 5 casi di composizione esistenti; la verifica completa finale copre tutti i target.
- Revisione indipendente Codex Sol high: un P2 nel test di replay, corretto con RED compilabile e GREEN, poi **PASS** nel riesame. Il test ora segna il possibile handoff prima della richiesta duplicata al runtime; il rifiuto del broker non viene confuso con assenza di esposizione. Il componente di produzione è invariato dalla prima review.
- Build Apple Development riuscita su snapshot finale di **422 input**, tutti confrontati con il checkout. Firma verificata e `/Applications/Cascade.app` aggiornato. Chiusura normale e nuovo processo **PID 51036 → 65073**, eseguibile atteso e stabilità per cinque secondi.

[Handoff originale](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-report.md), [correzione e riconciliazione](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-review-fix-report.md), [freeze finale](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-review-fix-final-freeze.json), [review originale](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-independent-review.md), [riesame PASS](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-independent-review-addendum.md), [suite completa finale](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-fixed-full.log), [snapshot finale](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-fixed-build-manifest.json), [build firmata](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-fixed-signed-build.log), [riavvio](../../../.scratch/codex-addon/20260918-continuation/service-lifecycle-restart-evidence.json). Freeze, log e build precedenti rimangono conservati come storico; non qualificano da soli la correzione.

## Comportamento verificato

Il ciclo serializzato dal chiamante conserva un solo ticket e metadati limitati, senza payload, task, code o cronologia. Valida valore e correlazione della completion prima del consumo. Prima del possibile invio, la cancellazione ritira il ticket; dopo l’esposizione, ogni operazione di servizio può restare outcomeUnknown, anche se si chiama read. Una risposta esatta consumata prima della cancellazione conserva il proprio esito; se arriva dopo viene scartata senza riscrivere l’incertezza locale.

La fixture usa risoluzione, acquisizione, dispatch, ingresso delle completion e cronologia canonici. Distingue risultato noto all’host ed esito locale incerto, revoca, replay, generazioni nuove e completion differite. Una completion pendente non è inoltrata come successo. I buffer restano entro uno scope protetto preammesso, distinto dalle quote host; i task trattenuti vengono sbloccati e attesi anche nei percorsi di errore. Chiusura logica non significa drain fisico, rimborso o rollback.

## Limiti e seguito

La generazione dei grant di servizio resta separata dalla connessione di pubblicazione; nessun AddonContext combinato o grant riscritto. Il relay dei risultati è soltanto infrastruttura di test fidata. I casi da 64 KiB verificano valori tipizzati, non l’intero trasporto serializzato di quei payload; gli ingressi reali della fixture usano messaggi piccoli. Limiti nativi, firme dei peer, allocazioni Foundation/RSS e uscita fisica non sono qualificati. `observeExit` è un input simulato e C0d mantiene exit78.

C3 completo richiede ancora messaggi consumer/provider e relative receipt, sottoscrizioni, composizione delle sessioni, canale nativo e prove con provider reali. I codec dedicati sono la tranche successiva, attualmente sviluppata in copia isolata; questa consegna non li attiva. Gli esempi pubblici già verificati restano invariati e non sono presentati come una prova nativa.
