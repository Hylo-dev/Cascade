# Addon runtime — servizi e checkpoint

Questo rapporto segue la [continuazione direct-v1](2026-09-10-addon-runtime-progress.md). L'utente ha autorizzato il proseguimento sulle parti già progettate. Non è stata modificata la decisione sul lavoro delegato; il launcher nativo rimane non ammesso.

## Parti implementate

### Broker dei servizi C3

Il broker riceve identità verificate e binding scelti dal resolver attraverso API dell'host. Le sessioni sono opache e generano nuove concessioni alla riconnessione. Convalida proprietario, feature, operazione, partizione privata, fornitore/versione e scadenza prima di ammettere le chiamate. Gli interessi sopravvivono all'uscita normale del consumatore; revoca, disattivazione e scadenza li eliminano insieme alle relative concessioni.

Sorgenti compatibili condividono una registrazione e il relativo costo di metadati. Le decisioni di avvio e invocazione vengono consumate una volta sola; una richiesta di arresto resta distinta dall'arresto osservato. Il ResourceGovernor conserva le ammissioni dei processi fino alla conferma dell'uscita. Nessun timer individuale o caricamento di codice addon nel processo grafico. [Contratto dei servizi](../../addons/services.md).

La revisione ha corretto l'ammissione ripetuta di uno stesso requestID di servizio. La cronologia conserva richiesta ed esito per identità verificata durante dieci minuti monotoni, anche dopo la riconnessione; richiede autorizzazione corrente per consultarli e non ritenta i comandi incerti. Riserva spazio per la risposta massima prima dell'invio. I 25 test mirati passano e la revisione delle correzioni non ha rilievi P1/P2 aperti.

Questa è una protezione limitata alla cronologia conservata, non una promessa di esecuzione unica dopo riavvio o rimozione della storia. Il ResourceGovernor non dispone ancora di una riduzione atomica della prenotazione: anche gli esiti piccoli conservano prudentemente la riserva massima fino alla scadenza. Il budget comune di8MiB può quindi rifiutare nuovi comandi prima del limite numerico della cronologia.

### Stato e migrazioni C5

È implementato un salvataggio di checkpoint opachi entro64KiB, con namespace legati a identità/editore, inventario limitato dei file presenti, scrittura preparata e sostituzione atomica. Le migrazioni ricevono un candidato validato e non eseguono codice dell'addon nell'host. I 19 test mirati passano e la revisione delle correzioni è conclusa senza rilievi P1/P2.

Lo spazio già occupato e i file temporanei partecipano alle quote. La revoca di un handle conserva dati e costo su disco; la cancellazione dei dati è un'operazione esplicita. Un checkpoint regolare e limitato ma corrotto o futuro fallisce nel proprio namespace; file sconosciuti, non sicuri o oltre i limiti fanno fallire esplicitamente la riconciliazione.

La revisione ha corretto due difetti: il limite dello schema ora appartiene a ciascuna identità verificata, e i buffer dei checkpoint vengono prenotati soltanto quando occorrono. Il registro ammette fino a256 identità, con un limite riducibile dall'host. Cento identità inattive lasciano spazio a una prenotazione reale di7MiB nello stesso ResourceGovernor. I test coprono anche migrazioni massime aggregate, rifiuto a quota piena e liberazione delle sole proprie risorse, persino quando non resta memoria disponibile per un'altra prenotazione. [Contratto dello stato](../../addons/storage.md).

## Verifica e integrazione

Suite completa **337 test Swift passati**, exit0: Runtime133, Presentation15, motore161, Contracts24, tool4. Sono44 nuovi casi per questo incremento; i5 ulteriori casi del motore provengono dalle modifiche preesistenti preservate. Ambiente: macOS27.0 (26A5425a), arm64, Xcode27.0 (27A5252f). Questi risultati non qualificano l'esecuzione su macOS14.

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/private/tmp/cascade-addon-clang-cache \
swift test --package-path CascadeKit \
  --scratch-path /private/tmp/cascade-addon-swift-build \
  --no-parallel --disable-sandbox
```

Log completo: `/private/tmp/cascade-services-final-swift.log`. Rimane soltanto l'avviso preesistente sulla variabile weak nei vecchi test di PublicationStore. I RED comportamentali e i GREEN mirati sono conservati nei rapporti di esecuzione. Non sono state ripetute le fixture native C0 o le suite Python invariate; i loro risultati precedenti restano storici.

Le revisioni dei due task, delle correzioni e dell'incremento complessivo sono concluse senza rilievi P1/P2 aperti. Integrati18 file esatti con confronto delle versioni precedenti e degli hash revisionati; verificati299 input di build identici fra copia locale e checkout originale. Nessun commit o staging.

Build app **riuscita**, exit0, dalla copia locale verificata tramite `scripts/build-development.sh`, con `CASCADE_DERIVED_DATA=/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeAddonDevelopment`. Firma deep/strict verificata e `/Applications/Cascade.app` aggiornato. Log `/private/tmp/cascade-services-app-build.log`; unico warning della build app: estrazione automatica dei metadati AppIntents saltata in assenza di dipendenza dal framework.

All'avvio finale nessuna istanza precedente della build era aperta, quindi non è stata necessaria una terminazione. Cascade è stata aperta dal collegamento Applications; osservato un unico nuovo processo stabile, **PID83405**, nell'eseguibile atteso di `CascadeAddonDevelopment`. Verifica: `/private/tmp/cascade-services-restart.json`. Gli aggiornamenti operativi successivi alla revisione riguardano soltanto questa documentazione e il riepilogo nel piano. Questo conclude l'incremento servizi/checkpoint, non l'intera feature.

Il controllo iniziale ristretto ha fatto fallire soltanto il vecchio test del popover per NSScreen.main assente. Lo stesso test è passato con accesso alla sessione desktop,9/9. Sono stati preservati nella copia di build anche gli aggiornamenti al motore grafico presenti nel checkout originale, compreso NotchGlassRenderer, senza modificarli.

## Confine del risultato

Queste componenti non costituiscono un runtime nativo ammesso. C3 richiede ancora trasporto autenticato, cache/consegna degli eventi, sorgenti reali e coordinatore. C5 non comprende storage SDK per chiave, asset/decoder isolato o ripristino automatico delle pubblicazioni. Non vengono riprodotti comandi né simulate migrazioni dei widget attraverso codice in-process.

La morte del supervisore può ancora lasciare vivo un processo gestito nelle prove C0. Tale difetto resta fuori dal rischio sul lavoro autonomamente delegato già accettato. Clock, timer e migrazioni successive attendono il percorso reale e le prove richieste dal [piano](../plans/2026-09-10-addon-runtime-completion.md).
