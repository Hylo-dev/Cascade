# Integrare Spotlight, notifiche e attività di macOS: fattibilità

ID: 02
Parent: cascade-product
Type: research
Labels: wayfinder:research
Mode: AFK
Status: resolved
Assignee: codex-research-02
Blocked by: none

## Question

Quali API e tecniche consentono a Cascade di mostrare notifiche di app non integrate, eventi di connessione Bluetooth, media correnti anche dal browser e feedback aptico? Quali operazioni sono possibili sul vero Spotlight di macOS: invocazione, posizione, stile e integrazione nel notch? Distinguere esplicitamente API pubbliche, tecniche private, Accessibility, permessi, copertura incompleta e versioni del sistema. Non confondere UserNotifications della propria app con un lettore universale. Non scegliere ancora tra Spotlight di sistema e ricerca propria: produrre la matrice di fattibilità per entrambe.

## Answer

Ricerca risolta il 4 settembre 2026 da codex-research-02. [Matrice di fattibilità, fonti e verifiche residue](../../../docs/wayfinder/research/macos-integrations.md).

- Il vero Spotlight è richiamabile; un eventuale spostamento tramite Accessibility va provato. Non è stato trovato un contratto pubblico per cambiarne materiali e gerarchia o ospitarlo in Cascade. Una UI di ricerca propria non ha automaticamente parità di funzioni.
- UserNotifications riguarda la propria app. Sapphire legge con polling un archivio SQLite privato di Notification Center: non dimostra né copertura universale né consegna immediata. Accessibility è un'altra tecnica da verificare; i relativi permessi non equivalgono all'accesso all'archivio.
- Bluetooth e richiesta di feedback aptico hanno API pubbliche; disponibilità dei dati degli accessori e percezione dell'impulso dipendono dall'hardware e dal sistema.
- Le informazioni globali Now Playing nei progetti esaminati passano da MediaRemote privato. Rilevare o instradare audio con Core Audio non fornisce da solo titolo, copertina o identità della scheda browser.
- ActivityKit e le attività iPhone mostrate dal sistema non costituiscono un protocollo di acquisizione automatica delle attività altrui per Cascade.

Contesto riproducibile: branch `codex/research/cascade-system-20260904`, commit `38dc5b7081d6badebaa419f7223a39d06b1e6a46`, worktree `/private/tmp/cascade-wayfinder-system`. Nessun accesso a notifiche o database personali, nessuna modifica di permessi, nessuna prova UI effettuata. Le scelte di fallback e il perimetro delle versioni supportate rimangono aperti.
