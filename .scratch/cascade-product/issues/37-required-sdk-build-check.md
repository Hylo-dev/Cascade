# Eseguire il controllo SDK prima della build di sviluppo

ID: 37
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 35

## Question

Rendere obbligatorio il controllo dei confini pubblici SDK nello script ufficiale di build di sviluppo: una violazione deve interrompere il percorso prima di compilazione, firma o aggiornamento del collegamento Applications.

## Context

Incremento circoscritto richiesto dal [piano strumenti e parità](../../../docs/superpowers/plans/2026-09-09-addon-runtime-04-release.md#task-042--strumenti-pubblici-e-parità-obbligatoria-per-i-nostri-widget), dopo [Verificare i confini pubblici dell’SDK e degli esempi](35-sdk-boundary-check.md). All’apertura del ticket il controllo esisteva ed era revisionato, ma `scripts/build-development.sh` non lo eseguiva ancora; l’integrazione è ora consegnata nella Answer. La [preparazione tecnica](../../codex-addon/20260918-continuation/boundary-build-gate-next-step.md) descrive il cambiamento minimo, i limiti e le prove.

Il comando deve ereditare il toolchain selezionato e usare la root esplicita indipendentemente dalla directory di invocazione. Conservare identità Apple Development, parametri Xcode, verifica firma e aggiornamento Applications. Nessuna modifica dei target Swift, del runtime o del gate nativo.

La verifica comprende fixture negative con il vero parser/grafo SwiftPM e traccia dei comandi per dimostrare il mancato ingresso in Xcode, più una build firmata positiva e riavvio verificato sulla copia esatta. La copia di build deve includere gli esempi controllati. Documentare la garanzia sullo script ufficiale senza attribuirla alle invocazioni Xcode dirette; la migrazione di tutte le registrazioni legacy e la parità nativa restano aperte.

## Progress — storico precedente alla consegna

Presa in carico dopo la consegna del verificatore. Sviluppo e fixture in copia temporanea isolata; nessun cambiamento al sorgente congelato delle sottoscrizioni finché la sua consegna non è conclusa. Lo script positivo completo e il riavvio restano responsabilità del task principale.

Implementazione isolata corretta e revisione indipendente PASS: quattro fixture reali verificano rifiuto e ordinamento, senza compilare un’app. [Verifica corrente](../../../docs/superpowers/verification/2026-09-18-addon-required-sdk-build-check.md). Import e build firmata positiva restano pendenti; i sorgenti dell’app rimangono congelati per la revisione delle sottoscrizioni.

## Answer

Controllo pubblico obbligatorio integrato prima di Xcode nello script ufficiale, senza bypass e con root/toolchain espliciti. Quattro fixture reali e revisione indipendente PASS; la build positiva con tutti e tre i package controllati, firma e riavvio PID85871 è consegnata insieme alle sottoscrizioni. [Verifica e limiti](../../../docs/superpowers/verification/2026-09-18-addon-required-sdk-build-check.md). Nessuna garanzia aggiunta alle invocazioni Xcode dirette o alla parità nativa.
