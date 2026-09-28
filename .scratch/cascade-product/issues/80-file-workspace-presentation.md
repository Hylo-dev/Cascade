# Aggiungere il componente condiviso e la lista animata del ripiano

ID: 80
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/file-shelf
Blocked by: 76

## Question

Implementare il task 4 del [piano del ripiano file](../../../docs/superpowers/plans/2026-09-26-file-shelf.md): schema contenuti 3 negoziato, nodo `fileWorkspace` disponibile a builtin/esterni e renderer SwiftUI comune per mazzo, lista e conversione. Accettazione: schemi 1/2 preservati e rifiuto del nodo nuovo, limiti byte/nodi/asset invariati, azioni validate, massimo quattro carte e +N, freccia centrata, paginazione, identità/animazioni stabili, VoiceOver e Riduci movimento. Test contratti/layout e review root; preview locale con 1/4/5/40 elementi. Sviluppabile offline senza montaggio nativo; non pubblicizzare schema 3 finché renderer/adattatori non sono installati.

## Answer

Implementato nel commit `b8b3756` con GPT-5.6 Sol e review root: nodo e schema contenuti 3 con opt-in esplicito, azioni semantiche con descrittori immutabili (massimo 64), miniature dichiarate e rimappate negli archivi, renderer comune per mazzo/lista/conversione. Le correzioni della review includono righe lunghe nei bordi, carte opache leggibili, comando Convert visibile, gruppi allineati alla freccia, risultati distinti dalle anteprime e blocco di Start durante job attivi.

Verifica indipendente root: 86 test mirati passati tra FileWorkspace, ProtocolAdmission, GlassLight, ContentValidation e ActionAuthorizer; preview NSHostingView/NSWindow con 1/4/5/40 file, nomi lunghi, riduzione movimento, conversione compatta e job attivo. Screenshot locali sotto `/private/tmp/cascade-file-shelf-preview/`; [checkpoint e limiti](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md).

Componente condiviso completato, schema 3 non abilitato nella app produttiva. Navigazione manuale VoiceOver e timing delle animazioni nel notch reale restano da verificare con l’integrazione nativa; le preview attestano gli stati assestati.
