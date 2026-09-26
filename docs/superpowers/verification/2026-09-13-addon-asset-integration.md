# C5 — integrazione canonica degli asset

## Perimetro implementato

`AddonRuntime` possiede decoder ImageIO/CoreGraphics, coordinatore raster e
`AssetState`, usando lo stesso ResourceGovernor. Import e rilascio controllano
identità verificata, digest, feature, pubblicazione assegnata e connessione corrente.
Il commit di pubblicazioni e riferimenti agli asset è sincrono e atomico dopo
l’ammissione delle risorse. Una richiesta rifiutata non avanza la sequenza.

Le pubblicazioni trattengono tutti i riferimenti dichiarati, anche nelle
rappresentazioni non visibili e nelle voci future della timeline già ammessa e
limitata dall’host. Uscita del provider e rilascio esplicito eliminano gli alias di
importazione, preservando le immagini già pubblicate. Fine, scadenza, disattivazione
e stop revocano l’autorità; le quote dei pixel restano occupate fino all’ultima
referenza CoreGraphics reale.

Il resolver di presentazione conserva la revisione osservata dalla vista e la
inoltra in ogni lookup. Il runtime verifica la revisione canonica e usa il proprio
orologio: il chiamante non può scegliere una data passata per aggirare la scadenza.

## Prove e correzioni

Sono stati osservati fallimenti comportamentali prima delle implementazioni di
riferimenti, stato asset, integrazione runtime, revisione delle viste e rilascio.
Le prime prove con PNG reali hanno anche individuato alias UUID non conformi alla
grammatica dei contenuti; il prefisso host `asset-` risolve il problema.

La revisione e il controllo finale hanno corretto tre regressioni:

- Le pubblicazioni senza asset richiedevano inutilmente metadata aggiuntivi.
  Il caso con quota già piena ora conserva il comportamento preesistente.
- Un import riuscito non drenava un completamento di servizio arrivato durante
  l’ammissione. Il test deterministico osservava esito mancante e quota job ancora
  occupata. Il drenaggio avviene ora prima dell’inserimento finale, conservando la
  prenotazione dei metadata pendenti e ricontrollando l’autorità dopo l’attesa.

Un ulteriore test, dopo l’ammissione della memoria temporanea del messaggio,
ha riprodotto il rifiuto della fine di una pubblicazione con immagini a quota piena.
Fine e sostituzione con contenuto senza immagini ora usano i metadata già prenotati
per le sole rimozioni. Un batch misto continua a prenotare tutti i nuovi riferimenti
prima del commit, senza spendere rimborsi futuri. L’ammissione iniziale del messaggio
rimane invariata.

Log mirati in `/private/tmp`: `cascade-asset-references-{red,green}.log`,
`cascade-asset-state-{red,green}.log`, `cascade-asset-empty-{red,green}.log`,
`cascade-asset-release-{red,green}.log`, `cascade-asset-presentation-{red,green}.log`,
`cascade-runtime-assets-{red,drain-red,release-red,final}.log`,
`cascade-asset-removal-{red,green}.log` e
`cascade-runtime-assets-removal-{red,green}.log`.

Revisione indipendente conclusa senza rilievi aperti. La suite mirata finale del
runtime contiene 37 test; AssetState ne contiene 12. Le prove dei riferimenti
sono 5 e quelle di presentazione 18, inclusi i casi preesistenti di quelle suite.

## Verifica completa e consegna

**536 test Swift passati**, 29 in più della baseline decoder (507), eseguiti con
`--no-parallel` e uscita 0: Runtime 304, Presentation 20, CascadeKit 170,
Contracts 38, Tool 4. Log definitivo:
`/private/tmp/cascade-asset-integration-final-tests.log`.

Sono stati confrontati 350 input di build/test fra workspace e copia locale
`/private/tmp/cascade-asset-integration`, poi congelati nel record
`/private/tmp/cascade-asset-integration-build-inputs.json`. La verifica definitiva
è successiva anche all’ultima formattazione dei test. Nessuna modifica del lavoro
pregresso è stata ripristinata o inclusa in un commit globale.

Build Debug firmata riuscita con `scripts/build-development.sh`; verifica
codesign deep/strict riuscita e `/Applications/Cascade.app` aggiornato alla build
in `CascadeAddonDevelopment/Build/Products/Debug/Cascade.app`.
Log: `/private/tmp/cascade-asset-integration-app-build.log`.
I 350 input sono ancora identici dopo la compilazione.

Chiusura normale e riavvio verificati: PID 60288 terminato, nuova istanza stabile
PID 69877 nel percorso atteso, nessuna terminazione forzata. Record:
`/private/tmp/cascade-asset-integration-restart.json`.
Ultima lettura disponibile del consumo settimanale: 19%, sotto il tetto del 60%.

## Ambiente e limiti

macOS 27.0 beta, build 26A5425a, arm64; Apple Swift 6.4 con Xcode beta.
Il target minimo rimane macOS 14: non è una prova di esecuzione su macOS 14.

I test usano il vero decoder, CGImage e governor, con trasporto e orologio controllati.
Non qualificano addon esterni, firma dei provider, launcher, processi reali,
resistenza del decoder a input ostili o lifetime di vere viste SwiftUI.
Il gate nativo C0d rimane chiuso. Nessun partecipante di tracing è stato avviato.

L’API è interna: ogni import è limitato a una pubblicazione. Prima di fissare il
contratto SDK pubblico resta da scegliere il riuso fra pubblicazioni dello stesso
addon entro ambiti di privacy compatibili. Questo incremento non introduce un
nuovo modello di account: l’autorità delle partizioni dei servizi esiste già nel
broker. Trasporto degli asset, trasferimento snapshot al renderer MainActor,
cache e ripristino persistente restano da integrare. C5 non è dichiarato concluso.
