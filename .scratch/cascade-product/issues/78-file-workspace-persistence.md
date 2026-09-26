# Persistire voci e ricevute del ripiano file

ID: 78
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/file-shelf
Blocked by: 76

## Question

Il modello del ripiano è fissato in [Definire raccolta e durata dei file nel ripiano](10-file-shelf.md).

Implementare il task 2 del [piano del ripiano file](../../../docs/superpowers/plans/2026-09-26-file-shelf.md): store persistente a writer unico, riferimenti agli originali senza copia, risultati gestiti, bookmark/identità, quote e ricevute di consegna. Accettazione: riapertura conserva ordine e ID; duplicati e omonimi gestiti; originali mancanti restano visibili; corruzione/versione futura e salvataggi falliti non distruggono lo stato; crash fra copia, commit e cleanup non perde il risultato; rimozione dell'unica copia gestita richiede conferma. Test con directory reali, review root e commit selettivo. Sviluppabile offline sul confine interno di [Contratti e confine autorizzato del ripiano file](76-file-workspace-contracts.md); la qualifica nativa non è prerequisito di questo task.

## Answer

Implementato nel commit `bbe1144`: store host persistente, bookmark e descriptor con identità verificata, writer unico con close/reopen esplicito, quote comuni di disco/stato/memoria, manifest atomico sincronizzato e ricevute per elemento. La review root ha corretto commit incerti, pin delle consegne, riapertura concorrente e rollback delle quote. Verifica root: filtro `FileWorkspace|ResourceGovernorTests`, 50 test passati, diff senza errori di whitespace.

La consegna accetta input promessi già completati e autorizzati dall’host; ricezione nativa e attivazione nell’app rimangono nei ticket successivi. L’identità device/inode/generation può rendere indisponibile un file dopo rimontaggio del volume; filesystem senza generation utile hanno garanzie inferiori contro il riuso inode. Nessun cleanup automatico di dati sconosciuti. Dettagli nel [checkpoint di verifica](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md).
