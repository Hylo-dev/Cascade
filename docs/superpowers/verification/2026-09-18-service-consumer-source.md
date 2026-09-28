# Verifica dell’esempio sorgente ServiceConsumer — 18 settembre 2026

**PASS nel perimetro dell’esempio sorgente, inclusi i miglioramenti ai test.** Creato un package indipendente con tre librerie: contratto condiviso, provider di un valore sintetico e consumer. Il valore 3 è un dato dimostrativo, non una cronologia reale né un servizio esposto da StandaloneFocus. [Esempio e istruzioni](../../../Examples/ServiceConsumer/README.md).

## Evidenze

- Build indipendente riuscita; due manifest reali validati. Dipendenze effettivamente raggiungibili: CascadeAddonSDK, CascadeContracts e CascadePresentation pubblica transitiva. Il consumer non dipende dall’implementazione del provider.
- Prima suite: 14 test passati e revisione indipendente PASS, senza rilievi P1/P2. Due P3 sui test sono stati corretti senza cambiare i sorgenti di produzione: rendezvous causale fra invocazione e completamento anticipato, pulizia dei task sospesi e controllo dei codici d’errore specifici.
- Suite corretta: **16 test Swift Testing passati**. Nessun polling con yield o attesa basata su ritardi arbitrari. La regressione del rendezvous è stata verificata con una mutazione soltanto del test esterno; un precedente errore di compilazione è conservato e non presentato come RED comportamentale.

[Handoff iniziale](../../../.scratch/codex-addon/20260918-continuation/service-consumer-report.md), [revisione indipendente](../../../.scratch/codex-addon/20260918-continuation/service-independent-review.md), [addendum finale PASS](../../../.scratch/codex-addon/20260918-continuation/service-independent-review-addendum.md), [correzioni ai test](../../../.scratch/codex-addon/20260918-continuation/service-review-fix-report.md), [hash finali](../../../.scratch/codex-addon/20260918-continuation/service-review-fix-final-hashes.json), [16 test](../../../.scratch/codex-addon/20260918-continuation/service-review-fix-final-tests.log), [build librerie](../../../.scratch/codex-addon/20260918-continuation/service-final-build.log).

Il consumer controlla assegnazione, grant forniti, scope, generazione e scadenze civili; valida il payload limitato prima della pubblicazione finita. Stop e cancellazione durante una risposta sospesa ne impediscono la pubblicazione. Le completion del servizio appartengono al provider/trasporto, mentre il refresh del consumer non inventa una completion per la chiamata in uscita.

## Limiti

I grant sono snapshot forniti dall’host: versione del provider, consenso, risoluzione REQUIRES, revoca canonica e trasporto autenticato non sono dimostrati dalle fixture. Le revisioni del consumer sono locali a una nuova assegnazione, senza ripristino della cronologia. Nessun eseguibile, firma, installazione o controllo di processi nativi; C0d invariato.

Le prove iniziali usano il package SDK congelato di 62 input. La [consegna del client storage](2026-09-18-addon-storage-message-client.md) ha poi verificato nuovamente questo esempio contro i 64 input pubblici aggiornati in una copia completa del package, con tutti i test passati. La medesima consegna include build firmata dell’app e riavvio verificato; l’esempio resta una libreria sorgente. I limiti completi sono nel README e nei report collegati.
