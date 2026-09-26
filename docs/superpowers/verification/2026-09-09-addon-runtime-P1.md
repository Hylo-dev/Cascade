# P1 — contratti, SDK e presentazioni

Implementazione avviata il 9 settembre 2026 nel worktree isolato `codex/addon-runtime`,
conservando lo stato precedente del progetto. Questo rapporto distingue la libreria
implementata dal runtime di processi, che rimane subordinato alle prove P0.

## Codice disponibile

- **CascadeContracts:** manifest e protocollo versionati, identità, revisioni,
  permessi/lease come valori, richieste/risposte correlate e rifiuto di dati fuori limite.
- **CascadePresentation:** componenti Swift per testo, simboli, immagini ammesse,
  righe/colonne, progresso, clock/countdown e pulsanti identificati; renderer SwiftUI
  condiviso con le preview. Nessuna serializzazione di viste arbitrarie o closure.
- **CascadeAddonSDK:** handler async e contesto con soli client storage/servizi,
  eventi e concessioni di connessione. I client sono interfacce; il trasporto non è
  sostituito da esecuzione del provider nel processo grafico.
- **CascadeRuntime / Resolution:** decisioni pure e deterministiche per addon e
  singole feature, versioni di servizio, dipendenze cicliche, ordine di avvio, vecchi
  binding, identità verificata e consenso separato per servizi di un altro editore.
  Il piano restituito non installa, avvia né concede permessi automaticamente.
- **CascadeRuntime / Publications:** stato posseduto dall'host entro 8 MiB contabili,
  quote di istanze, attività e avvisi, timeline finite e scadenze, sessioni terminate
  non riutilizzabili. Il produttore può sparire senza cancellare i valori ricevuti.
- **CascadeKit / AddonPresentation:** adattamento dei valori al notch, identità
  separate dalle integrazioni esistenti, privacy prima delle viste, riferimenti ad
  asset ammessi e contesti/azioni revocabili. Nessun provider entra in queste factory.

La documentazione pubblica è in [protocol.md](../../addons/protocol.md),
[manifest.schema.json](../../addons/manifest.schema.json),
[content.md](../../addons/content.md) e [requires.md](../../addons/requires.md).
I prodotti nuovi mantengono macOS 14 e usano Swift 6; il motore esistente conserva
la propria modalità Swift 5 con isolamento MainActor.

## Verifiche e limiti

La verifica finale dell'intero package passa: **230 test, zero fallimenti**, con
`--no-parallel`. Sono 35 test Runtime (28 resolver, 7 pubblicazioni), 15 Presentation/SDK,
156 del motore/bridge (17 nuovi del bridge) e 24 Contracts: 91 test aggiunti alla baseline.
La revisione indipendente del resolver ha ripetuto anche tre riproduzioni esterne,
confermando rollback coerente, profondità massima e rifiuto di vincoli incompatibili.

Comando finale, eseguito con esito 0:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-addon-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cascade-addon-swift-cache \
xcrun swift test --disable-sandbox --package-path CascadeKit \
  --scratch-path /private/tmp/cascade-addon-final-tests --no-parallel
```

Log della sessione: `/private/tmp/cascade-addon-all-verified.log`. Una verifica mirata
precedente passa 90 test; la suite completa include anche la prova di preview esclusa
per nome da quel filtro. Il test contiene un warning di compilazione sulla variabile
weak del produttore di fixture; non è un warning del codice Runtime.

Le esecuzioni concorrenti della baseline e della revisione avevano mostrato un
fallimento temporale preesistente in `controlDragKeepsExpandedContentAliveUntilMouseUp`
(`NotchControllerTests.swift:924`). Il caso passa isolato e nel run finale sequenziale
in 290 ms. Non abbiamo modificato il trascinamento né quel test per nascondere il
risultato; rimane da indagare l'interferenza della suite concorrente.

Le correzioni con regressioni comportamentali comprendono messaggi Unicode troppo
grandi, accessibilità dei contenuti, scope dei servizi, rollback di dipendenze annidate,
limiti sulle catene già ammesse, vincoli congiunti dello stesso servizio, resurrezione
di sessioni terminate e perdita dell'identità di pubblicazioni future. La ricerca usa
scelte in un array limitato per evitare di esaurire lo stack con congiunzioni ampie.
Una prova Store → bridge verifica contenuto presente, futura revisione in attesa,
attivazione alla scadenza e cancellazione definitiva delle voci future al disable.

La [preview del renderer](assets/addon-content-preview.png) è stata prodotta e ispezionata. È una fixture di componenti, non il layout definitivo di un widget. VoiceOver nel pannello,
preferenze di movimento/trasparenza ridotti e consumi con superfici visibili/nascoste
restano **non qualificati**. Nessun test di immagine statica viene presentato come
misura energetica o validazione della scena remota.

Lo scheduler che alimenterà le deadline, il broker, storage/asset completi, il catalogo,
la scena SwiftUI remota e la migrazione Clock/Focus/avvisi/media appartengono alle fasi
successive. Gli addon del team dovranno usare lo stesso SDK e gli stessi controlli;
nessun percorso privilegiato è stato aggiunto per anticipare la migrazione.

Il [gate P0](2026-09-09-addon-runtime-P0.md) resta aperto e impedisce di presentare
questo lavoro come runtime addon completo o come efficienza già qualificata.

## Build e integrazione

Il codice produttivo del motore dipende da Contracts e Presentation. Runtime è usato
nel test di integrazione, non importato dalle factory del notch. L'adattamento è
compilabile ma la composizione app → scheduler → bridge appartiene ancora a P3.
La reintegrazione conserva i file preesistenti e verifica i loro hash prima della copia.
Reintegrati **106 file verificati** senza conflitti; gli hash dei file preesistenti
fuori da questo intervento sono rimasti invariati.

Build finale dal checkout principale, esito **BUILD SUCCEEDED** e firma verificata:

```sh
CASCADE_DERIVED_DATA=/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeAddonDevelopment \
/bin/zsh scripts/build-development.sh
```

Lo script ha aggiornato `/Applications/Cascade.app` alla build appena compilata.
Verificati chiusura normale del vecchio processo PID 32179 e avvio del nuovo
PID 49632 dall'eseguibile `CascadeAddonDevelopment/Build/Products/Debug/Cascade.app`.
Log di sessione: `/private/tmp/cascade-addon-integrated-build.log` e
`/private/tmp/cascade-addon-restart.json`. Questi PID descrivono la verifica,
non sono identificatori da riutilizzare per controllare processi futuri.

### Chiusura della verifica, 10 settembre

Aggiunti 23 file delle alternative P0: il totale reintegrato è 129 file, senza conflitti
e senza variazioni ai file preesistenti fuori da questo intervento. Il codice P1 e i
suoi test non sono cambiati dopo il run completo da 230 test. I nuovi prototipi restano
separati dal package produttivo e mantengono il profilo di contenimento non superato.

Ultima build dal checkout principale: **BUILD SUCCEEDED**, log
`/private/tmp/cascade-addon-final-app-build.log`; firma e collegamento Applications
verificati. Chiusa normalmente l'istanza PID 49632 e osservato l'avvio del PID 56980
nel percorso CascadeAddonDevelopment previsto. Nessun processo delle fixture è
rimasto aperto. Evidenza: `/private/tmp/cascade-addon-final-restart.json`.
