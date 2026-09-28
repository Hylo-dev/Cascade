# Collegamento asset SDK/runtime — prosecuzione Codex

Stato: **completato e consegnato**. Ticket Wayfinder risolto, revisione indipendente PASS, build firmata e riavvio verificati.

## Ambito

Prosecuzione di [Collegare i messaggi asset al runtime e al client SDK](../../../.scratch/cascade-product/issues/23-asset-message-integration.md), sulla [specifica approvata](../plans/2026-09-15-addon-asset-message-integration.md). Il 18 settembre l’utente ha richiesto esclusivamente agenti Codex, con modello/livello scelti secondo difficoltà; resta valida la deroga esplicita alla riserva del 35%. Nessun invio a DeepSeek, commit, staging o reset nella prosecuzione.

Il percorso interno usa frame asset schema 1, negoziazione cumulativa 1.2, connessioni/assegnazioni canoniche, protezione delle allocazioni e il client SDK seriale. I test inoltrano messaggi al runtime reale attraverso un bridge locale di test e usano codec Foundation, assemblatore, ImageIO e AssetState reali.

## Implementazione e prove circoscritte

- **Revoca del solo trasferimento:** fine/scadenza di una pubblicazione non chiude definitivamente l’assemblatore del processo; il suo riuso attende la pulizia precedente. La correzione sospesa è stata confrontata con le preimmagini e approvata dalla [revisione circoscritta](../../../.scratch/codex-addon/20260918/nonterminal-review.md). I test di riuso dopo fine/scadenza passano nelle nuove verifiche di integrazione.
- **Chiusura della connessione:** revoca sessione e import, preserva pubblicazioni/pin durevoli e risorse fisiche/lavoro incerto fino alle osservazioni effettive. Gestisce anche processo già in arresto e quiescenza dell’archivio, autentica gli handle canonici e rende innocue chiusure obsolete/estranee/ripetute. RED→GREEN documentato, ultima verifica: 132 test / 7 suite; [report](../../../.scratch/codex-addon/20260918/connection-report.md) e [revisione con P2 risolto](../../../.scratch/codex-addon/20260918/connection-review.md).
- **SDK e drenaggio:** prove di cancellazione tardiva su release e chiusura concorrente con finish/share/release, con osservazione DEBUG della partecipazione al drain. Una mutazione controllata che rimuove l’attesa fallisce nei tre casi; il sorgente corretto è stato ripristinato esattamente. Ultima verifica: 79 test / 3 suite, di cui 43 SDK/storage e 36 di integrazione; [report](../../../.scratch/codex-addon/20260918/sdk-report.md) e [revisione P2/P3 risolti](../../../.scratch/codex-addon/20260918/sdk-review.md).

I totali sommano tutti i riepiloghi Swift Testing per target. I test parametrizzati possono avere più casi della singola dichiarazione conteggiata. Le verifiche circoscritte non sostituiscono la suite completa finale.

## Correzione emersa dalla revisione finale

La prima [revisione complessiva](../../../.scratch/codex-addon/20260918/review-round1/final-review.md) approva i criteri runtime ma rileva un P2: dopo la validazione della risposta, la conclusione SDK poteva osservare la chiusura, drenarla e restituire comunque successo. La correzione ordina finalizzazione riuscita e chiusura con lo stesso lock. Se vince la chiusura, il client conserva lo slot durante il drain e restituisce `sessionRevoked`; una chiusura successiva a una finalizzazione già riuscita non cambia retroattivamente il risultato. La sola cancellazione tardiva conserva il successo noto.

Il nuovo checkpoint DEBUG dopo validazione ha riprodotto il difetto nei tre casi finish/share/release: compilazione riuscita, exit 1, tre errori di comportamento. Dopo il fix passano **65 test / 2 suite** mirati, compresi i sei casi di chiusura prima/dopo validazione, i tre controlli di successo precedente alla chiusura e le prove esistenti di cancellazione. [Report, preimmagini e comandi](../../../.scratch/codex-addon/20260918/finalization-report.md). La [rivalutazione indipendente](../../../.scratch/codex-addon/20260918/final-review-round2.md) è **PASS**, senza rilievi residui, ed eredita l’accettazione runtime precedente.

## Matrice reale e suite completa

La [matrice di sicurezza](../../../.scratch/codex-addon/20260918/safety-evidence.md) esegue 32 casi parametrizzati di ammissione protetta/frame nativo ImageIO contro arresto, uscita osservata, disabilitazione, fine, scadenza e chiusura esatta, inclusi processo già in arresto e quiescenza. Copre anche identità precedenti/estranee, contesa reale con azioni, decode unico, ultimo prestito CGImage e rimborsi falliti. I checkpoint osservano meccanismi reali; non simulano autorizzazioni, contabilizzazione o immagini decodificate.

Il nuovo test di regressione ha compilato e riprodotto **due tentativi di rimborso dello stesso token in un solo drain**, contro il limite di uno; non si trattava di doppio accredito. La correzione raccoglie gli assemblatori usciti nell’unica fase finale del drain e conserva il proprietario del token quando il rimborso fallisce. [Report e comandi](../../../.scratch/codex-addon/20260918/safety-report.md).

- Verifica mirata: **268 test / 25 suite**, exit 0.
- Suite completa con accesso alla sessione grafica: **883 test / 83 suite**, exit 0, zero problemi: runtime 578/48, presentation 66/7, CascadeKit 170/19, contracts 65/8, tool 4/1. [Audit dei cinque target](../../../.scratch/codex-addon/20260918/root-test-audit.json), [log](../../../.scratch/codex-addon/20260918/finalization-full.log), [status](../../../.scratch/codex-addon/20260918/finalization-full.status).
- Il primo full run nella sandbox aveva due fallimenti nello stesso test UI parametrizzato, per `NSScreen.main == nil`. Il secondo run passava 882 test sugli stessi sorgenti con accesso alla sessione grafica; dopo il fix SDK la nuova suite completa ne passa 883: nessuna modifica UI, esclusione o indebolimento dei test. Il log originale resta conservato.
- Quattro documenti pubblici aggiornati e 22 collegamenti locali verificati. I limiti del canale iniettato e la finalizzazione atomica rispetto alla chiusura SDK sono espliciti.
- **285 input finali congelati**, con hash, copie e diff contro baseline dirty di ripresa e originale; nessun drift alla verifica root. [Manifest](../../../.scratch/codex-addon/20260918/final-manifest.json), [delta](../../../.scratch/codex-addon/20260918/final-delta.json). `git diff --check` riuscito.

## Revisione e consegna

Revisione indipendente finale Codex Astra high **PASS** sugli input congelati. [Verdetto](../../../.scratch/codex-addon/20260918/final-review-round2.md).

Build Debug eseguita con `scripts/build-development.sh`, Xcode beta e DerivedData `CascadeAddonDevelopment`: **BUILD SUCCEEDED**, exit 0, verifica `codesign --verify --deep --strict` riuscita. Firma Apple Development prevista dal progetto; nessuna firma ad hoc. Lo script ha aggiornato `/Applications/Cascade.app` alla build compilata. [Log](../../../.scratch/codex-addon/20260918/build.log), [status](../../../.scratch/codex-addon/20260918/build.status).

La prima build era ferma prima della compilazione in `NSFileCoordinator` durante la lettura del progetto iCloud. È stata interrotta con SIGINT (exit 130), senza terminare Cascade o servizi di sistema. Recuperati i 126 file dataless, la build riuscita usa una copia locale di **408 file identici** in `/private/tmp/cascade-addon-delivery-20260918`, con lo stesso script, configurazione e DerivedData. [Manifest della copia](../../../.scratch/codex-addon/20260918/build-snapshot-manifest.json), [diagnosi](../../../.scratch/codex-addon/20260918/build-wait.sample.txt), [tentativo interrotto](../../../.scratch/codex-addon/20260918/build-icloud-blocked.log). Un primo tentativo dalla copia locale è fallito per `Config/Cascade-Info.plist` omesso nella copia (exit 65); il file originale è stato aggiunto invariato prima della build riuscita. [Log conservato](../../../.scratch/codex-addon/20260918/build-snapshot-incomplete.log). Verificata nuovamente l’identità dei 408 file tra checkout e copia dopo la build.

Cascade è stata chiusa normalmente e riaperta dal collegamento Applications. Verificati un unico processo nuovo, **PID 50978**, percorso eseguibile esatto e stabilità per cinque secondi. [Evidenza di riavvio](../../../.scratch/codex-addon/20260918/restart-evidence.json). Tutti i 285 input revisionati restano identici dopo build e riavvio.

Risolto soltanto [Collegare i messaggi asset al runtime e al client SDK](../../../.scratch/cascade-product/issues/23-asset-message-integration.md). Le altre decisioni restano aperte secondo le proprie dipendenze.

## Provenienza e limiti

[Baseline e avanzamento Codex](../../../.scratch/codex-addon/20260918/ledger.md): 285 input iniziali copiati con hash; le 19 preimmagini originali modificate sono state recuperate da iCloud e verificate. I diff includono i sorgenti originariamente untracked; HEAD da solo non rappresenta il delta. Lo stato dirty preesistente è conservato.

Nessun adattatore OS, bootstrap autenticato produttivo, qualifica del processo decoder/launcher, verifica runtime macOS 14, integrazione finale MainActor/SwiftUI o distribuzione viene dichiarato completato. C0d resta chiuso e questa tranche non completa l’intera piattaforma addon.
