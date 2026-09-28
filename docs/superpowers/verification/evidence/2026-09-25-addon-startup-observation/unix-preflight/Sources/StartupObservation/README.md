# Osservazione di un provider dentro l'inizializzatore

Prova isolata autorizzata il 25 settembre 2026. Obiettivo: identificare la fixture
mentre è bloccata in `AppExtension.init`, registrare l'uscita e poi terminare/crashare
broker o root mantenendo vivo un osservatore separato. Non è una prova di tutta la
finestra prima di main e non ammette il launcher produttivo.

Il canale diagnostico candidato è AF_UNIX dentro il container della sola fixture.
Si verifica il token audit restituito dal kernel, la firma esatta e il percorso;
dopo EV_RECEIPT viene emessa una challenge imprevedibile. Risposta e token devono
concordare con la prima osservazione. Questo vale per il codice fisso, che non
trasferisce descrittori, non crea figli e non esegue exec; LOCAL_PEERTOKEN non è un
token allegato dal kernel a ogni messaggio. Guardie indipendenti restano attive.

La fattibilità e i risultati nativi verranno registrati soltanto dopo esecuzione.
