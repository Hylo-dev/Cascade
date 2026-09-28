# Instradare il ripiano come pagina contestuale e battito del notch

ID: 83
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: open
Assignee: none
Blocked by: 79, 80

## Question

Implementare il task 7 del [piano del ripiano file](../../../docs/superpowers/plans/2026-09-26-file-shelf.md) usando il registro di pagina e il renderer comune secondo la [specifica approvata del ripiano](../../../docs/superpowers/specs/2026-09-26-file-shelf-design.md). La precedenza generale fra attività, pagine e contesti resta una decisione distinta; questo task applica solo il comportamento del ripiano già approvato. Accettazione: ripiano occupato come predefinito, scelta manuale conservata, drag annullato ripristina la pagina, ultimo file consegnato riporta la selezione ordinaria, un solo notch aperto, doppio impulso una volta per drag, hit testing e focus corretti con Spotlight/display/lock. Test routing e regressioni; prova nativa Spotlight con testo presente, review root e commit. Nessun timer keepalive o falsa scadenza infinita.
