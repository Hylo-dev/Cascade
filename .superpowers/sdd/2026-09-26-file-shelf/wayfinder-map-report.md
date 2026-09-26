# Mappa Wayfinder del ripiano file — 26 settembre 2026

Commit tracker: `7c8fa2a` (`docs: map remaining file shelf work in Wayfinder`).

File aggiornati: [mappa](../../../.scratch/cascade-product/map.md), [frontiera](../../../docs/wayfinder/frontier.md), [decisione sul ripiano](../../../.scratch/cascade-product/issues/10-file-shelf.md) e nuovi figli [Contratti e confine autorizzato del ripiano file](../../../.scratch/cascade-product/issues/76-file-workspace-contracts.md) fino a [Verificare e consegnare il ripiano file integrato](../../../.scratch/cascade-product/issues/85-file-workspace-integration.md). La decisione sul ripiano e il confine interno sono risolti con riferimenti a specifica, verifica e commit; la qualifica nativa rimane aperta. Gli altri otto nuovi task restano aperti.

Frontiera attuale: 85 ticket, 62 risolti, 8 disponibili, 15 bloccati. Per questa tranche sono disponibili [Persistire voci e ricevute del ripiano file](../../../.scratch/cascade-product/issues/78-file-workspace-persistence.md), [Aggiungere il componente condiviso e la lista animata del ripiano](../../../.scratch/cascade-product/issues/80-file-workspace-presentation.md) e [Preparare FFmpeg e ffprobe verificati nel bundle](../../../.scratch/cascade-product/issues/81-file-workspace-ffmpeg-bundle.md). Nessuno è stato reclamato qui.

Validazione: script temporaneo Python in `/tmp/check_wayfinder_file_shelf.py` PASS per ID unici, metadati, link locali, DAG aciclico, dipendenze attese, conteggi e tabella della frontiera. `git diff --cached --check` PASS prima del commit. Nessun codice, build o riavvio in questa tranche documentale; il controller root gestisce il ciclo dell'app.
