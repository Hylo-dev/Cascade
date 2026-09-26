# Disegnare Notch software e Dynamic Island a goccia

ID: 73
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: codex/multi-display
Blocked by: 72

## Question

Implementare e verificare il task 5 del [piano multi-display](../../../docs/superpowers/plans/2026-09-24-multi-display-notch.md) rispettando la [specifica](../../../docs/superpowers/specs/2026-09-24-multi-display-notch-design.md). La tranche esecutiva è autorizzata dalla richiesta del 25 settembre; chiudere solo con prove e revisione.

## Answer

Implementati sporgenza software, misure indipendenti delle attività e contorno a goccia. Le transizioni mantengono forma, maschera e hit test coerenti; il cambio stile richiude prima la superficie. Compatibilità del contesto pubblico preservata.

Prove: 103 test in sei suite, 30 test del coordinatore e confronto PNG del renderer. Revisione indipendente PASS/PASS dopo un giro correttivo: [rapporto](../../../.superpowers/sdd/2026-09-24-multi-display-notch/task-5-rereview-1.md). Il confronto geometrico sintetico non qualifica un monitor esterno fisico; il collegamento di Impostazioni e Spotlight è nel ticket successivo.
