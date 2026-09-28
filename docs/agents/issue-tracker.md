# Tracker delle decisioni: Local Markdown

Per questa mappa si usa il fallback locale previsto da wayfinder; non vengono pubblicate issue su GitHub. Per configurare successivamente il toolkit su un altro tracker, eseguire `/setup-matt-pocock-skills`.

## Wayfinding operations

- Mappa canonica: `.scratch/cascade-product/map.md`, con etichetta `wayfinder:map`.
- Figli: un file per ticket in `.scratch/cascade-product/issues/NN-nome.md`; `ID` è l'identità e `Parent` identifica la mappa.
- Tipo ed etichetta: `Type: research|prototype|grilling|task` e `Labels: wayfinder:<tipo>`.
- Stati: `open`, `claimed`, `resolved`, `closed-out-of-scope`. Questi ultimi due sono chiusi.
- Claim: impostare `Assignee` e `Status: claimed` **prima** del lavoro. Rilasciare entrambi se il lavoro viene abbandonato. Non prendere un ticket già assegnato.
- Dipendenze: `Blocked by: NN, NN`, oppure `none`. È il fallback testuale per un tracker senza relazioni native.
- Frontiera: figli con stato open, assignee none e tutti i blocchi chiusi; ordinare per ID. `docs/wayfinder/frontier.md` è una vista derivata, non una seconda fonte delle decisioni.
- Risoluzione: aggiungere `## Answer` con esito, prove e asset; impostare resolved e aggiungere alla mappa soltanto titolo collegato e gist. Non inserire la risposta nella Question.
- Fuori ambito: stato closed-out-of-scope, motivazione e collegamento in Out of scope della mappa, senza inserirlo tra le decisioni raggiunte.
- Nuovi ticket: creare prima tutti i file e poi collegare le dipendenze in una seconda passata. Vietati riferimenti inesistenti e cicli.
- Citare i ticket per titolo collegato in tutto il testo destinato alle persone; gli ID nudi sono riservati ai metadati.

Adattato dal [template local-markdown originale](https://github.com/mattpocock/skills/blob/main/skills/engineering/setup-matt-pocock-skills/issue-tracker-local.md). Il file è configurazione della mappa corrente; il setup globale delle skill non è stato eseguito.

