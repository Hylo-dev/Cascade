# Addon runtime — luci, sessioni e memoria dei risultati

Continuazione di [servizi e checkpoint](2026-09-10-addon-services-storage.md). L’utente ha chiesto di verificare la sua estensione per l’effetto di luce, correggerla se necessario e proseguire sulle parti già progettate. Nessuna nuova concessione sul controllo dei processi. **Incremento implementato e revisionato: 385 test Swift passati, build firmata riuscita e riavvio verificato.**

## Luci dell’utente preservate

Sono stati confrontati e copiati nella worktree locale 25 file aggiornati dall’utente: GlassLight, schema 2 di ContentDocument, preferenze SwiftUI, raccolta e invalidazione delle sorgenti, renderer e risposta musicale. Ogni copia è stata preceduta dal controllo della versione locale. Nessuna correzione alla sua implementazione è risultata necessaria.

La revisione ha verificato valori e limite di otto luci, compatibilità con lo schema 1, pulizia delle sorgenti sostituite, nascoste o sensibili, protezione dalle consegne tardive, assenza di timer o cattura aggiuntiva e colore statico in pausa e con movimento ridotto. Il contratto rimane quello scelto dall’utente. [Guida delle luci](../../architecture/glass-lighting.md).

La baseline con queste modifiche ha superato **360 test Swift**, exit 0: Runtime 133, Presentation 20, motore 169, Contracts 34, tool 4. I 23 casi in più rispetto alla precedente verifica di 337 provengono dal lavoro dell’utente. È passato anche `scripts/test-music-glass-light.sh`, exit 0. Log: `/private/tmp/cascade-light-baseline-swift.log` e `/private/tmp/cascade-light-baseline-music.log`.

## C1a — negoziazione e pubblicazioni

La libreria supporta il protocollo 1.0 e gli schemi di contenuto 1/2. Ogni connessione concorda un sottoinsieme compatibile con l’offerta del provider e il requisito del manifest verificato dall’host. Tutte le rappresentazioni, comprese quelle future della timeline, devono usare uno schema concordato. Lo schema 2 resta necessario anche quando non contiene luci: niente rimozione implicita dell’effetto o cambio di versione del documento.

`PublicationStore` conserva l’autorità della connessione, la generazione, la sequenza e gli ID assegnati dall’host. Valida il messaggio prima di modificare le pubblicazioni e aggiorna la sequenza soltanto dopo un batch riuscito. Il rifiuto conserva contenuti e revisioni precedenti. La normale chiusura conserva storia e contenuti; la sostituzione invalida il vecchio handle, e la rimozione dell’owner revoca l’autorità prima di cancellare lo stato.

Il registro ammette al massimo 32 connessioni attive e 256 namespace di publisher, con limiti riducibili dall’host e addebiti locali di 4.096 e 1.024 byte. Non prealloca buffer per tutti gli addon installati. Questi addebiti usano il budget locale dello store; il collegamento al limite comune del runtime resta da fare.

I **41 test mirati** sono passati, exit 0: 18 nuovi casi e 23 esistenti. I test nuovi hanno mostrato fallimenti comportamentali prima dell’implementazione. La revisione di specifica e qualità è approvata senza P1/P2. Una successiva verifica mirata ha individuato due scansioni e codifiche JSON ridondanti nel controllo degli schemi: le due chiamate duplicate sono state rimosse, conservando i controlli di ammissione, e gli stessi 41 test mirati sono passati nuovamente. Non è una misura di prestazioni o consumo energetico.

L’identità verificata, il digest e gli ID ammessi provengono dall’host. Il nuovo confine non verifica firme o audit token, non decodifica frame del trasporto e non esegue operazioni di servizio. Restituisce operazioni, completion e checkpoint come valori controllati: soltanto le pubblicazioni vengono applicate. Anche `endPublication` resta un’operazione da autorizzare e applicare nel futuro coordinatore. [Guida delle sessioni](../../addons/sessions.md).

## C4a — capacità inutilizzata restituita al budget

`ResourceGovernor.reduceStateReservation` riduce una prenotazione di stato già esistente in un’unica operazione, senza liberarla e riaprirla. Verifica proprietario e prenotazione canonici, ammette soltanto riduzioni e conserva i 1.024 byte di metadati della prenotazione fino al rilascio effettivo. Funziona anche quando il budget è completamente pieno. Non modifica quote di processi, lavori, asset o disco.

Prima dell’invio il broker riserva ancora input, metadata e tutta la possibile risposta da 65.536 byte. Dopo un esito definitivo conserva input, metadata e risultato reale, restituendo lo spazio inutilizzato. Una risposta di tre byte restituisce quindi 65.533 byte al budget. La risposta e l’ID rimangono conservati per i dieci minuti originari: nessuna nuova autorizzazione a ripetere il comando.

Risposta, errore, timeout, disconnessione e revoca usano gli eventi già esistenti per il recupero. Il relativo flag vive nel record della richiesta, entro i limiti di 128 record per owner e 1.024 globali; nessun nuovo timer, task o controllo periodico. L’esito diventa definitivo prima dell’attesa sul governor. Recuperare un risultato ripete dopo l’attesa i controlli su permesso, connessione, binding e scadenza. Scadenza e shutdown non ricreano record rimossi; le riserve del processo restano fino alla sua uscita osservata.

Sono passati **42 test mirati in tre suite**, exit 0, con sette nuovi casi. Coprono quota piena, risultato massimo e piccolo, nove eventi terminali, revoca prima e dopo il recupero, binding cambiato e cleanup concorrente con risorse estranee conservate. Log finale: `/private/tmp/cascade-reduction-final.log`. Il preciso punto di sospensione durante una revoca è una verifica del codice: non è stato introdotto un finto governor o un aggancio di test per forzare quell’ordine. Revisione indipendente di specifica e qualità approvata senza P1/P2; controllata anche la rivalidazione dopo l’attesa sul governor. [Guida dei servizi](../../addons/services.md).

## Verifica finale e limiti

La suite completa successiva alle modifiche ha superato **385 test**, exit 0: Runtime 154, Presentation 20, motore 169, Contracts 38, tool 4. Sono 25 nuovi casi di questo incremento rispetto alla baseline con le luci dell’utente. Log: `/private/tmp/cascade-light-sessions-final-swift.log`. Tutti i 25 file della modifica alle luci conservano il contenuto verificato nella baseline.

La revisione finale di integrazione ha approvato specifica e qualità senza rilievi aperti P1/P2/P3. Sono stati integrati 21 file con controllo preventivo degli hash nel checkout originale; i 318 input di build corrispondono alla worktree compilata. Nessun commit o staging.

`scripts/build-development.sh` è terminato con exit 0 usando Xcode beta e DerivedData `CascadeAddonDevelopment`. La verifica della firma `--deep --strict` è riuscita e `/Applications/Cascade.app` punta alla nuova build. Log: `/private/tmp/cascade-light-sessions-app-build.log`.

La precedente istanza, PID 89540, è stata chiusa normalmente senza arresto forzato. La nuova istanza, **PID 94732**, è stata osservata attiva e stabile con eseguibile in `CascadeAddonDevelopment/Build/Products/Debug/Cascade.app`. Il riavvio riguarda la versione aggiornata, non la precedente build `CascadeDevelopment`. Evidenza: `/private/tmp/cascade-light-sessions-restart.json`.

Durante la preparazione dei test il disco pieno ha interrotto una compilazione prima dell’esecuzione: non è contato come RED. Sono state rimosse soltanto cache temporanee SwiftPM di questo lavoro, verificandone tag, riferimenti a CascadeKit e assenza di processi utilizzatori; sorgenti, log e build dell’app sono conservati.

Rimane l’avviso preesistente `weakProducer` nei vecchi test di PublicationStore. Questa verifica non misura energia o memoria fisica e non qualifica VoiceOver o il minimo macOS 14 su un altro sistema.

**La feature nativa resta incompleta.** C0 non è ammesso: la morte del supervisore può lasciare vivo un worker gestito. L’accettazione del lavoro autonomamente delegato al sistema non copre quel caso. Trasporto reale, crediti dei frame, identità nativa, coordinatore comune, avvio dei provider e migrazione dei widget restano da collegare e qualificare. Il [piano di completamento](../plans/2026-09-10-addon-runtime-completion.md) mantiene aperte queste fasi.
