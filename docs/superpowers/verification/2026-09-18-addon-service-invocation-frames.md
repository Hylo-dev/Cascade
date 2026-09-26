# Verifica dei messaggi dedicati alle invocazioni — 18 settembre 2026

**PASS per i contratti e codec, senza attivazione nel runtime.** Quattro nuovi file Contracts e una suite definiscono richiesta consumer, risposta correlabile e invocazione al provider. Il profilo `.v1_3` descrive la sintassi; la negoziazione resta invariata, con default1.0 e massimo implementato1.2.

## Evidenze

- Sviluppo in harness Contracts isolata: 77 test / 9 suite passati, 12 nuovi gruppi e 65 test esistenti. RED comportamentali compilabili conservati; tutti i 62 input di base invariati. La harness usa Swift6.4 installato e tools minimum6.2, non prova un compilatore6.2.
- Import nel checkout dei soli cinque file, identici al freeze; nessun Package temporaneo importato. Revisione indipendente Codex Sol high **PASS**, senza fix P1/P2 obbligatori.
- **Suite completa del checkout: 990 test in 90 suite PASS**: Runtime634/51, Presentation92/9, Kit170/19, Contracts77/9 e Tool17/2. La verifica completa è distinta dall’harness iniziale.
- Build Apple Development riuscita su **427 input**, confrontati con il checkout e con i 422 della consegna precedente, tutti invariati. Firma verificata, collegamento Applications aggiornato e riavvio normale **PID65073 → 68582**, eseguibile atteso e stabilità per cinque secondi.

Evidenze: [harness e handoff preservati](../../../.scratch/codex-addon/20260918-continuation/service-frames-isolated/service-frames-artifacts/service-frames-handoff.md), [freeze](../../../.scratch/codex-addon/20260918-continuation/service-frames-isolated/service-frames-artifacts/service-frames-FROZEN.json), [import esatto](../../../.scratch/codex-addon/20260918-continuation/service-frames-root-import.json), [review indipendente](../../../.scratch/codex-addon/20260918-continuation/service-frames-independent-review.md), [suite completa](../../../.scratch/codex-addon/20260918-continuation/service-frames-full.log), [snapshot](../../../.scratch/codex-addon/20260918-continuation/service-frames-build-snapshot-manifest.json), [build](../../../.scratch/codex-addon/20260918-continuation/service-frames-signed-build.log), [riavvio](../../../.scratch/codex-addon/20260918-continuation/service-frames-restart-evidence.json). I percorsi assenti dichiarati dal freeze descrivono il momento precedente all’import, non lo stato attuale.

## Contratto e limiti

Il cap raw è192KiB, applicato prima del decoder Foundation; payload decodificati restano64KiB e ragioni di rifiuto4096byte UTF-8 non vuoti, senza troncamento. Schema, discriminanti e campi sono chiusi. L’esito incerto ha una variante dedicata; refused(outcomeUnknown) è invalido. Un rifiuto significa nessun nuovo dispatch causato da questo scambio, non che una richiesta logica precedente non sia stata eseguita.

Payload massimi con ogni slash base64 escaped attraversano i tre codec dedicati; i metadati P1 più grandi sono limitati conservativamente a711byte, per175479byte totali, sotto196608. Il limite generico AddonEvent128KiB rimane invariato. Rappresentazioni con espansione Unicode/whitespace oltre il cap vengono rifiutate. Non è una prova di workspace Foundation, RSS o doppia codifica base64 in un envelope esterno.

**La decodifica non equivale a una risposta correlata.** Prima di proiettare una risposta completed nel ciclo SDK, il consumer deve chiamare `reply.validate(matching: request)`: verifica ID, contratto e operazione esterni e della risposta annidata. Constructor/codec verificano struttura e limiti, ma ammettono una discordanza outer/nested che matching rifiuta sempre. Anticipare quel rifiuto è un rafforzamento P3 opzionale, registrato senza cambiarne qui il confine. Non esiste ancora un consumer Runtime/SDK di questa nuova reply che salti la verifica.

Restano da implementare handler/adapter con receipt e risorse reali, percorso completo input/completion/risposta, composizione delle generazioni, executor SDK e sottoscrizioni. Nessun client pubblico completo, trasporto nativo, peer autenticato o C3 completo è dichiarato. C0d mantiene l’uscita incondizionata78.
