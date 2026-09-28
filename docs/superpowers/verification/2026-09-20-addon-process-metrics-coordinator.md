# Coordinatore delle osservazioni addon — consegna del 20 settembre 2026

**Esito: PASS per la componente interna**, dopo revisione root e revisione indipendente Sol medium con un giro di correzioni. Il [ticket Wayfinder](../../../.scratch/cascade-product/issues/45-process-metrics-coordinator.md) è concluso; C4 nel suo complesso e il launcher restano aperti/bloccati.

## Incremento consegnato

`ProcessMetricsCoordinator` raggruppa registrazioni osservative esplicite e riusa `ProcessMetricsReader`/`ProcessMetricsReducer`. Un solo deadline periodico, inizialmente 1 Hz e mai più frequente, nessun recupero di tick persi e disarmo a insieme vuoto. Campioni su confini dei job o pressione non rinviano il deadline periodico. Identità e token conflittuali sono rifiutati; registrazioni duplicate conservano la baseline; rimozione esatta non tocca una sostituzione. Una lettura mancante non equivale a zero e non blocca le altre.

Il componente serializza le letture nel proprio actor ma non installa timer/task né viene collegato all’app o all’autorità dei processi. Capacità osservativa massima 1.024 registrazioni, default 4: non è ammissione di nuovi processi né una quota aggiuntiva del governor. Identità discordante/uscita osservativa ritirano soltanto la registrazione, senza liberare riserve o dimostrare uscita fisica.

## Verifica

- Terra medium: ricognizione circoscritta della frontiera. Sol medium: implementazione; un secondo Sol medium: revisione indipendente; root: lettura del codice, confronto requisiti, correzioni richieste e replay dell’intera suite.
- 47 test metriche in 2 suite PASS, inclusi 14 nuovi test del coordinatore. Prima il normale scaffold compilabile falliva comportamentalmente; la regressione frazioni di nanosecondo ha fallito con 5 aspettative prima della correzione.
- **1.098 test package in 97 suite PASS**, comando `swift test --disable-sandbox --package-path CascadeKit --scratch-path /private/tmp/cascade-addon-tests --skip-build --no-parallel`, toolchain Xcode-beta, nella sessione desktop. Gli stessi target sono stati compilati dal comando mirato prima del replay.
- La baseline era 1.084 test. Due aspettative AppKit `NSScreen.main` non passavano nella sandbox; gli stessi binari sono passati nella sessione desktop, senza modifiche a quei test.
- La revisione ha corretto l’avanzamento del clock nelle registrazioni duplicate, i valori temporali estremi, la perdita di precisione sub-nanosecondo e un ciclo di ritenzione nella fixture. Il codice finale conserva `Duration` direttamente con aritmetica limitata. Nessun rilievo importante residuo.
- Lettore esistente byte-identico; hash finali dei tre file revisionati conservati. Nessun’altra sorgente preesistente tra i 388 input iniziali è stata modificata.

## Build e avvio

La prima build ufficiale è rimasta prima della compilazione in `NSFileCoordinator`, durante la lettura del progetto iCloud. Un campione di un secondo documenta l’attesa; è stato interrotto soltanto il relativo `xcodebuild`.

La stessa build ufficiale è poi riuscita su una copia locale con **479 input verificati identici prima e dopo la build**. Controllo SDK: 4 package, 11 target, 90 sorgenti Swift, 140 import PASS. `scripts/build-development.sh`, firma Apple Development e `codesign --verify --deep --strict` PASS. Lo script ha aggiornato `/Applications/Cascade.app` alla build in `CascadeDevelopment/Build/Products/Debug/Cascade.app`.

Chiusura normale e riavvio verificati: PID 10620 → **18882**, eseguibile corrispondente al link Applications e stabilità per 5 secondi. Nessun nuovo processo addon o prototipo nativo è stato attivato.

[Evidenze, log e hash](../../../.scratch/codex-addon/20260920-wayfinder-continuation/root-review.md); [revisione indipendente finale](../../../.scratch/codex-addon/20260920-wayfinder-continuation/task-45-rereview.md); [risultato avvio](../../../.scratch/codex-addon/20260920-wayfinder-continuation/delivery.json).

## Confine e punto di arresto

Rimangono binding nativo canonico, azionamento dal wakeup comune, integrazione del governor/salute, enforcement e prova reale dei processi. Non sono qualificati macOS14/Intel, consumo del supervisore o profili continui.

L’utente richiede arresto a una scelta progettuale oppure sotto il 75% di budget residuo. Residuo osservato alla consegna: **93%** (7% consumato). L’arresto riguarda la [semantica del burst CPU](../../../.scratch/cascade-product/issues/46-addon-cpu-burst-policy.md): la specifica non definisce come 100ms/job convivano con 50ms/10s. Nessuna politica è stata selezionata o implementata. Il launcher resta bloccato per la decisione già acquisita, senza riproporla.
