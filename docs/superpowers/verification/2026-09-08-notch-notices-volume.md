# Verifica forma continua, avvisi e volume

8 settembre 2026 — Xcode beta, SDK macOS 27. Specifica operativa:
[piano](../plans/2026-09-08-notch-notices-volume.md),
[contratti aggiornati](../../architecture/live-activity-contracts.md).

## Risultati verificati

- **81 test CascadeKit in 12 suite superati**, log
  `/private/tmp/cascade-notice-final-tests.log`.
- **28 controlli volume superati** con Swift 6, isolamento MainActor predefinito
  e warning trattati come errori: `zsh scripts/test-volume.sh`.
- Build app Debug completa e firma ad hoc valide; log
  `/private/tmp/cascade-volume-app-build.log`.
- `git diff --check` pulito. Nessun commit o modifica globale agli HUD macOS.
- App finale avviata via CUA; processo verificato al percorso
  `/private/tmp/cascade-volume-derived/Build/Products/Debug/Cascade.app`.
- Render offscreen delle vere factory volume controllato a 0, 6, 37 e 100%:
  icona, testo, barra e percentuale leggibili. Immagine diagnostica locale
  `/private/tmp/cascade-volume-notice-preview.png`; il render verifica il
  contenuto delle ali, non la geometria completa del notch o l'input di sistema.

## Regressioni esercitate

Il vecchio comportamento falliva i test di avviso espanso, replay alla chiusura,
priorità dell'ultimo avviso e ritorno alla sagoma base prima della vista compatta.
La nuova implementazione li supera e sospende le risorse delle viste durante il
passaggio. Sono coperti anche rehover, chiusura immediata, movimento ridotto,
blocco/sblocco e variazioni di larghezza.

La revisione indipendente ha individuato e portato alla correzione di due casi
ulteriori: cambio display con molla compatta già ferma, e attivazione temporanea
di un provider secondario durante il blocco. Entrambe le regressioni sono state
eseguite prima e dopo le correzioni.

Nove test del path confrontano la sagoma con `RoundedRectangle(.continuous)` e
verificano raccordi, simmetria, bounds, raggi nulli e geometrie piccole. I segmenti
nativi vengono memorizzati una volta; nel ciclo di animazione si trasformano e
si emettono dodici cubiche, senza costruire viste SwiftUI.

Il controllo volume verifica decodifica, generazioni, baseline silenziosa,
duplicati, callback fuori MainActor, gesto nativo fino al rilascio, feedback ai
limiti e scadenza della soppressione dei duplicati. Il codice CoreAudio è stato
revisionato per mute master/canali, letture fallite e rollback delle scritture.
L'ultima revisione non ha segnalato problemi residui nel perimetro letto.

## Confini della prova

La sonda facoltativa `zsh scripts/test-volume.sh --probe` legge capability e
crea/invalida immediatamente tap pass-through. Sul processo host già autorizzato
ha confermato lettura dell'output, capacità di controllo e creazione dei tap HID
e di sessione. Non modifica audio, non pubblica eventi e non concede permessi.
Questo esito non dimostra l'autorizzazione TCC dell'app firmata né la soppressione
reale dell'HUD durante la pressione dei tasti.

Per la prova reale, usare il menu Cascade: **Prova avviso volume** non modifica
l'audio; **Consenti Accessibilità per i tasti volume…** apre il percorso dei
permessi. La sostituzione dei tasti richiede l'autorizzazione dell'app. Uscite
non supportate, mute misto o errori mantengono il comportamento di macOS.

CoreAudio non identifica il produttore di un cambiamento. Il filtro di 600 ms
attorno a un gesto passato a macOS limita i duplicati; è un'euristica valutata
solo sugli eventi, senza timer ricorrente. Non garantisce la soppressione di HUD
emessi autonomamente da applicazioni esterne.

## Riproduzione build

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-hig-module-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/cascade-hig-module-cache \
/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift \
test --package-path CascadeKit --scratch-path /private/tmp/cascade-notice-build --disable-sandbox

zsh scripts/test-volume.sh

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild -project Cascade.xcodeproj -scheme Cascade -configuration Debug \
-derivedDataPath /private/tmp/cascade-volume-derived CODE_SIGNING_ALLOWED=YES \
CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build

codesign --verify --deep --strict /private/tmp/cascade-volume-derived/Build/Products/Debug/Cascade.app
```

Riferimenti primari: [curvatura continua Apple](https://developer.apple.com/documentation/swiftui/roundedcornerstyle/continuous),
[event tap Quartz](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)),
[listener CoreAudio](https://developer.apple.com/documentation/coreaudio/audioobjectpropertylistenerblock).
