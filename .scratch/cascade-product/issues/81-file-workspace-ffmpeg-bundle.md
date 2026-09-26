# Preparare FFmpeg e ffprobe verificati nel bundle

ID: 81
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: open
Assignee: none
Blocked by: none

## Question

Implementare il task 5 del [piano del ripiano file](../../../docs/superpowers/plans/2026-09-26-file-shelf.md): acquisizione da release ufficiale con firma/hash realmente verificati, manifest di versione/configurazione/licenze, build e verifica di ffmpeg/ffprobe, staging e firma nel bundle senza dipendenza da Homebrew o download durante la build ordinaria. Accettazione: verifier rifiuta binari mancanti, versione/architettura errata e librerie non di sistema; fixture di conversione leggibile da ffprobe; architetture e codec attestati solo se provati. Niente GPL/nonfree implicito. Review root e commit selettivo. Questo lavoro è indipendente dalla qualifica del percorso nativo.
