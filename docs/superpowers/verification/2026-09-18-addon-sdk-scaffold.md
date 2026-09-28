# Verifica del generatore sorgente SDK — 18 settembre 2026

**PASS nel perimetro del progetto sorgente.** `cascade-addon init` genera un package SwiftPM compilabile con provider pubblico, manifest, test e istruzioni. Identificatore e percorso SDK sono espliciti. Il comando non esegue automaticamente build, test o shell e rifiuta ogni destinazione esistente, incluse directory vuote e symlink. [Guida iniziale](../../addons/quickstart.md).

Revisione indipendente Codex Sol high PASS; unico rilievo P3 sul commento di cleanup corretto e riesaminato. Pubblicazione RENAME_EXCL senza sostituire la destinazione; cleanup non ricorsivo con controllo delle identità osservate. Nessuna garanzia di isolamento da modifiche arbitrarie concorrenti con la stessa autorità filesystem dell’utente, né di persistenza dopo crash.

## Evidenze

- Test mirati tool: 17 test / 2 suite PASS. Progetto esterno generato dal template finale: build e 5 test / 1 suite PASS; import e dipendenze solo SDK/contratti pubblici e loro dipendenze pubbliche. Caso nome keyword e identità coincidente con la precedente fixture estranea verificato.
- Suite completa finale: **896 test / 84 suite PASS** — Runtime 578/48, Presentation 66/7, Kit 170/19, Contracts 65/8, Tool 17/2. Nessun errore di test nella verifica finale.
- Primo tentativo completo fermato dal module cache non scrivibile; secondo con due problemi nel test UI preesistente per NSScreen.main assente nella sandbox. Impostato il cache esplicito ed eseguita la suite con accesso alla sessione grafica; nessuna modifica o esclusione del test UI. Errori precedenti conservati.
- Build Debug Apple Development riuscita da snapshot locale esatto di 412 file, firma deep/strict verificata; collegamento /Applications/Cascade.app aggiornato dallo script previsto.
- Chiusura normale e riavvio verificati: PID 50978 → 17941, unico eseguibile atteso, stabilità per 5 secondi. Nessuna terminazione forzata.

[Rapporto implementer](../../../.scratch/codex-addon/20260918-continuation/scaffold-report.md), [revisione indipendente e correzione](../../../.scratch/codex-addon/20260918-continuation/scaffold-independent-review.md), [audit suite](../../../.scratch/codex-addon/20260918-continuation/scaffold-test-audit.json), [manifest esatto build](../../../.scratch/codex-addon/20260918-continuation/scaffold-final-build-manifest.json), [build](../../../.scratch/codex-addon/20260918-continuation/scaffold-signed-build.log), [riavvio](../../../.scratch/codex-addon/20260918-continuation/scaffold-restart-evidence.json). Log/comandi/status e fallimenti intermedi sono conservati nella medesima directory; snapshot finale /private/tmp/cascade-addon-scaffold-final-20260918.

## Limiti ancora aperti

Il risultato è una libreria sorgente, non un pacchetto addon installabile. Firma dell’addon, bootstrap, trasporto nativo, ripristino delle revisioni e parità bundled/external reale restano distinti. Nessun processo addon lanciato e nessuna qualifica macOS 14 a runtime dichiarata; C0d mantiene exit 78. Questa consegna non completa C12 o l’intero sistema addon. Nessun commit/staging/reset effettuato.
