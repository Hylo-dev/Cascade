# Contratti e confine autorizzato del ripiano file

ID: 76
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: none

## Question

Il modello del ripiano è fissato in [Definire raccolta e durata dei file nel ripiano](10-file-shelf.md).

Registrare il lavoro interno già consegnato per il task 1 del [piano del ripiano file](../../../docs/superpowers/plans/2026-09-26-file-shelf.md): contratti pubblici bounded, `FileWorkspaceClient` sul client servizi comune e autorità host su ServiceWork canonico. La chiusura riguarda soltanto questo confine e i test modellati; la qualifica nativa resta nel ticket successivo.

## Answer

I commit `eb18b8e` e `f402d8c` hanno consegnato contratti, client SDK e confine di servizio interno. La [verifica del percorso runtime](../../../docs/superpowers/verification/2026-09-26-file-workspace-runtime.md) registra 21 test FileWorkspace passati (7 contratti, 4 client, 10 autorità), 22 test ServiceBroker passati e review root con correzioni per errori di dominio stabili e testo host sanitizzato. La build di sviluppo è riuscita e Cascade è stata riavviata dalla build aggiornata. Il full package ha avuto un fallimento intermittente preesistente in NotchControllerTests, superato al rerun mirato: non è dichiarato interamente verde. Queste prove non qualificano bootstrap, trasporto nativo, provider firmato sul percorso comune o uscita fisica; il launcher resta bloccato.
