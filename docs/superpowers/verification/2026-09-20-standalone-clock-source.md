# StandaloneClock — incremento sorgente

20 settembre 2026. [Ticket e ambito](../../../.scratch/cascade-product/issues/44-standalone-clock-source.md).

## Consegna

[StandaloneClock](../../../Examples/StandaloneClock/README.md) è una libreria SwiftPM indipendente, con manifest validato e provider che usa soltanto CascadeAddonSDK/CascadeContracts. Pubblica ora e minuti in forma dichiarativa, con identità assegnata dall'host e revisione monotona. Non crea tick o lavoro residente: il disegno dell'orologio appartiene all'host. La scadenza di ogni pubblicazione è 24 ore; il provider non pianifica un rinnovo.

Implementazione Sol medium, revisione e integrazione root con Ponytail. Il controllo SDK include esplicitamente il nuovo package; la build ufficiale eredita automaticamente questo controllo prima della compilazione.

## Evidenze

Le prove complete e il diff circoscritto sono in [20260920-clock-source](../../../.scratch/codex-addon/20260920-clock-source/).

- Build della copia indipendente e **3 test Swift**: PASS, ripetuti dal root. Manifest, pubblicazioni e ricreazione con revisione precedente, azioni sconosciute, assegnazioni errate, eventi finiti e stop, tempo non finito ed esaurimento revisioni. Tutti i client di capacità falliscono se invocati.
- Confronto SDK: **78 sorgenti pubblici identici** agli input dell'audit corrente; nessun target privato nella fixture SDK.
- Build protetta: **5 fixture PASS**, incluso un import privato aggiunto a Clock che ferma lo script prima della build/firma/aggiornamento Applications. La fixture positiva raggiunge intenzionalmente un progetto Xcode assente, senza compilare l'app.
- Audit sul checkout: **4 package / 11 target / 90 sorgenti Swift / 140 import, PASS**. Input ricontrollati dopo la consegna: invariati.
- Suite completa del checker: **21 test PASS, nessuno saltato**, in 317 secondi. Il record del riavvio resta distinto dalle prove sorgente.

La prima invocazione delle fixture build mancava del DEVELOPER_DIR richiesto e ha fallito nel setup; il log è conservato separatamente. L'empty-target iniziale del worker non è una regressione comportamentale. Il nuovo controllo del manifest Clock è invece verificato RED→GREEN: prima raggiungeva la valutazione del toolchain senza controllare Clock, ora rifiuta subito un suo manifest mancante.

## Limiti

Il macOS minimo dichiarato resta 14; le prove sono locali con Xcode-beta su macOS27 arm64. Nessuna qualifica di altri OS, processo addon nativo, firma di un contenitore, uscita fisica, trasporto OS o parità bundled/external. Il ClockWidget produttivo e la composizione dell'app restano quelli precedenti. Il launcher e C0d rimangono bloccati. C6 non è concluso.

Non essendoci cambiamenti al codice dell'app, questa consegna non produce un nuovo binario Cascade. Il riavvio usa la build di sviluppo firmata già collegata in /Applications. Le cache temporanee del build/test Clock sono eliminate dopo la verifica, conservando copia sorgente, hash, comandi e risultati.

Riavvio concluso: firma deep/strict verificata, chiusura normale PID90193, nuovo PID34140 dal percorso Applications atteso, stabile per5 secondi. [Record](../../../.scratch/codex-addon/20260920-clock-source/restart-evidence.json). Ultimo budget osservato3% settimanale, sotto20%. Nessun agente lasciato attivo.
