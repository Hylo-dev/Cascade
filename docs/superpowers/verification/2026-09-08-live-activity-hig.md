# Verifica dell'adattamento alle HIG Live Activities

Data: 8 settembre 2026. Toolchain: Xcode beta, SDK macOS 27.
Contratto di riferimento: [attività e avvisi del notch](../../architecture/live-activity-contracts.md).

## Risultati

- CascadeKit: **62 test superati in 11 suite**, inclusi host, controller,
  geometria, hit testing, aptica e snapshot musicali.
- Regressione verificata prima e dopo la correzione: spostare `startedAt`
  attraverso `present` o `invalidate` non prolunga il limite della sessione;
  un inizio futuro non consente più di otto ore di permanenza.
- Build Debug completa dell'app: riuscita; firma ad hoc verificata con
  `codesign --verify --deep --strict`.
- `git diff --check`: nessun errore.
- Revisione indipendente di lifecycle, scheduler, privacy, selezione della
  seconda attività, dimensionamento e provider: nessun blocco residuo.
- App avviata dal percorso esatto della build e riavviata dopo la correzione
  finale del tema scuro. Osservati il notch, il menu applicativo e la gerarchia
  accessibile dell'anteprima musicale estesa con titolo, artista, play/pausa e
  progresso. Nessuna integrazione musicale reale viene dichiarata verificata.

## Comandi riproducibili

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-hig-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cascade-hig-module-cache \
/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift \
test --package-path CascadeKit --scratch-path /private/tmp/cascade-hig-build --disable-sandbox

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project Cascade.xcodeproj -scheme Cascade -configuration Debug \
-derivedDataPath /private/tmp/cascade-hig-derived CODE_SIGNING_ALLOWED=YES \
CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build

codesign --verify --deep --strict /private/tmp/cascade-hig-derived/Build/Products/Debug/Cascade.app
git diff --check
```

Log della sessione: `/private/tmp/cascade-hig-tests.log` e
`/private/tmp/cascade-hig-app-build.log`. I warning riguardano cache SwiftPM
non scrivibili nel sandbox e assenza della dipendenza AppIntents; nessun errore
di compilazione.

## Limiti delle verifiche

Le prove automatiche verificano decisioni di rendering, redazione prima delle
factory, revoca dei contesti, scadenze, dimensioni e arresto dell'animazione.
Non misurano la percezione dell'aptica, non sostituiscono una prova VoiceOver
completa e non dimostrano il funzionamento dei link di un futuro provider.
L'override del banner Bluetooth nativo richiede ancora una prova con evento
reale e autorizzazione Accessibilità. Questo lavoro non modifica il monitor
Bluetooth o il soppressore nativo.
