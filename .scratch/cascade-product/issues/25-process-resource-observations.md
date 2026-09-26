# Osservare le risorse di un processo senza abilitare il launcher

ID: 25
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: none

## Question

Implementare lettura pubblica libproc e riduzione pura degli intervalli CPU con identità osservata nello stesso record, aritmetica controllata e metriche assenti distinte da zero. Nessuna autorità di arresto, autenticazione o enforcement dedotta dalle metriche.

## Context

Incremento indipendente C4 autorizzato dalla prosecuzione del 18 settembre. [Piano](../../../docs/superpowers/plans/2026-09-18-addon-process-metrics.md). Qualificazione launcher, C0d e controllo nativo completo restano aperti.

## Progress

Disegno esaminato; implementazione e verifiche da completare.

## Answer

Lettore libproc v0 e riduttore CPU interni implementati, 33 test mirati passati e revisione indipendente PASS. Suite completa 929 test / 85 suite, build firmata e riavvio verificati. [Consegna e qualifiche residue](../../../docs/superpowers/verification/2026-09-18-addon-process-metrics.md). Nessun enforcement o launcher abilitato; misura CPU indipendente, associazione autenticata e controllo nativo completo restano aperti.
