# Lifecycle

A plugin is finite handlers plus the sources its manifest declares. Nothing runs its code but the kernel, and the kernel runs it only when something happened. This page follows a plugin from registration to quarantine; the reasons are in spec §5 and §13.

## Three separate lives

1. **Work.** PluginHost starts with Cascade and stays alive while Cascade runs, idle when nothing changes. Launching it on demand would cost about 66 ms per wake, so it waits until measured RAM justifies it.
2. **Presentation.** Publications live in the kernel's `PluginPublicationStore`, not in the plugin. The last valid content survives a throw and a PluginHost restart, and when PluginHost is killed for one plugin's hang, the others keep showing theirs. A plugin the kernel stops loses its content: one disabled after a hang, quarantined, switched off by the user, or whose feature loses a grant has its publications withdrawn. After a Cascade restart nothing is restored from disk: every plugin is asked for its content again.
3. **Visibility.** It is decided per surface, not by `NotchState`. A widget is visible while its page is open on screen, a notice while it shows; the compact activity, once activities are routed, stays visible while the notch is closed.

## What wakes a plugin

A `PluginEvent` is one of four things, and nothing else runs plugin code:

- `refresh`: give your current content. Sent at registration, after any restart, after the user re-enables or switches on the plugin, and when a visible surface's content went stale.
- `source`: the latest state of a source the plugin declared, as flat typed fields (`PluginSourceEvent`).
- `wake`: the moment the plugin asked for in its last output came.
- `action`: the user touched one of its controls, or Cascade invoked one of its declared actions, such as a preview from the menu (see [Actions](actions.md)).

One event is in flight per plugin. Events that arrive meanwhile wait in its `PluginMailbox`: source states coalesce to the latest per source, refreshes and wakes to one each, and actions queue in order, at most eight. The next event is taken by urgency: the user's actions, then source news, then a refresh, then the plugin's own wake. A plugin therefore receives the latest state, never a backlog, and one that missed a few states still ends up right.

## Sources

Sources come only from the host catalog (`PluginCatalog.sources`); plugins cannot write their own, because inside a shared process a polling source could not be attributed to its plugin. A source is an always-armed listener that costs nothing while it waits, a notification, a socket or a kernel event, and emits its state when it changes.

- PluginHost implements `power` and `bluetooth` (`PluginHostCatalog`). Their states still travel through the kernel, which coalesces, schedules and times every dispatch in one place.
- The kernel implements `volume`, beside the volume key tap it shares a subsystem with. A plugin cannot tell the difference.
- The other catalog entries have no implementation yet, so a feature that declares one is unavailable.

`PluginSourceLeases` shares a source between plugins: it starts with its first holder and stops with its last. A plugin holds the sources of its available features while it is enabled and PluginHost is there, even before anything is on screen, so a plugin can notice an event and publish in response, the way Music will notice playback starting. While a source runs the leases keep its latest state, so a plugin that starts later is primed with it; a source that stops forgets its state, which would be stale by the time it starts again.

## Opening, closing and staleness

The notch opens on hover, often, and the kernel never tells a plugin that it opened or closed. A publication may say how old its content may grow, `staleAfter`, from one second to a day. When a surface becomes visible and its publication is older than that, the kernel sends one `refresh` and renews the content's age, so a plugin with nothing new is not asked again at the next opening. Content the kernel draws itself, such as a clock, never goes stale and leaves `staleAfter` out. Ages are measured on the wall clock, since content ages while the Mac sleeps.

## Wakes

A plugin that needs a cadence asks for it: `PluginOutput.wake` is the date it wants to run again. Each output's `wake` replaces the previous one and an output without one cancels it. A wake asked for sooner than a second away comes a second away. The kernel waits for it on the wall clock, so a wake asked for midnight comes at midnight even across sleep. One `DispatchSourceTimer` serves every plugin's wake, watchdog and retry, and it is disarmed when nothing is due. Most plugins need no wake at all: a clock face or a countdown is drawn by the kernel.

## Publications

`PluginPublicationStore` is the source of truth for what is on screen. A publication with a document replaces what the feature showed on that surface; one without a document withdraws it. Revisions come from one counter, so a revision names exactly one stored document. A document equal to the stored one changes nothing, not even the revision, though it renews the content's age. A notice is an event, not a state, so it is stored again under a new revision even when it equals the last one, and the notch shows it again.

## Switching a plugin off

The user's switches in Settings (the Alerts section of the Widget page) call `setEnabled`. A plugin switched off stays loaded in PluginHost but runs nothing: its content leaves the screen, its sources are released and an answer still in flight is dropped. Switched back on, it leases its sources again and gets a `refresh`.

## Restarts and priming

Whenever a plugin may have lost its memory, after a retry, a PluginHost restart or a re-enable, the kernel primes it: the latest state of every source it holds, then a `refresh`. That is all a plugin needs to rebuild what it shows, so a plugin persists nothing.

**A lost result does not repeat an action.** Whatever ends a dispatch early, a throw, a crash or a kill, the kernel primes the plugin instead of sending the event again, so an action that was in flight is never delivered twice: its effect may already have happened. A retry also clears whatever was waiting in the mailbox. An answer that arrives from a dispatch the watchdog gave up on is ignored.

## Failures

`StandardHealthPolicy` turns incidents into reactions; `PluginHostSupervisor` decides when a lost PluginHost comes back.

| Failure | Reaction |
| --- | --- |
| `handle()` throws | Retry after 1, 5 and then 30 s. The fourth incident of any kind but a hang within five minutes quarantines. |
| PluginHost dies with a plugin inside `handle()` | Counts against that plugin like a throw. |
| Invalid publication, CPU debt | Counts as an incident; the plugin returned, so there is nothing to retry. An invalid publication is rejected and the previous one stays. A plugin in debt is held until it has rested. |
| Hang: `handle()` past 250 ms | The watchdog kills the PluginHost incarnation of the handshake with SIGKILL and PluginHost comes back for the others at once. The hung plugin's content is withdrawn and it stays `disabledAfterHang` until the user re-enables it or Cascade restarts; a second hang since Cascade started quarantines it. |
| PluginHost crashes with nothing in flight | Blamed on PluginHost. It comes back after 1, 5 and then 30 s. |
| PluginHost past 96 MiB | Checked after each answer, so nothing polls. PluginHost is killed blaming no plugin, and comes back like after a crash. |
| Three idle crashes or memory kills, in any mix, within five minutes | PluginHost is given up on. Settings show it stopped, with a Restart button. |
| A new PluginHost silent for 30 s at handshake | Lost like a crash with nothing in flight. |

PluginHost never comes back sooner than ten seconds after its last launch, because launchd holds back a service that died that young until then. The watchdog arms only on dispatches to an incarnation that completed its handshake, so it never times a host that is not there. Re-enable gives a quarantined plugin a clean history; a plugin disabled after a hang keeps its history, so a second hang quarantines it. Settings show every plugin's state (Widget page, Plugins section) with Re-enable where it applies.
