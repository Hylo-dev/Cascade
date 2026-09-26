# Contratti di controllo e aggiornamento dei servizi

18 settembre 2026. **Implementazione integrata, revisione PASS e consegna firmata verificata: 1048 test / 94 suite.** Questa verifica non attiva il protocollo 1.4.

Il [piano](../plans/2026-09-18-addon-service-subscription-frames.md) definisce sei file nuovi: richieste e risposte di controllo, avvio e output della sorgente, codec dedicato e test. Il codec delle invocazioni esistente rimane invariato. Le forme chiuse distinguono accettazione dell'intento di acquisizione e risultato terminale; gli aggiornamenti correlano sorgente e nonce di avvio. I valori serializzati non costituiscono autorità del provider, prova di disponibilità o autorizzazione del consumer.

## Prove isolate

- 14 test mirati e 91 test Contracts in 10 suite PASS sull'harness isolato con Xcode-beta / Swift 6.4; non sono risultati dell'intero CascadeKit.
- 67 sorgenti/test/fixture preesistenti conservati byte per byte. Sei aggiunte congelate, nessuna modifica ai contratti precedenti o al package reale.
- Frame limitati a 196608 byte prima del decode e payload a 65536 byte. Payload all-FF con slash completamente escapati attraversano i codec sorgente/evento. I wrapper conservativi sono 476 byte per aggiornamento, 1424 per evento e 7189 per avvio sorgente, tutti sotto 8192.
- Matrice fase/tipo/risultato, correlazione, campi extra/null/sconosciuti, limiti dei motivi di rifiuto, metadati massimi e separazione dai codec precedenti verificati. Un rifiuto non può usare il codice outcomeUnknown.

Il primo RED comportamentale compilante contiene un test e un errore, prima dell'implementazione. La successiva esecuzione dei test ampliati su scaffolding permissivo rileva 224 violazioni: è una prova per mutazione successiva, non il RED originario di ogni asserzione. Le prime fasi non catturavano tutti gli hash degli input; gli input Swift/Package dei GREEN finali sono congelati, con le fixture protette dal manifest della baseline. Gli errori preliminari della toolchain sono conservati separatamente.

[Handoff e log](../../../.scratch/codex-addon/20260918-continuation/subscription-frames-evidence/handoff.md) · [Revisione indipendente PASS](../../../.scratch/codex-addon/20260918-continuation/subscription-frames-independent-review.md) · [Hash dei sei file](../../../.scratch/codex-addon/20260918-continuation/subscription-frames-evidence/new-file-hashes.json).

## Limiti e consegna

Restano da verificare nel runtime ordinamento delle fasi, autorità corrente, lifetime della sorgente, quote effettive, ricevute, cancellazione e consegna degli eventi. Nessuna prova di memoria RSS, trasporto nativo, morte dei processi o compatibilità macOS 14 / Intel è dedotta da questi test. Il client pubblico completo e la negoziazione 1.4 restano da implementare.

Root ha importato esclusivamente i sei file revisionati, senza gli ausili dell’harness. I 463 input precedenti sono rimasti identici; il freeze comprende ora 469 input. La suite completa passa con **1048 test in 94 suite**, exit 0, 63,54 s. La copia esatta per la build contiene 439 input; build Debug Apple Development, verifica firma e collegamento `/Applications/Cascade.app` PASS, exit 0, 11,7 s. Riavvio normale PID **18542 → 20946**, eseguibile corretto e stabile per 5 s. La negoziazione del runtime resta al massimo 1.3.

[Importazione e verifiche root](../../../.scratch/codex-addon/20260918-continuation/subscription-frames-root-import.json) · [Riavvio verificato](../../../.scratch/codex-addon/20260918-continuation/subscription-frames-restart-evidence.json). SHA256 dell’eseguibile: `0712922cbb2d0337875e768474d172c7d34648700797c8d41d349b0b9b2ad13a`.
