# Caricare widget SwiftUI esterni: meccanismi e limiti

ID: 01
Parent: cascade-product
Type: research
Labels: wayfinder:research
Mode: AFK
Status: resolved
Assignee: codex-research-01
Blocked by: none

## Question

Quali meccanismi permettono a Cascade, distribuito fuori dal Mac App Store, di scoprire e ospitare widget SwiftUI forniti da altre app o installati come moduli in una cartella, senza ricompilare l'host? Confrontare Swift Package/import, bundle o framework dinamici, IPC/XPC e UI ospitata in un processo separato. Distinguere possibilità documentate, limiti di ABI e type identity, firma e hardened runtime, isolamento reale, compatibilità e ciò che richiede una prova. Chiarire perché conformare un protocollo dentro un'altra app non produce da solo discovery o trasporto della UI. Indicare le alternative tecnicamente percorribili, senza scegliere al posto dell'utente il formato definitivo.

## Answer

Ricerca risolta il 4 settembre 2026 da codex-research-01. [Report con fonti e matrice delle alternative](../../../docs/wayfinder/research/swiftui-extensions.md).

- Import e SwiftPM servono alla build; non forniscono discovery automatico in un altro processo.
- Un bundle binario può fornire UI SwiftUI caricata nell'host, con vincoli di firma/ABI e senza isolamento da crash o blocchi del main thread.
- ExtensionKit offre UI remota pubblica. Le classi base sono disponibili dal 13; le nuove API di extension point e discovery richiedono macOS 26. La distribuzione separata avviene tramite app contenitore e richiede abilitazione utente.
- Compatibilità del percorso legacy su 14/15, firme di sviluppatori diversi e comportamento dentro il pannello del notch richiedono una prova; la scelta del formato rimane aperta.

Contesto riproducibile: branch `codex/research/cascade-sdk-20260904`, commit `7a89398`, report conservato anche nel worktree `/private/tmp/cascade-wayfinder-sdk`. Nessun prototipo eseguito e nessuna garanzia di compatibilità dedotta dalla sola disponibilità delle API.
