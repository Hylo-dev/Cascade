# Verificare e consegnare il primo ripiano file locale

ID: 90
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: open
Assignee: none
Blocked by: 89, 91, 92

## Question

Eseguire la fase D del [piano locale approvato](../../../docs/superpowers/plans/2026-09-26-local-file-shelf.md): review root dei commit, test mirati e suite completa, QA nativa su drag Finder/rifiuto/annullamento/parziale, riavvio, pagina predefinita e navigazione manuale, VoiceOver e Riduci movimento. Registrare limiti URL/promise e conversione differita. Build firmata, aggiornamento `/Applications/Cascade.app`, chiusura e riapertura con processo aggiornato verificato. Non dichiarare qualificato il launcher esterno.

## Avanzamento parziale — ticket aperto

Build finale firmata exit 0 (`local-app-build.log`), controlli dei confini SDK e firma superati. `/Applications/Cascade.app` punta a `/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeFileShelf/Build/Products/Debug/Cascade.app`. Il processo precedente PID 34695 non usciva con Quit via CUA: root ha inviato TERM mirato e verificato l'assenza del processo, poi ha riaperto l'app via CUA. Nuovo PID 52683, avvio 26 settembre 2026 ore 20:23:07 CEST, eseguibile nel bundle collegato e binario aggiornato alle 20:21:40. Screenshot del notch chiuso visibile. Test SwiftPM 1.416/1.416 e test app firmati 6/6 passati. Riserva settimanale residua 95%.

La QA nativa del ripiano resta **aperta**: Finder `getApp`/AX falliscono ripetutamente con ScreenCaptureKit `-3812` (`invalid parameter`); le coordinate 64/72 nell'AX/screenshot di Cascade non hanno aperto il notch. Non sono quindi verificati ingresso/uscita Finder, carte e animazioni reali, copie e originali in Finder, annullamento/rifiuto/parziale, persistenza osservata nell'app, navigazione manuale, VoiceOver e Riduci movimento nel notch. I test unitari di persistenza e Riduci movimento non sostituiscono queste prove. Le file promise in ingresso e Converti restano indisponibili. Riprendere dal QA nativo quando l'accesso Finder/notch è recuperato; launcher addon e ticket esterni restano separati.

Successiva prova diretta dell'utente: il drag di file sotto il bordo produce battito e apertura; si sente il suono di rilascio, ma il file non viene acquisito. Questo è un fallimento della QA d'ingresso, tracciato in [Correggere l'acquisizione file nel drag nativo del ripiano](91-file-shelf-native-drop-regression.md). La rimozione del selettore Ripiano/Attività è richiesta dall'utente ed è in lavorazione; area di drop temporanea, ciclo nativo e guardia Mission Control richiedono ancora review e prova. Il ticket di consegna resta aperto.

La correzione sorgente è stata revisionata e consegnata in una nuova build firmata; `/Applications/Cascade.app` riavviata al PID 59537 il 26 settembre 2026 alle 21:36:32. La prova Finder automatizzata continua a fallire nella cattura CUA con ScreenCaptureKit `-3811`; conferma manuale dell'utente ancora pendente. Il ticket resta bloccato dalla prova nativa del [drag in ingresso](91-file-shelf-native-drop-regression.md), senza dedurre dalla build che l'acquisizione sia riuscita.
