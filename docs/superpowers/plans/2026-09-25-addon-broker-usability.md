# Broker addon: riavvio e isolamento verificabili

Prosecuzione autorizzata del piano di completamento del 10 settembre; specifica e
policy del controllo diretto e del recupero globale restano vincolanti.

1. Provare l'uscita della catena broker/provider e la sua ricreazione con lo stesso
   host ancora vivo; osservazione kernel autenticata prima di ogni arresto, nessun
   nuovo avvio con uscita precedente sconosciuta.
2. Provare due host contemporanei dello stesso provider: identificare l'eventuale
   riuso, fermare la prima catena e verificare l'altra. Questa prova non equivale
   all'isolamento di due addon diversi nello stesso host.
3. Valutare dalle fonti pubbliche un contenitore fidato che carichi il codice addon
   dopo il bootstrap; esplicitare ogni scelta di formato/sicurezza necessaria.
4. Conservare risultati, revisione e limiti; proseguire sulle parti dimostrate,
   fermandosi soltanto a una decisione progettuale necessaria. Gate invariato.

## Registro

- Si lavora sul checkout corrente autorizzato, che contiene l'intera implementazione
  non ancora committata. Nessuna pulizia o commit delle modifiche preesistenti.
- Le nuove prove estendono la fixture BrokerRecovery, senza abilitare un launcher
  di produzione. Le finestre pre-main e gli OS non disponibili restano aperti.
- Classificatore: test scritto prima della logica, comprese falsa ripartenza,
  uscita della guardia e sessione condivisa. Prove native e cleanup separati.
- 1 e 2 completati nella fixture: ricambio del broker e due host PASS. Primo
  tentativo RED per comando mancante; successivo UNKNOWN per finestra startup di
  2 s, conservato con verifica cleanup incompleta. Finestra diagnostica estesa a
  15 s dopo evidenza di richiesta ancora pendente: circa 10 s osservati, non una SLA.
- Estensione necessaria per l'usabilità: il normale lavoro termina il solo provider;
  due provider successivi con lo stesso broker PASS, nuova partenza circa 66 ms.
  Nessun provider resta vivo solo per mostrare contenuto. Questo è un risultato
  della fixture, non un'integrazione del runtime di prodotto.
- 3 completato: il loader tardivo non chiude il pre-main del contenitore fidato e
  aggiunge vincoli ABI/storage/firma. Non viene adottato né sottoposto come scelta
  risolutiva: non c'è evidenza che risolva il blocco per cui cambiare architettura.
- 4: tre nuovi casi e tre regressioni native PASS; 25 test Python PASS; revisione
  indipendente senza P1/P2. Rimane aperta C0, secondo la decisione già presa, senza
  riproporre l'eccezione rifiutata. Nessun commit delle modifiche preesistenti.
