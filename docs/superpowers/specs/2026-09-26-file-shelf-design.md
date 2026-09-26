# Ripiano file persistente e conversione

Data: 26 settembre 2026.

Stato: specifica approvata dall'utente con «esatto, continua» dopo la revisione
del documento. Le decisioni della sezione 2 e il completamento proposto nelle
sezioni successive costituiscono la base del piano esecutivo. Le altre azioni
della sezione 8 restano successive. Nessun codice applicativo è stato modificato.

## 1. Obiettivo

Raccogliere file nel notch, conservarli fra riavvii, convertirli e consegnarne
copie ad altre destinazioni. L'esperienza collega visivamente trascinamento,
mazzo di carte, elenco e conversione. Gli originali rimangono nella loro posizione.

## 2. Decisioni confermate

| ID | Decisione | Vincolo |
| --- | --- | --- |
| F1 | Un trascinamento di file richiama il notch chiuso con un battito elastico. | Il feedback precede l'ingresso nel bersaglio; nessuna acquisizione prima del rilascio. |
| F2 | Passando sopra il notch appare il ripiano animato. | Le carte emergono dal centro e si dispongono a sinistra. |
| F3 | I file sono rappresentati come una mano di carte. | Prima carta leggermente ruotata a destra; successive aperte progressivamente verso sinistra. |
| F4 | Il ripiano è la pagina principale finché contiene file. | L'occupazione sopravvive alla chiusura del notch e al riavvio dell'app. |
| F5 | Il clic sul mazzo apre l'elenco dei file con un'animazione. | L'apertura dell'elenco deve essere animata, come il resto del ripiano. |
| F6 | Converti propone destinazioni adatte ai file selezionati. | Ingressi a sinistra, selettore e freccia nella zona centrale, risultati a destra. |
| F7 | La freccia collega ingressi e risultati al centro della composizione. | Non va collocata sotto il flusso come elemento a fondo pagina. Questa decisione sostituisce la collocazione iniziale. |
| F8 | Dopo la scelta del formato compare Avvia e la conversione mostra avanzamento animato. | I risultati diventano utilizzabili solo dopo il completamento effettivo. |
| F9 | Si procede con FFmpeg. | Le scelte tecniche complementari e il perimetro proposto sono precisati sotto. |
| F10 | Il trascinamento in uscita consegna copie e svuota il ripiano per i file consegnati. | Gli originali sono conservati; rifiuto, annullamento o errore non rimuovono il file. |
| F11 | Il ripiano conserva i file dopo il riavvio di Cascade. | Riferimenti persistenti per gli originali; conservazione dei risultati prodotti e ancora presenti nel ripiano. |

Fonti delle decisioni: richiesta iniziale del ripiano; scelta esplicita
«Copia alla destinazione e svuota il ripiano; originali conservati»;
seguito «continuiamo con FFMPEG e la conservazione dei file nel ripiano»,
con elenco animato e freccia al centro.

## 3. Acquisizione, mazzo e navigazione — proposta

All'inizio di un trascinamento riconosciuto come file, il notch esegue un doppio
impulso elastico breve. Il feedback non viene ripetuto a ogni movimento del mouse.
Il rilevamento globale è indicativo: ingresso e rilascio nel bersaglio verificano
effettivamente i tipi offerti. Un trascinamento di testo o di una finestra non
deve essere trattato come acquisizione di file.

All'ingresso appare l'anteprima del ripiano: le carte nascono nella zona centrale
utile e raggiungono il lato sinistro. L'eventuale taglio hardware resta escluso
dai contenuti e dai bersagli. Un'uscita senza rilascio ripristina la pagina
precedente; un rilascio valido conferma gli elementi e mantiene il ripiano.

Il limite proposto è di quattro carte visibili, con contatore +N oltre la quarta.
Non è un limite di quattro file acquisibili. I nuovi file si aggiungono in ordine;
un originale già presente non genera una seconda voce. File diversi con lo stesso
nome restano distinti. Le cartelle sono escluse dalla prima versione, con feedback
esplicito; un lotto misto rende visibili eventuali elementi non acquisiti.

Il clic sul mazzo trasforma le carte nelle righe dell'elenco dentro la stessa
superficie del notch. Le miniature conservano la loro identità e posizione di
partenza; le righe successive entrano con un breve sfalsamento. Indietro ricompone
il mazzo. Non si apre una finestra separata. L'elenco contiene nome, tipo, stato,
selezione multipla e azione di rimozione; scorre quando supera l'altezza disponibile.
Il clic seleziona, mentre il movimento oltre la soglia del drag avvia la consegna.

Finché occupato, il ripiano è la destinazione predefinita all'apertura. La
navigazione manuale verso altre pagine resta possibile e non viene annullata
da aggiornamenti del ripiano. Il notch può richiudersi. Quando l'ultimo elemento
esce con successo, torna alla selezione ordinaria delle pagine e attività.
Un drag che entra esplicitamente nel notch può mostrare il bersaglio temporaneo;
gli eventi automatici non sostituiscono una pagina che l'utente sta consultando.
La compatibilità con la ricerca Spotlight nativa va verificata senza perdere
il testo o il focus della ricerca in caso di drag annullato.

## 4. Conversione — proposta

La composizione usa tre zone orizzontali: ingressi, trasformazione, risultati.
La freccia occupa il centro verticale e orizzontale dello spazio fra i due gruppi
di carte. Il selettore sta sopra la freccia nella medesima zona centrale; Avvia
compare sotto il selettore nel layout disponibile senza spostare la freccia
al fondo della pagina. Il layout deve essere verificato sul notch hardware e
su quello software, evitando sovrapposizioni fra comandi, freccia e taglio fisico.

Aprire Converti conserva le carte di ingresso a sinistra. A destra compare una
previsione identificata come tale soltanto dopo la selezione di un formato.
Avvia è disponibile quando la combinazione è valida. Per una selezione mista,
il selettore propone solo formati comuni a tutti i file selezionati; in assenza
di destinazioni comuni, l'elenco permette di scegliere un gruppo compatibile.
Nessun file viene saltato silenziosamente.

Durante l'elaborazione, il moto lungo la freccia comunica la direzione e un
indicatore mostra l'avanzamento reale. Il lavoro senza durata nota mostra uno
stato indeterminato. La UI offre Annulla e lo stato dei singoli file. I risultati
completi compaiono a destra e sono trascinabili; quelli falliti restano distinguibili
e ripetibili. La conversione non sostituisce o rimuove gli ingressi.

Il batch iniziale elabora un file alla volta in background, senza bloccare la UI.
Una pagina nascosta non annulla il lavoro. Nessuna animazione rimane attiva quando
non serve; Riduci movimento conserva stato e avanzamento con transizioni minime.

## 5. Motori e perimetro — proposta

| Ambito | Motore | Destinazioni iniziali |
| --- | --- | --- |
| Audio/video | FFmpeg e ffprobe distribuiti con Cascade | MP4, estrazione audio, MP3, M4A/AAC, WAV, FLAC, subordinati alle capacità della build e del singolo ingresso. |
| Immagini | ImageIO di macOS | JPEG, PNG, TIFF, HEIC quando supportato dal sistema. |
| PDF | PDFKit e ImageIO | Immagini in PDF; pagine PDF in immagini raster. |

FFmpeg viene invocato con argomenti separati e preset controllati. ffprobe legge
tracce e durata; il formato selezionabile dipende dalle capacità reali, non dalla
sola estensione. La build inclusa deve avere codec, architetture, firma e obblighi
di redistribuzione verificati. Non si dipende da Homebrew installato dall'utente.
Si evita un secondo motore audio/video AVFoundation nella prima versione.
Documenti Office, OCR, animazioni e conversioni vettoriali restano fuori perimetro.

Ogni risultato nasce in un file provvisorio gestito da Cascade. Diventa definitivo
solo dopo la chiusura riuscita del processo e la verifica del risultato, con nome
senza collisioni. L'annullamento attende l'arresto del processo prima della pulizia.
Originali e risultati già completi non vengono rimossi dall'annullamento del batch.

## 6. Conservazione e recupero — proposta

Il ripiano salva identità, ordine, riferimento al file e stato necessario al
recupero. Per gli originali locali conserva riferimenti persistenti, senza
duplicarne subito il contenuto. La persistenza del ripiano non è un backup:
un originale eliminato, un volume scollegato o un permesso perso produce una
voce non disponibile, che l'utente può ricollegare o rimuovere.

File promessi in ingresso e risultati di conversione vengono materializzati
nello spazio dati persistente dell'app. Non vanno affidati a una cartella
temporanea eliminabile al riavvio. Una promessa è acquisita solo dopo la sua
scrittura riuscita; gli elementi cloud non ancora disponibili mostrano il loro
stato, senza fingere che la conversione possa iniziare.

Al riavvio, un lavoro incompleto è indicato come interrotto e ripetibile, senza
conversioni riavviate automaticamente. Ingressi e risultati completi restano.
I provvisori incompleti sono ripuliti solo dopo avere escluso un processo ancora
attivo. Un export senza conferma persistita lascia l'elemento nel ripiano: il
recupero non deduce il successo dal solo avvio del trascinamento.

## 7. Consegna e rimozione — proposta

L'uscita usa operazioni di copia e una file promise per elemento, quando accettate
dalla destinazione. La carta viene rimossa soltanto dopo la scrittura riuscita
del relativo file. In un drop parziale escono solo le carte effettivamente
consegnate; le altre mantengono posizione e possibilità di riprovare.

Il completamento della sessione di drag non prova la scrittura della promessa,
che può avvenire successivamente. La scrittura riuscita prova la consegna all'URL
richiesto, non un successivo upload o salvataggio interno dell'app destinataria.
Per gli originali esterni, un percorso di compatibilità basato solo su URL,
privo di conferma individuale, mantiene gli elementi nel ripiano e non dichiara
la consegna verificata. Nella prima versione i risultati posseduti da Cascade
vengono offerti tramite file promises: una destinazione che accetta solo URL
non può riceverli da questo percorso e non provoca alcuna rimozione. Un futuro
supporto URL per i risultati richiede una politica di conservazione distinta,
poiché la fine del drag non prova che il destinatario abbia terminato la lettura.

La rimozione della voce e la pulizia del file posseduto da Cascade sono separate.
Si persiste prima la rimozione della voce; soltanto dopo si può ripulire il file,
escludendo conversioni o consegne che lo stanno usando. Un crash fra questi due
passaggi può lasciare un file da ripulire, mai una voce ripristinata senza il suo
risultato. Gli originali esterni non vengono mai eliminati da queste operazioni.
La rimozione manuale di
un risultato gestito è distinta dalla rimozione di un riferimento all'originale
e deve renderne chiaro l'effetto prima di eliminare l'unica copia del risultato.

## 8. Altre azioni — proposta successiva

Converti è l'azione richiesta. Condividi (incluso AirDrop) e Crea ZIP restano
proposte da valutare separatamente, senza farle diventare implicitamente
requisiti del primo incremento. Anteprima, Mostra nel Finder e Rimuovi dal
ripiano completano il menu contestuale. La condivisione non viene equiparata a
un export verificato per svuotare automaticamente il ripiano.

## 9. Inserimento in Cascade

Il percorso esistente del puntatore e il coordinatore dei display devono essere
riusati per routing e proprietà del notch aperto. Il modello persistente del
ripiano è condiviso fra display e indipendente dalle viste. Acquisizione AppKit,
conversione in background e presentazione animata mantengono responsabilità
distinte, senza duplicare lo stato dei file nelle singole superfici.

La composizione rispetta i contratti di prodotto per widget interni ed esterni.
L'accesso ai file e l'esecuzione del convertitore richiedono capacità esplicite:
il piano dovrà collocarli nei confini esistenti, senza introdurre un percorso
privilegiato del widget o dichiarare già risolti i vincoli del runtime addon.
La pagina persistente si coordina con la specifica delle pagine contestuali,
che è ancora in discussione; non si assume che quella navigazione sia già attiva.

## 10. Verifica prevista

- Drag di file, testo e finestre; ingresso, uscita, annullamento e rilascio valido.
- Uno, quattro e più file; omonimi, duplicati e drop parzialmente valido.
- Apertura e chiusura animate dell'elenco, drag distinto dal clic, tastiera e Riduci movimento.
- Freccia centrale senza sovrapposizioni su notch hardware/software e display diversi.
- Riavvio con originali, risultati completi, file irreperibili e lavori interrotti.
- Conversioni reali, selezioni miste, formato non supportato, annullamento ed errore.
- Export singolo, multiplo e parziale; destinazione rifiutata, copia fallita e crash prima della conferma persistita.
- Pagina principale finché occupata, navigazione manuale, ritorno quando vuota e drag durante ricerca.
- Build, aggiornamento del collegamento /Applications/Cascade.app e riavvio verificato prima di dichiarare conclusa l'implementazione.

## 11. Riferimenti

- [Pagine e selezione contestuale](2026-09-26-contextual-pages-design.md).
- [Raccolta e durata del ripiano](../../../.scratch/cascade-product/issues/10-file-shelf.md).
- [FFmpeg: conversione e progress](https://ffmpeg.org/ffmpeg.html).
- [ffprobe: analisi dei media](https://ffmpeg.org/ffprobe.html).
- [FFmpeg: redistribuzione](https://ffmpeg.org/legal.html).
- [Apple: formati scrivibili di ImageIO](https://developer.apple.com/documentation/imageio/cgimagedestinationcopytypeidentifiers()).
- [Apple: PDFPage](https://developer.apple.com/documentation/pdfkit/pdfpage).
- [Apple: scrittura delle file promises](https://developer.apple.com/documentation/appkit/nsfilepromiseproviderdelegate/filepromiseprovider(_:writepromiseto:completionhandler:)).
- [Apple: drop parziali](https://developer.apple.com/documentation/appkit/nsdragginginfo/numberofvaliditemsfordrop).
