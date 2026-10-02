# Performance

Cascade is on screen all day, so a plugin is judged by what it costs while nothing happens, which should be nothing. The budget the plugin engine is held to is Cascade's own: below 10% CPU while the pointer hovers the notch, and RAM far below 100 MB (spec §1).

## What idle costs

While no source changes, no wake is due and nobody touches a control, no plugin code runs. PluginHost is alive and idle, waiting for a message. The engine's single `DispatchSourceTimer` is disarmed when nothing is due. The hop to main is a pending flag, not a display link: `PluginSurfaceRelay` queues one only when a delivery arrives and none is pending. Opening and closing the notch wakes no plugin; only a surface that becomes visible with stale content asks for one `refresh`.

## Designing finite work

- **Publish on real change only.** An answer costs a dispatch over XPC, a `handle()` and, for every new document, one validation encoding. A document equal to the stored one changes nothing on screen, but the work to produce it was still spent. Answer a `refresh` with the current content, and any other event with only what it changed, an empty `PluginOutput` when nothing did.
- **Let the kernel draw time.** `Clock()`, `Today()`, `Text(_:style:)`, `Text(timerInterval:countsDown:)` and `ProgressView(timerInterval:)` are drawn and kept current by the kernel. A clock, a countdown or a playback position never needs a plugin that wakes every second. Content drawn this way never goes stale, so leave `staleAfter` out.
- **Ask for a wake only when content changes at a known time.** The kernel holds a wake at least a second away; a plugin that wakes often is charged for every run.
- **Offer every size at once.** A widget cannot know the tile the user gave it, so it offers one face per size inside `ViewThatFits`, and the kernel picks the first that fits without asking the plugin again.
- **Keep state small.** A reducer behind a `Mutex` is the usual whole state. A plugin persists nothing: after a restart its sources' latest states and a `refresh` rebuild it.

## Budgets

| Budget | Rule | When it runs out |
| --- | --- | --- |
| Deadline | `handle()` returns within 250 ms. | A hang: PluginHost is killed and the plugin disabled. |
| CPU (`PluginCPUBudget`) | A bucket of 100 ms that refills at 1/200 of elapsed time, about 5 ms per second: a burst at once, half a percent of a core sustained. Charged from the plugin thread's own CPU time, which PluginHost reports with each answer. | The plugin owes a debt and is held until it has rested; repeated debt quarantines it. |
| Publications (`PluginPublicationBudget`) | A burst of eight publications, then one every 250 ms; notices refill every 33 ms, because a held volume key repeats about thirty times a second. | The next event waits for a token while new events coalesce, so the excess becomes fewer, fresher publications rather than dropped ones. |
| Document | 64 KiB, 256 nodes, depth 12, 16 modifiers per node; 48 publications per output. | The document is rejected and the previous one stays. |
| Memory | PluginHost as a whole stays under 96 MiB of physical footprint, read after each answer. | PluginHost is restarted, blaming no plugin. |

## Measures that are not the same

Wire size, validated size and memory footprint are different numbers. A 64 KiB document limit bounds what crosses XPC and what the kernel keeps per publication; it says nothing about what the plugin allocated to build it. PluginHost's memory is measured for the process as a whole, because a shared process cannot say which plugin holds memory; a plugin suspected of holding it can later move to a process of its own through `PluginExecutor` with no change to its code.
