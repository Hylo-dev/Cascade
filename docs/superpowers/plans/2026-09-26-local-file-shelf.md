# Ripiano file locale: primo incremento

**Autorizzazione:** [specifica approvata, §9](../specs/2026-09-26-file-shelf-design.md#9-inserimento-in-cascade). Questo piano sostituisce, per il solo montaggio locale del ripiano, il prerequisito del gate addon nel [piano originale](2026-09-26-file-shelf.md). Il launcher esterno, i suoi ticket nativi e le quote/grant restano invariati. Conversione e relativo motore restano differiti finché supervisione, annullamento e recupero sono pronti; Converti non deve apparire disponibile.

**Ordine:** [Host locale](../../../.scratch/cascade-product/issues/87-file-shelf-local-host.md) → [pagina e drop](../../../.scratch/cascade-product/issues/88-file-shelf-local-routing.md) → [composizione e uscita](../../../.scratch/cascade-product/issues/89-file-shelf-local-composition.md) → [verifica e consegna](../../../.scratch/cascade-product/issues/90-file-shelf-local-delivery.md). Ogni incremento richiede test mirati e revisione root; l'ultimo esegue suite completa, build firmata e riavvio reale.

## A. Host locale e consegna verificata

Un solo `FileWorkspaceHost` possiede lo store persistente e la disciplina di ammissione. Espone snapshot paginati (12 voci di default, massimo wire 32), add di URL originali, remove e relink conservando gli ID. Per l'uscita prepara per ogni voce una capability opaca e immutabile legata alla generazione corrente; la preparazione non apre né trattiene il file. Alla scrittura del provider risolve e verifica nuovamente l'identità, apre il descrittore controllato, copia con creazione esclusiva senza overwrite e `fsync`, poi registra ricevuta e rimuove solo dopo copia completata. Fallimento, rifiuto, annullamento e ricevute tardive conservano la voce. Nessuna eliminazione dell'originale.

## B. Pagina contestuale e ingresso AppKit

Il motore offre uno slot dedicato al ripiano, senza simulare una Live Activity o ripiegare sulla pagina Musica. Finché contiene file, lo seleziona per default all'apertura; una scelta manuale resta fino alla successiva apertura e non viene sovrascritta da aggiornamenti. `NSDraggingDestination` riconosce file correnti, produce un solo battito all'inizio del drag e mostra il bersaglio/mazzo; testo, drag annullato e pasteboard stantia non acquisiscono nulla. Chiusura, cambio display e proprietario del notch mantengono un solo stato coerente. Riduci movimento elimina il moto superfluo senza perdere il feedback di stato.

## C. Composizione app e trascinamento in uscita

La facade app collega host, motore e renderer condiviso già verificato: quattro carte +N, elenco animato e persistenza visibile al riavvio. Il drag di uscita usa provider nativi per la copia verificata per singolo elemento. L'ingresso accetta URL regolari; file promise in ingresso non supportate nel primo incremento ricevono un rifiuto chiaro. Ogni consegna riuscita rimuove soltanto la relativa voce; un drop parziale lascia le altre. Gli originali restano nella posizione iniziale. La UI spiega perché Converti è disabilitato finché il motore supervisionato non è completo.

## D. Verifica finale

Il root rivede ogni commit e verifica test mirati e suite completa, drag reali (Finder, destinazione che rifiuta, annullamento, batch parziale), persistenza/riavvio, pagina occupata e navigazione manuale, VoiceOver e Riduci movimento. Registra limiti del drag URL e delle promise. Dopo build firmata riuscita aggiorna `/Applications/Cascade.app`, chiude e riapre Cascade e prova il processo aggiornato. L'evidenza non qualifica il launcher addon né la conversione differita.
