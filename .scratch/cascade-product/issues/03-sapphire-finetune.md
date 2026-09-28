# Evaluate glass and audio from the Sapphire and FineTune sources

ID: 03
Parent: cascade-product
Type: research
Labels: wayfinder:research
Mode: AFK
Status: resolved
Assignee: codex-research-03
Blocked by: none

## Question

How does Sapphire implement its glass treatment, and FineTune its per-app audio management? Read the sources, beyond the READMEs. Identify renderer, APIs, permissions, system minimums, any driver/helper, routing, EQ, limits of the audio path and costs when idle or active. Also identify Sapphire's relevant integrations without importing its whole feature list into the product. Report verified facts and references to commits/files; distinguish functional inspiration from possible reuse, noting the declared licenses without taking a copy as authorized.

## Answer

Research resolved on 4 September 2026 by codex-research-03. [Source report with commit references](../../../docs/wayfinder/research/sapphire-finetune.md).

- Sapphire uses NSGlassEffectView on macOS 26, with additional internal manipulations; on earlier systems it adopts an NSVisualEffectView fallback. The exact resemblance to the Siri in the attachment is still to be evaluated visually.
- FineTune uses process taps and HAL aggregates for per-app volume, routing and multiple outputs, without an additional driver in the path studied. The audio engine must remain independent of the widget's visibility.
- The Core Audio taps primitive requires macOS 14.2; the FineTune project examined sets 15.4, while the README states 15.0. No full compatibility of that code with Cascade on macOS 14 has been demonstrated.
- The code studied includes private APIs, recovery paths and concurrency handling that do not constitute transferable guarantees. Apple's documentation also corrects a source comment about the dispatch of the audio callback.

Reproducible context: branch `codex/research/cascade-references-20260904`, commit `6de9c6635dfa54db5eea4a073ad85a950d1612e1`, worktree `/private/tmp/cascade-wayfinder-references`. No reference app was run; no audio or compatibility test was performed. The necessary tests remain later decisions/prototypes.
