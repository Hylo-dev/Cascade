# Verificare e completare il ciclo del contatore nel provider

ID: 42
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 41

## Question

Modello reale del provider: ack, timeout, invalidazione e risposte tardive; test in memoria senza avviare ExtensionKit. Completare la copertura del codice di callback effettivo consegnato nel contatore remoto, oltre al solo riduttore. Correggere difetti riprodotti e compilare il prototipo separato.

## Scope

Incremento C8 già approvato, con Ponytail: riuso delle classi reali, callback controllate, nessun modello duplicato. Nessuna attivazione della scena, processo addon, nuovo entitlement, modifica al launcher/C0d o qualifica nativa dedotta. Il root verifica i risultati prima del seguito; più ticket possono essere completati nella stessa prosecuzione.

## Answer

Riprodotto e corretto il completamento perso durante invalidazione iniziale: il modello reale conserva e ritira una sola callback, completata su ack, timeout o perdita del canale. Sol medium ha implementato; il root ha revisionato e reso deterministica la consegna controllata degli ack nel check, senza affidarsi a Task.yield. Coperti ack invalidi/tardivi, un solo evento in volo, inizializzazione ripetuta e timeout reale2s.

Tre check locali (riduttore, host e provider), compilati con warnings-as-errors, PASS. Build Release con firma Apple Development dei tre target e verifica deep/strict PASS. [Revisione root ed evidenze](../../codex-addon/20260920-counter-lifecycle/root-review.md), [comandi riproducibili](../../../Prototypes/AddonPlatform/RemoteUI/README.md).

Esecuzione in memoria delle classi effettive, con callback controllate: nessuna connessione OS o scena attivata. XPC autentico, interazione UI, uscita fisica, macOS14 e Intel restano non qualificati. Launcher e gate C0d invariati; nessuna nuova build di Cascade dichiarata.
