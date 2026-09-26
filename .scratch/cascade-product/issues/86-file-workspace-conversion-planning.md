# Preparare formati e avanzamento della conversione

ID: 86
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/file-shelf
Blocked by: 76, 81

## Question

Estrarre la parte pura del task 6 del [piano approvato](../../../docs/superpowers/plans/2026-09-26-file-shelf.md): parser incrementale e limitato del progresso FFmpeg, decodifica limitata dei metadati ffprobe, intersezione dei formati compatibili e preset chiusi coerenti con la build verificata. Nessun processo, accesso ai file, coordinatore, persistenza job o montaggio produttivo.

Accettazione: chunk spezzati e CRLF, valori mancanti/non finiti/negativi e input eccessivi; microsecondi corretti anche per l’alias out_time_ms; progress=end non rappresenta il successo. Formati MP4/M4A/WAV/FLAC, MP3 escluso; copertine attached_pic non diventano tracce video; selezioni miste senza salto silenzioso. Argomenti controllati e nessuna opzione o percorso proveniente dal widget. Test mirati e review personale root. Il componente produce soltanto un piano: autorizzazione, confinamento, quote, uscita fisica e validazione dei risultati restano in [Eseguire conversioni file in job recuperabili](82-file-workspace-conversion-jobs.md).

## Answer

Implementato da GPT-5.6 Sol nel commit `5c53ae5`, con review personale e verifica indipendente root. Parser incrementale con riga massima 4096 byte e osservazione coalescente; metadati ffprobe limitati a 64 KiB e 32 tracce; selezione comune MP4/M4A/WAV/FLAC. Preset chiusi con indici delle tracce esatti, nessun percorso o comando del widget. Copertine e video senza disposizione esplicita esclusi dalla capacità MP4. Durata da tracce selezionate, fallback al contenitore soltanto senza tracce estranee. `progress=end` rimane telemetria, non successo.

Quindici test mirati con cicli RED/GREEN; filtro indipendente root FileWorkspace/FFmpeg: 64 test passati. Build firmata riuscita, collegamento Applications aggiornato e riavvio verificato PID34695. Review ha corretto la gestione delle copertine non identificate, gli argomenti audio per video muti e prove che non misuravano il comportamento. Nessun processo, coordinatore o job attivato. Il [ticket conversioni complete](82-file-workspace-conversion-jobs.md) resta aperto; [evidenze della tranche](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md).
