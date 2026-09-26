# Preparare il provider Clock con il solo SDK pubblico

ID: 44
Parent: cascade-product
Type: task
Labels: wayfinder:task
Mode: AFK
Status: resolved
Assignee: none
Blocked by: 24

## Question

Preparare la sorgente Clock prevista da C6 come libreria di esempio indipendente, prima del contenitore nativo: pubblicazione dichiarativa clock hourMinute, identità assegnata dall'host, nessun tick o loop del provider. Riutilizzare SDK, contratti e convenzioni degli esempi esistenti; non collegare il provider al processo grafico né sostituire il widget corrente.

## Scope

Package sorgente StandaloneClock con dipendenza SDK esplicita, manifest validabile, provider finito e check comportamentali. Build indipendente e controllo dei confini aggiornato per includerlo. Nessuna firma/identità inventata, nessun processo addon avviato, nessuna qualifica bundled/native o migrazione Clock dichiarata. Sol medium implementa l'esempio; root cura integrazione dei controlli, revisione e consegna.

## Answer — 20 settembre 2026

Consegna sorgente completata e revisionata dal root dopo implementazione Sol medium: [provider, manifest e guida](../../../Examples/StandaloneClock/README.md). Build indipendente e3 test Swift PASS,21 test del checker senza skip e5 fixture dello script build PASS. Il controllo obbligatorio include Clock: audit corrente4 package/11 target/90 sorgenti/140 import. La copia SDK contiene78 sorgenti pubblici identici agli input verificati.

[Verifica e limiti](../../../docs/superpowers/verification/2026-09-20-standalone-clock-source.md), [revisione root](../../codex-addon/20260920-clock-source/root-review.md), [esiti](../../codex-addon/20260920-clock-source/results.json). Nessuna integrazione nell'app, migrazione ClockWidget o qualifica nativa; C6 e launcher rimangono bloccati. Nessun nuovo binario app necessario: normale riavvio della build firmata esistente verificato, PID90193→34140 e stabilità5s. Budget settimanale osservato3%, tetto20%; nessun agente residuo.
