# Acquisire e consegnare file con drag nativo per elemento

ID: 79
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: open
Assignee: none
Blocked by: 77, 78

## Question

Implementare il task 3 del [piano del ripiano file](../../../docs/superpowers/plans/2026-09-26-file-shelf.md) con AppKit, monitor/hold drag esistenti e trasferimento per singolo file tramite ricevute persistenti. Accettazione: drag non-file e pasteboard vecchia non attivano il ripiano; annullamento non acquisisce; drop parziale rimuove solo gli elementi la cui consegna è provata; promise asincrone, nomi sicuri e collisioni senza overwrite; prova reale Finder, Mail/URL-only, annullamento e drop parziale. Test mirati, review root e commit. Richiede percorso nativo qualificato e store di [Persistire voci e ricevute del ripiano file](78-file-workspace-persistence.md); un esito globale del drag non prova ogni file.
