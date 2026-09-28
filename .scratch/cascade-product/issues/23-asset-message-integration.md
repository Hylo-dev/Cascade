# Collegare i messaggi asset al runtime e al client SDK

ID: 23
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex-01a0b0f2
Blocked by: 21

## Question

Completare il percorso a messaggi per importazione, condivisione e rilascio delle immagini tra client SDK e runtime canonico, verificandolo end-to-end con un canale di test verso il runtime reale. È una tranche esecutiva esplicitamente ammessa nelle Notes della mappa, non una nuova scelta del meccanismo o una qualifica del trasporto nativo.

## Context

- Decisione acquisita: [Scegliere il trasferimento delle immagini tra addon e host](21-asset-transfer.md).
- Specifica implementativa già preparata: [Authenticated asset messages and concrete SDK client](../../../docs/superpowers/plans/2026-09-15-addon-asset-message-integration.md).
- Piano, criteri e incarico autonomo della pipeline: [Collegamento asset autenticato — Astra Pipeline](../../astra-pipeline/20260915-124500/plan.md).

## Progress

15 settembre 2026: presa in carico da pi/Astra xhigh. Preflight riuscito; configurazioni e autenticazione previste disponibili. Checkout preesistente salvato separatamente dalla baseline Git, senza staging o commit. Piano approvato esplicitamente dall'utente. Arresto richiesto sotto il 35% di quota settimanale GPT disponibile o all'esaurimento del credito DeepSeek; controllo ufficiale pre-dispatch: 38% GPT disponibile e 1,45 USD DeepSeek. Prima implementazione prodotta da DeepSeek: 809 test / 82 suite passati. La [valutazione Astra](../../astra-pipeline/20260915-124500/review.md) è PARTIAL per difetti di cleanup/contabilità/close-drain e prove mancanti. Primo round di correzioni messo in pausa su richiesta dell'utente dopo la conclusione del solo worker già attivo. Ultima suite: 811 test / 82 suite; la correzione al cleanup non è ancora rivalutata. Cinque wave non avviate, nessun subagent rimasto attivo, nessuna consegna approvata. [Report di avanzamento e checkpoint di pausa](../../astra-pipeline/20260915-124500/progress.md). Ripresa autorizzata successivamente dall'utente, mantenendo la riserva GPT del 35% e il credito DeepSeek. Checkpoint verificato senza drift; la prosecuzione ha completato altre wave e ricevuto una nuova valutazione PARTIAL. Arresto automatico alla riserva GPT del 35% durante la prima wave dell'ultimo round: worker interrotto prima del report, nessun subagent attivo. [Rapporto corrente e checkpoint](../../astra-pipeline/20260915-124500/budget-stop.md). Ticket preso in carico ma sospeso per budget; nessuna chiusura o consegna approvata. Il gate C0d resta chiuso.

17 settembre 2026: richiesta di continuazione ricevuta in Codex e stato recuperato tramite Wayfinder. Il controllo live del monitor autorizzato conferma GPT 65% usato / 35% disponibile e DeepSeek 0,51 USD. Gate di ripresa chiuso per riserva GPT: nessun worker o valutatore avviato, nessun sorgente modificato, nessuna build o riavvio della versione non approvata. Il checkpoint e la valutazione PARTIAL restano validi come punto di ripresa, non come consegna approvata. Lettura corrente: `../../astra-pipeline/20260915-124500/budget-latest.json`.

17 settembre 2026, ripresa autorizzata: l’utente deroga esplicitamente la riserva GPT del 35%. Claim trasferito al coordinatore Codex; nessun worker precedente attivo. Si riprende il round finale esistente dalla verifica della prima wave interrotta; invariati criteri tecnici, modello worker/valutatore e arresto per credito DeepSeek esaurito o limiti effettivi del provider.

Ripresa corrente: [verifica e autorizzazione provider](../../astra-pipeline/20260915-124500/resume-20260917.md). Avvio DeepSeek respinto dall’auto-review in attesa di consenso esplicito al trasferimento dei sorgenti; test locali avviati, nessun worker attivo.

Verifica locale della ripresa: checkpoint dei quattro file invariato e `git diff --check` riuscito; test mirati interrotti dal timeout di 300 s durante compilazione (exit 124), senza nuovo verdetto. Cascade già installata riavviata normalmente e verificata (PID 55327). Nessun sorgente applicativo modificato in questa ripresa.

18 settembre 2026: l’utente richiede esplicitamente solo Codex, con 5.6 Sol medium o altri modelli secondo difficoltà. Sostituiti routing DeepSeek e relativo gate/credito; non è richiesto ulteriore consenso al provider esterno, che non viene usato. Ripresa nel [piano Codex](../../codex-addon/20260918/plan.md), mantenendo criteri tecnici e revisione indipendente.

## Answer

18 settembre 2026 — Completato il percorso interno autenticato a messaggi per importazione, condivisione e rilascio delle immagini tra SDK e runtime canonico. Sono verificati slot e receipt esatti, assegnazioni immutabili, revoca non terminale delle pubblicazioni, chiusura della connessione distinta dalla disabilitazione dell’owner, durata reale delle risorse, rimborsi limitati e finalizzazione SDK atomica rispetto alla chiusura.

Prosecuzione svolta esclusivamente con Codex: Sol medium/high per interventi e revisioni circoscritte, Astra high per la matrice di sicurezza e la valutazione complessiva. Revisione finale **PASS** dopo la correzione del P2 SDK, **883 test / 83 suite passati**, 285 input finali identici, build Apple Development riuscita, collegamento Applications aggiornato e riavvio verificato (PID 50978). [Verifica finale e prove](../../../docs/superpowers/verification/2026-09-18-addon-asset-message-integration.md), [valutazione indipendente](../../codex-addon/20260918/final-review-round2.md).

Il canale produttivo OS/bootstrap/launcher, la qualifica del decoder contro input ostili, C0d, l’integrazione finale MainActor/SwiftUI e la verifica runtime macOS 14 restano fuori ambito. Nessun altro ticket globale viene chiuso e nessuna release viene pubblicata.
