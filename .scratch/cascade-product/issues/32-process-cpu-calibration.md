# Verificare indipendentemente le unità delle metriche CPU

ID: 32
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: —
Blocked by: 25

## Question

Confrontare il lettore CPU già consegnato con una misura indipendente sul processo locale della prova, per verificare le unità senza introdurre un launcher, controllo di altri processi o garanzie di uscita gestita.

## Context

Requisito esplicito C4 sulla calibrazione indipendente, ancora aperto nella [verifica delle metriche](../../../docs/superpowers/verification/2026-09-18-addon-process-metrics.md). Prova diagnostica limitata alla macchina corrente e al proprio processo; sorgenti di produzione invariati. La qualificazione macOS14/Intel e C0d restano separate.

## Progress

Presa in carico per definire ed eseguire un controllo breve e limitato, con sorgenti della prova, hash, misure grezze e limiti conservati. Nessun risultato ancora dichiarato.

## Answer

Tre campioni delle copie esatte di lettore/riduttore concordano con gli intervalli POSIX getrusage; revisione indipendente PASS, sorgenti invariati. [Evidenze e limiti](../../../docs/superpowers/verification/2026-09-18-addon-process-cpu-calibration.md). Il risultato qualifica solo la scala CPU su macOS27 arm64/self-process; C4 completo e controllo nativo restano separati.
