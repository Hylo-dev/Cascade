# Notch continuo, avvisi e volume

Richiesta approvata direttamente dall'utente l'8 settembre: forma continua Apple,
avvisi soltanto da chiuso, chiusura delle Live Activities in due fasi, sostituzione
dell'HUD volume con icona/testo e barra percentuale ai lati del notch.

## Decisioni

- La sagoma mantiene l'attacco al bordo superiore e adotta la curvatura continua
  nativa. Il path condiviso governa disegno, maschera e hit testing.
- Gli avvisi occupano entrambi i lati compatti. Entrare in hover li rimuove e
  apre una Live Activity disponibile oppure i widget. Gli avvisi arrivati durante
  l'espansione vengono scartati, senza riproposizione successiva.
- La chiusura di una Live Activity nasconde subito le sue viste, raggiunge la
  geometria base e solo al frame successivo apre le ali. Nessuna attesa a tempo
  fisso: la seconda fase dipende dall'assestamento delle molle. Movimento ridotto
  passa direttamente allo stato finale.
- Il volume usa listener CoreAudio e intercettazione selettiva dei tasti volume.
  Non vengono disabilitati globalmente daemon o HUD di sistema; senza supporto o
  permessi, i tasti mantengono il comportamento nativo.
- Nessuna concessione automatica di Accessibilità, nessuna modifica dell'audio
  reale attraverso script di verifica, nessun commit delle modifiche preesistenti.

## Esecuzione

- [x] Path continuo: `Extensions/CGPath+Notch.swift` e test geometrici dedicati;
  derivare/cachare segmenti Apple, verificare simmetria, bounds e angoli piccoli.
- [x] Host e controller: limitare la presentazione estesa alle Live Activities,
  scartare gli avvisi in apertura, sospendere le viste durante il ritorno alla
  base, animare la larghezza compatta in punti. Regressioni host/controller prima
  dell'implementazione.
- [x] Volume: nuovi tipi `Cascade/Integrations/Volume`, `VolumeChangeNotice`,
  collegamento in servizi/menu e harness Swift 6 per eventi, capability e cleanup.
- [x] Verificare suite completa, build firmata, revisione indipendente e avvio
  della build esatta. Aggiornare il contratto con queste nuove regole.

Il contratto condiviso aggiunge `compactPreferredSideWidth: CGFloat?` (larghezza
esterna di ciascuna ala, default configurato quando nil). Volume richiede 116pt;
il renderer limita i valori al display. `makeExpandedView` appartiene soltanto a
`NotchLiveActivity`; gli avvisi non possono ottenere una superficie estesa.
