# Definire quando gli sforamenti CPU diventano violazioni distinte

ID: 49
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 48

## Question

Il credito condiviso è definito e le osservazioni possono ora conservare il debito. Per applicare «tre violazioni moderate in cinque minuti», quando un nuovo campione rappresenta una nuova violazione CPU?

## Contesto

La specifica richiede riduzione delle concessioni dopo uno sforamento moderato e quarantena della versione dopo tre violazioni in cinque minuti. `AddonHealthStore` riceve violazioni già classificate: non decide se un debito persistente rappresenti uno o più incidenti. La scelta cambia il tempo e le condizioni della quarantena, non soltanto la rappresentazione dei dati.

Esempio: un addon consuma 150 ms, supera di 50 ms il credito iniziale e poi rimane inattivo. Il debito resterà visibile per dieci secondi. Contare ogni saldo negativo provocherebbe tre violazioni anche senza altro lavoro: la raccomandazione esclude questo doppio conteggio.

## Alternative

1. **Nuovo consumo oltre il credito (raccomandazione).** Al massimo una violazione per addon per giro comune di misurazione, se nel giro viene effettivamente consumata altra CPU oltre il credito disponibile. Il solo debito residuo non conta. Se l’addon continua a consumare oltre il budget in tre giri entro cinque minuti, raggiunge la quarantena; più processi dello stesso addon nello stesso giro non moltiplicano gli incidenti. Un giro comprende sia campioni periodici sia osservazioni esplicite ai confini dei job o per pressione: la frequenza dei giri può quindi influire sul tempo di rilevamento.
2. **Un incidente per episodio di debito.** Il primo passaggio in negativo conta; finché il saldo non torna almeno a zero non si conta un secondo incidente. Tre episodi distinti portano alla quarantena. Un consumo continuo che non recupera credito resta un solo incidente: prima di applicare questo modello serve anche una soglia/durata separata di arresto per uno sforamento continuo.

I campioni incompleti non devono essere classificati come consumo nullo o stato sano; l’abilitazione del profilo richiede comunque misure e arresto qualificati. Questo ticket non apre il launcher, non attribuisce costi dei servizi condivisi e non abilita UI/audio continui.

L’utente ha chiesto di proseguire fino a una scelta progettuale necessaria. Completare revisione, test e consegna del collegamento osservativo autorizzato, quindi presentare questa scelta. Nessuna politica di conteggio viene implementata prima della risposta.

## Answer — decisione dell’utente, 21 settembre 2026

L’utente approva l’approccio consigliato: nuovo consumo CPU oltre il credito disponibile, al massimo una violazione moderata per addon e giro comune. Il solo debito residuo non conta. Più processi dello stesso addon non moltiplicano le violazioni nello stesso giro. Restano validi i tre incidenti in cinque minuti per la quarantena della versione e i confini del profilo event-driven. I campioni incompleti non diventano zero o stato sano.

Il consenso include il comportamento dei giri periodici e delle osservazioni esplicite già descritto sopra. Non modifica i gate nativi o i profili continui.
