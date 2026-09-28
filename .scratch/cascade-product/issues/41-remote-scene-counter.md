# Collegare il contatore remoto al canale autenticato del prototipo

ID: 41
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: none

## Question

Eseguire il primo incremento sorgente C8 già previsto: il pulsante della scena deve notificare il contatore all'host tramite il canale autenticato esistente, con correlazione della sessione, ordine verificabile, memoria limitata e nessun polling. Completare un check locale della logica e compilare i target separati; non attivare ExtensionKit né dichiarare una prova di click reale.

## Scope

Tre sorgenti del prototipo RemoteUI, un unico check Swift eseguibile e documentazione. Nessuna API SDK produttiva, modifica al launcher/C0d, nuovo entitlement o dipendenza. Protocollo e fixture limitati a echo e osservazione del contatore; un solo evento in volo, budget finito e rifiuto degli eventi incoerenti. Sol medium implementa; il root revisiona, corregge se necessario e verifica prima di proseguire. La distinta qualifica della scena reale resta nel [ticket UI remota](19-extension-host-probe.md).

## Piano operativo

1. Rendere osservabile un evento iniziale e increment/reset, con sessione fresca assegnata dall'host e sequenza verificata.
2. Collegare la UI e il ricevitore XPC, invalidando lo stato su perdita del canale e impedendo code illimitate.
3. Check Swift locale (include rifiuti e terminalità), build dei target separati, revisione root; nessuna attivazione della fixture.
4. Registrare esiti distinti da qualifica nativa, conservare il launcher bloccato e riprendere la frontiera.

## Answer

Implementato il percorso sorgente contatore UI → canale autenticato → riduttore host → acknowledgement. Sessione fresca assegnata dall'host, sequenze e transizioni controllate, un evento in volo, deadline2s, massimo1000 azioni e payload applicativi1024byte. L'host emette osservazioni counterChanged; timeout, perdita del canale e disattivazione rendono terminale la sessione. Nessun polling né nuova dipendenza.

Sol medium ha implementato; il root ha revisionato e corretto logging, dimensione delle risposte, completamenti tardivi durante la disattivazione e ammissione monouso. [Revisione ed evidenze](../../codex-addon/20260920-remote-counter/root-review.md). [Check riproducibile](../../../Prototypes/AddonPlatform/RemoteUI/README.md): compilazione Swift con warnings-as-errors e assert PASS; build Release host/provider/container e verifica deep/strict delle tre firme PASS. Configurazione Xcode e gate C0d invariati.

Il check esegue il vero riduttore in memoria. Trasporto XPC, attivazione della scena, click reali, comportamento delle callback a runtime, accessibilità, uscita del provider e matrice macOS/editori non sono verificati. Nessun prodotto del prototipo avviato o registrato. Il ticket UI remota e il launcher restano aperti/bloccati nei rispettivi ambiti.
