> Prosecuzione corrente: [verifica Codex del 18 settembre](2026-09-18-addon-asset-message-integration.md). I vincoli di routing e budget riportati qui sotto sono storici.

# Collegamento messaggi asset e client SDK

Stato storico al 15 settembre: implementazione in corso, nessuna consegna allora verificata. [Piano](../plans/2026-09-15-addon-asset-message-integration.md).

Baseline verificata prima dell’intervento:795 test/80 suite,400 input applicativi/test identici,55 percorsi nel manifesto cumulativo revisionato. L’ultima build firmata e il riavvio PID28937 riguardano il componente precedente. La quota principale ufficiale è61% utilizzata al15 settembre2026,10:31:09UTC; tetto65% per conservare almeno35%.

L’incremento collega i frame al runtime autenticato, ai suoi slot condivisi, alle quote e agli alias canonici, e aggiunge un client SDK concreto per importare/condividere/rilasciare immagini tramite un canale a messaggi iniettato. La negoziazione1.2 è cumulativa: l’host la abilita solo con supporto storage e asset; le operazioni asset non richiedono il permesso storage.own.

La prova end-to-end userà un bridge soltanto nei test verso runtime, codec, assemblatore, ImageIO e AssetState reali. Non costituisce un adattatore IPC di produzione o una qualifica del launcher nativo. Nessun gate C0d viene aperto.

Pendenti al 15 settembre (ora completati nella verifica del 18 settembre): implementazione, RED/GREEN mirati, revisione indipendente, suite completa sul codice congelato, build firmata, aggiornamento Applications e riavvio verificato.
