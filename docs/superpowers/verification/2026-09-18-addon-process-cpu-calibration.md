# Calibrazione indipendente delle unità CPU — 18 settembre 2026

**PASS sul percorso di lettura e riduzione, limitato a macOS27 arm64 e al processo della prova.** Copie identiche dei due sorgenti di produzione sono state compilate con un diagnostico locale. Il lettore nativo acquisisce i contatori; il riduttore applica la conversione Mach. Il riferimento `getrusage(RUSAGE_SELF)` somma separatamente secondi e microsecondi di utente/sistema, senza riusare timebase o contatori Mach per costruire il riferimento.

## Risultati

Timebase effettivo125/3, Swift6.4 e SDK CLT27.0, macOS27.0 build26A5425a. I valori convertiti sono tutti dentro gli intervalli del riferimento; non è stata necessaria la tolleranza di2000µs dichiarata prima della prova.

| Campione | CPU del riduttore, µs | Intervallo POSIX, µs | CPU / tempo acquisizioni |
| --- | ---: | ---: | ---: |
| 1 | 150064,791 | 150062–150074 | 99,998473% |
| 2 | 150021,583 | 150016–150027 | 100,000111% |
| 3 | 150020,666 | 150014–150027 | 97,002418% |

I riferimenti sono acquisiti prima e dopo ogni lettura. L’intervallo della differenza è `[prima corrente − dopo precedente, dopo corrente − prima precedente]`; ampiezze12,11 e13µs. Il lieve superamento del100% nel secondo campione rientra nell’incertezza di acquisizione/quantizzazione. I controlli negativi sui medesimi dati rifiutano tick trattati come nanosecondi, come microsecondi o convertiti con timebase inverso: nessun carico ulteriore.

Tre carichi seriali hanno registrato circa0,45s di CPU; il valore454435µs è la CPU dalla nascita **all’ultima acquisizione**, non la misura esatta all’uscita. Il runner ha atteso l’uscita normale con status0 in0,6898s. La compilazione separata è durata33,93s. I limiti del workload e i timeout sono guardie diagnostiche, non un meccanismo di enforcement CPU del processo. Cache privata rimossa; nessuna modifica a produzione, test o app.

[Rapporto e sonda preservati](../../../.scratch/codex-addon/20260918-continuation/cpu-calibration-evidence/cpu-calibration-report.md), [osservazioni grezze](../../../.scratch/codex-addon/20260918-continuation/cpu-calibration-evidence/cpu-calibration-observations.json), [sorgente diagnostico](../../../.scratch/codex-addon/20260918-continuation/cpu-calibration-evidence/cpu-calibration-main.swift), [comando/esito della sonda](../../../.scratch/codex-addon/20260918-continuation/cpu-calibration-evidence/cpu-calibration-probe-log.json), [hash delle evidenze](../../../.scratch/codex-addon/20260918-continuation/cpu-calibration-evidence/cpu-calibration-evidence-sha256.json), [revisione indipendente PASS](../../../.scratch/codex-addon/20260918-continuation/cpu-calibration-independent-review.md). La review ha ricalcolato aritmetica e hash senza rieseguire la prova. Le precisazioni sopra prevalgono sulle formulazioni più generali del report congelato.

## Limiti

Le API possono condividere la contabilità del kernel: il confronto qualifica scala e conversione, non la precisione assoluta di tale contabilità. La percentuale riusa il denominatore temporale del riduttore; non è una misura indipendente dell’accuratezza del clock. Non c’è precisione sperimentale al nanosecondo, né archivio ermetico di compilatore/SDK e ambiente ereditato.

L’identità è ottenuta esplicitamente dal solo processo diagnostico. Nessuna autenticazione addon, misura RSS, garanzia macOS14/Intel, campionamento comune/disarmo, soglia, rimborso di quote o uscita gestita viene qualificata. C4 completo e C0d rimangono aperti; il driver C0d non è stato eseguito né modificato. Il risultato è una verifica in sola lettura del codice già consegnato, non una nuova build dell’app. L’integrazione dei servizi prosegue separatamente.
