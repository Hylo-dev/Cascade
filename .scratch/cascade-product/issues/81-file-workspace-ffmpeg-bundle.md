# Preparare FFmpeg e ffprobe verificati nel bundle

ID: 81
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/file-shelf
Blocked by: none

## Question

Implementare il task 5 del [piano del ripiano file](../../../docs/superpowers/plans/2026-09-26-file-shelf.md): acquisizione da release ufficiale con firma/hash realmente verificati, manifest di versione/configurazione/licenze, build e verifica di ffmpeg/ffprobe, staging e firma nel bundle senza dipendenza da Homebrew o download durante la build ordinaria. Accettazione: verifier rifiuta binari mancanti, versione/architettura errata e librerie non di sistema; fixture di conversione leggibile da ffprobe; architetture e codec attestati solo se provati. Niente GPL/nonfree implicito. Review root e commit selettivo. Questo lavoro è indipendente dalla qualifica del percorso nativo.

## Answer

Implementato con GPT-5.6 Sol nei commit `c1c8d51` e `30ba37f`, dopo ricerca GPT-6 Sol e review personale root. FFmpeg/ffprobe 9.0.2 da sorgenti ufficiali autenticati con hash e firma, build arm64 per macOS 14, dipendenze dinamiche esclusivamente di sistema. Encoder H.264 VideoToolbox, AAC, FLAC e PCM; MP3 escluso. Artefatti generati ignorati da Git, riproduzione documentata in [FFmpeg in Cascade](../../../docs/third-party/ffmpeg.md).

Root ha verificato dieci casi negativi, percorsi con spazi, conversioni MP4 reali e sandbox. La build Xcode reale ha rilevato e fatto correggere la directory temporanea: sandbox mantenuta attiva, scratch nel TEMP_DIR del target. Build finale `scripts/build-development.sh` exit0, firme app/helper coerenti, conversione dalla coppia firmata nel bundle riuscita, licenze nelle Resources. Link `/Applications/Cascade.app` aggiornato e riavvio verificato PID27461.

Solo arm64 è qualificato; x86_64 non consegnato. Nessun coordinatore di conversione o percorso nativo attivato. [Evidenze e limiti della tranche](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md).
