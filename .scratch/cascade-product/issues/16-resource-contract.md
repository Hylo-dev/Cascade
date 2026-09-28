# Definire budget, isolamento e recupero dai guasti

ID: 16
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: open
Assignee: none
Blocked by: 05, 06, 13

## Question

Quali soglie misurabili di memoria, CPU, energia, wakeup, latenza di apertura e fluidità deve rispettare Cascade, in idle e con attività reali? Decidere diagnosi, policy per estensioni lente, crash e revoca permessi, e verifica del percorso audio. Separare promesse del protocollo da limiti realmente imponibili dal sistema: codice nello stesso processo non diventa isolato perché espone suspend(). Includere Reduce Motion, Reduce Transparency e tastiera/VoiceOver nei criteri di validazione pertinenti.

## Avanzamento del 9 settembre 2026

Approvati ammissione preventiva delle operazioni gestite, servizi condivisi con concessioni revocabili, processi su domanda e supervisione con recupero/quarantena. Distinte quote applicative rigide e soglie CPU/RAM osservate; congelamento escluso dal default. Identici controlli e budget per addon del team ed esterni.

La [specifica](../../../docs/superpowers/specs/2026-09-09-addon-runtime-design.md) propone valori iniziali; [P2](../../../docs/superpowers/plans/2026-09-09-addon-runtime-02-execution.md) li applica e [P4](../../../docs/superpowers/plans/2026-09-09-addon-runtime-04-release.md) li misura. Rimangono aperti valori qualificati, profili continui di UI/audio, costo totale dei servizi e prove su hardware/OS: nessun benchmark è già concluso da questa decisione.

## Riallineamento del 14 settembre 2026

Sono implementate e revisionate le prenotazioni del governor comune, la contabilità protetta dei raster/decoder e le risorse delle operazioni storage. L'utente ha scelto SwiftData per l'archivio durevole; salvataggio, ripristino, inventario completo, scrittura su modifiche significative e checkpoint limitato alla chiusura hanno verifiche dedicate nel [piano corrente](../../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md).

La [politica disco approvata](../../../docs/superpowers/plans/2026-09-13-addon-swiftdata-disk-policy-decision.md) conserva nel conteggio gli eventuali superamenti prodotti dai file interni del framework e blocca le scritture successive. Le allocazioni controllate dall'app restano soggette ad ammissione preventiva. Si riusano SwiftData, Foundation e ImageIO/CoreGraphics; non è stato aggiunto un database o un codec alternativo.

Restano aperte le misure native di CPU/footprint, l'uscita effettiva dei processi, i profili continui audio/UI, il costo complessivo dei servizi e la matrice hardware/OS. I test funzionali non sono benchmark energetici né prova di un limite rigido sul consumo interno dei framework. Le dipendenze globali del ticket restano valide.
