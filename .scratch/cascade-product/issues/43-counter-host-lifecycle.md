# Verificare e completare il ciclo del ricevitore del contatore

ID: 43
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 41

## Question

Ricevitore reale dell’host: configurazione monouso, rifiuti, invalidazione e osservazioni coerenti; test in memoria senza una connessione OS. Completare la copertura del codice di callback effettivo consegnato nel contatore remoto, oltre al solo riduttore. Correggere difetti riprodotti e compilare il prototipo separato.

## Scope

Incremento C8 già approvato, con Ponytail: riuso delle classi reali, callback controllate, nessun modello duplicato. Nessuna attivazione della scena, processo addon, nuovo entitlement, modifica al launcher/C0d o qualifica nativa dedotta. Il root verifica i risultati prima del seguito; più ticket possono essere completati nella stessa prosecuzione.

## Answer

Riprodotte e corrette invalidazioni ripetute dopo un rifiuto: la callback viene ritirata sotto il lock e invocata fuori dal lock. Il check usa il vero ricevitore, senza NSXPCConnection, e copre osservazioni/ack, configurazione monouso, eventi invalidi/anticipati/tardivi e32 chiusure concorrenti con una sola invalidazione.

Tre check locali (riduttore, host e provider), compilati con warnings-as-errors, PASS. Build Release con firma Apple Development dei tre target e verifica deep/strict PASS. [Revisione root ed evidenze](../../codex-addon/20260920-counter-lifecycle/root-review.md), [comandi riproducibili](../../../Prototypes/AddonPlatform/RemoteUI/README.md).

Esecuzione in memoria delle classi effettive, con callback controllate: nessuna connessione OS o scena attivata. XPC autentico, interazione UI, uscita fisica, macOS14 e Intel restano non qualificati. Launcher e gate C0d invariati; nessuna nuova build di Cascade dichiarata.
