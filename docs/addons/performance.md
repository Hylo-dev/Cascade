# Prestazioni e risorse degli addon

## Progettare lavoro finito

Pubblicare contenuti dichiarativi limitati e timeline finite; usare countdown e clock del [renderer](content.md) invece di mantenere un task del provider che invii aggiornamenti a ogni tick. Il modello separa durata del contenuto e durata del processo. Conservazione dei valori, scadenze e revisioni sono descritte nel [ciclo di vita](lifecycle.md); la prova completa con provider nativo assente resta distinta dal comportamento delle componenti.

Gestire `resourceDenied`, `rateLimited`, scadenze e revoche esplicitamente. Un risultato incerto non autorizza una ripetizione automatica di effetti. Limitare input, risultati e stato conservato, liberando le risorse secondo il relativo contratto; non trattare una richiesta di stop o una ricevuta di trasporto come uscita osservata.

## Limiti applicati e contabilità

La baseline implementa validazione dei payload e ammissione tramite `ResourcePolicy`/`ResourceGovernor`. Per le richieste ordinarie il governor verifica i costi per owner e globali prima di registrare una riserva. La riconciliazione del disco registra anche dati già presenti oltre quota; quel debito impedisce nuova crescita, senza nascondere i byte esistenti. Le quote coprono quantità diverse: pubblicazioni, lavori, provider, scene, stato conservato, asset, memoria ammessa e disco. I costi includono metadati di prenotazione; una dichiarazione di risorse nel manifest non è un grant e l’origine del package non seleziona una policy privilegiata.

Per i limiti dei documenti, alberi, timeline e frame usare il [protocollo](protocol.md); per pixel e trasferimenti gli [asset](assets.md); per stato persistente lo [storage](storage.md); per code, lavori e storia delle azioni il [lifecycle](lifecycle.md) e le [azioni](actions.md). I [servizi](services.md) precisano prenotazioni prima del dispatch, capacità condivise e lifetime degli esiti. Questi budget non vanno sommati come se costituissero un unico limite di memoria del processo.

Dimensione wire, costo prenotato e footprint osservato sono misure differenti. Un frame accettato non dimostra un limite alle allocazioni Foundation o alla RSS; un costo di provider nel governor non costituisce un sandbox di memoria. Le riserve di processo rimangono fino all’uscita osservata nel modello host: gli ingressi di uscita modellati nei test non qualificano la terminazione nativa.

## Misure effettivamente disponibili

Il lettore interno osserva risorse di processo; il riduttore calcola intervalli CPU da campioni compatibili. Dati assenti o riferiti a un’identità diversa non diventano consumo zero. Il [contratto delle osservazioni](../architecture/addon-resource-observations.md) descrive continuità, overflow e limiti dell’identità.

La [calibrazione indipendente](../superpowers/verification/2026-09-18-addon-process-cpu-calibration.md) confronta copie identiche di lettore e riduttore con `getrusage(RUSAGE_SELF)` su macOS 27 arm64. Qualifica scala e conversione delle unità per il processo diagnostico, senza qualificare precisione assoluta della contabilità kernel o del clock. Il footprint letto non è una misura RSS qualificata dell’addon installato.

Restano da collegare associazione autenticata addon/processo, campionamento comune e disarmo, soglie, salute e arresto reale. Non sono consegnate garanzie di latenza, p99, risvegli, consumo continuo o prestazioni su macOS 14/Intel. Un test sorgente o una prenotazione riuscita non chiude la qualifica del controllo nativo delle risorse.
