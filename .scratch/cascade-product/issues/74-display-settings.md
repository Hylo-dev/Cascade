# Collegare preferenze display e superfici ausiliarie

ID: 74
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/multi-display
Blocked by: 73

## Question

Implementare e verificare il task 6 del [piano multi-display](../../../docs/superpowers/plans/2026-09-24-multi-display-notch.md) rispettando la [specifica](../../../docs/superpowers/specs/2026-09-24-multi-display-notch-design.md). La tranche esecutiva è autorizzata dalla richiesta del 25 settembre; chiudere solo con prove e revisione.

## Answer

Implementate le preferenze native per display e routing, con target offline conservato e scelte temporanee per identità non persistenti. Settings distingue ancora della finestra e riserva di focus; comandi globali e contestuali esplicitano il target. Spotlight attende la chiusura reale, conserva la riserva finché la finestra nativa è visibile e recupera aperture mai avvenute; lock e preview non lasciano riserve orfane.

Prove: 44 test coordinator, 9 routing, 68 controller nelle verifiche pertinenti; 15 Settings firmati prima dell’ultima correzione e 2 nuove regressioni firmate RED→GREEN sulla correzione finale. Script Spotlight e 7 casi droplet passano. Revisione finale scoped PASS/PASS dopo tre correzioni: [rapporto](../../../.superpowers/sdd/2026-09-24-multi-display-notch/task-6-rereview-3.md). Il nuovo run completo Settings è nella verifica di consegna: gli ultimi tentativi si sono fermati per timeout dell’approvazione prima del lancio. Nessun riavvio né qualificazione fisica multi-monitor dichiarata qui. [Evidenze](../../../.superpowers/sdd/2026-09-24-multi-display-notch/task-6-report.md).
