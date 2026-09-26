# Preparare formati e avanzamento della conversione

ID: 86
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: claimed
Assignee: codex/file-shelf
Blocked by: 76, 81

## Question

Estrarre la parte pura del task 6 del [piano approvato](../../../docs/superpowers/plans/2026-09-26-file-shelf.md): parser incrementale e limitato del progresso FFmpeg, decodifica limitata dei metadati ffprobe, intersezione dei formati compatibili e preset chiusi coerenti con la build verificata. Nessun processo, accesso ai file, coordinatore, persistenza job o montaggio produttivo.

Accettazione: chunk spezzati e CRLF, valori mancanti/non finiti/negativi e input eccessivi; microsecondi corretti anche per l’alias out_time_ms; progress=end non rappresenta il successo. Formati MP4/M4A/WAV/FLAC, MP3 escluso; copertine attached_pic non diventano tracce video; selezioni miste senza salto silenzioso. Argomenti controllati e nessuna opzione o percorso proveniente dal widget. Test mirati e review personale root. Il componente produce soltanto un piano: autorizzazione, confinamento, quote, uscita fisica e validazione dei risultati restano in [Eseguire conversioni file in job recuperabili](82-file-workspace-conversion-jobs.md).
