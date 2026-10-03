# Caffeinate: Vorssaint behavior, provenance and licensing

Research date: 3 October 2026. Cascade branch: `cava/caffeinate`, created from
`39d86ec` (`cava/screenshot-tool`). Existing staged and untracked files were preserved.

## Scope and current status

The initial reference requested a coffee cup with title and session status. The
subsequent UI revision removes the capsule background, caps the effective grid size at 4x2, and
adds a text-free cup. The legacy adapter doubles manifest columns, so plugin
sizes 2x2 and 1x1 render as grid footprints 4x2 and 2x1. Clicking the cup toggles the session. Options must cover
the other widgets inside the notch; the missing shared addon capability is
tracked as `ADDON-NOTCH-OPTIONS` in `docs/TODO.md`.
The supplied image is a layout reference; its Do Not Disturb behavior is not part
of this feature.

The user approved an independently authored native implementation after reviewing
the GPL/MPL implications. Cascade now implements the adaptive widget through its existing
plugin publication and action route, backed by a background IOKit assertion owner.
No upstream source, assets, tests or translations have been incorporated. A
project-wide MPL license has not been applied; that remains a separate decision.

## Pinned reference and credits

- Project: [Vorssaint, maintained by Vorssaint](https://github.com/vorssaint/vorssaint-utils).
- Inspected revision: [`aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958`](https://github.com/vorssaint/vorssaint-utils/tree/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958).
- Core: [`KeepAwakeManager.swift`](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/KeepAwakeManager.swift).
- Notch session presentation: [`NotchKeepAwakeSupport.swift`](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/Notch/NotchKeepAwakeSupport.swift).
- Automation behavior: [`KeepAwakeAutomationSupport.swift`](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/KeepAwakeAutomationSupport.swift).

These source files identify `GPL-3.0-or-later` and copyright 2026 Vorssaint.
The repository contains the [GPLv3 license text](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/LICENSE).
Its [trademark policy](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/TRADEMARKS.md)
separately reserves its branding and trade dress. Do not import its app icon,
logo, identity or branded styling based on the source license.

The bundled acknowledgment in `Cascade/Resources/CaffeinateCredits.md` records:
“Keep Awake behavior informed by Vorssaint (copyright 2026 Vorssaint). Cascade's
implementation uses Apple IOKit power-management APIs; no Vorssaint source code
or assets are included.” Any later imported material needs its own
file/revision/license/author record and accompanying notices.

## Licensing implications

No project-wide LICENSE or COPYING file was found in the inspected Cascade
checkout. FFmpeg notices cover that component and do not establish Cascade's
own license.

GPL permits use, modification and commercial distribution. Distribution of a
modified combined program requires GPL licensing of that work, preservation of
notices, marking modifications, a license copy, and provision of corresponding
source. Private use and modification are treated differently. Attribution alone
does not satisfy distribution requirements. See [GPLv3 sections 2, 4, 5 and 6](https://www.gnu.org/licenses/gpl-3.0.html).

MPL 2.0 applies copyleft to covered source files. Distributed modifications to
those files must remain available under MPL; separate independent files can
have different licenses. Its compatibility mechanism permits combining eligible
MPL code with GPL code, additionally distributing the MPL portions under the
secondary license. It does not turn imported GPL code into MPL-only code or
remove GPL obligations for the combination. See [Mozilla FAQ Q11–Q14](https://www.mozilla.org/en-US/MPL/2.0/FAQ/)
and [MPL 2.0 section 3.3](https://www.mozilla.org/en-US/MPL/2.0/).

Recommendation: author a small native implementation from Apple's API contracts
and the desired behavior, without copying or translating upstream implementation
expression. Credit Vorssaint as the functional reference. This preserves the
option to license original Cascade code under MPL 2.0. Applying a project license
also requires checking ownership and existing third-party components; this note
does not perform that project-wide audit.

## Behavior and implementation boundaries

Vorssaint's core owns an idle-system assertion and optionally an idle-display
assertion. Sessions can be indefinite, timed or end at a chosen date; stopping
releases the assertions. `scheduleEnd` uses a one-shot timer. `applyAssertions`
checks acquisition results, but `activate` still sets the UI active flag without
propagating acquisition failure; release errors are ignored. The battery watch
schedules a 30-second repeating timer with 5-second tolerance even when the
threshold is disabled. These are source observations, not measured CPU results.
[Core source, lines 229–291, 660–715 and 1116–1147](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/KeepAwakeManager.swift).

Closed-lid operation is a separate privileged feature using global `pmset`
settings and administrator/sudoers setup. It is not supplied by ordinary idle
assertions. That path, synthetic pointer activity, automation rules and brightness
control should not enter the initial toggle/timer implementation without a
separate product decision. [Core source, closed-lid and pointer sections](https://github.com/vorssaint/vorssaint-utils/blob/aa6ddcb901acb0a61f6bfc9ed4753c6fbffcf958/Sources/Vorssaint/Services/KeepAwakeManager.swift).

## Amphetamine reference

[Amphetamine by William Gustafson](https://apps.apple.com/us/app/amphetamine/id937984704)
is a functional reference for indefinite/timed sessions and display options.
The public [Amphetamine repository](https://github.com/x74353/Amphetamine/tree/84740c43c66ee9fae9e6f668a7c129e84e9fd352)
is MIT-licensed (copyright 2023) but contains additional resources and translations,
not the main application's source. Its license must not be represented as the
main app's source license.

[Amphetamine Enhancer](https://github.com/x74353/Amphetamine-Enhancer/tree/20b6f4c5452bea55c7de8e57f5baa0cdd4b39d8c)
is a separate MIT companion (copyright 2020). Its launch agent periodically checks
process/lid state and its lid helper uses a private power-management interface.
[Power Protect](https://github.com/x74353/Amphetamine-Power-Protect/tree/4937590499c5504f9623dcf290c099349cf8e8fd)
is a separate MIT resource (copyright 2023) involving administrator setup and
system-wide sleep settings. Neither is needed or included in this implementation.

## Implemented scope and verification

A serial background actor owns a system-idle assertion and an optional display-idle
assertion. Acquisition errors are reported; partial acquisition rolls back;
failed releases retain their IDs for retry. Plugin disable and app termination
wait asynchronously for an in-flight acquisition and release its resources.
A finite session has a native timeout plus one app deadline callback. Indefinite
sessions have no timer. The widget displays a fixed end time rather than a
countdown and requests no periodic plugin wake.

The widget declares plugin sizes 2x2 (default) and 1x1, mapped to effective
grid sizes 4x2 and 2x1. ViewThatFits selects a wide text face or a compact cup.
Obsolete saved 6x2/8x2 placements shrink to 4x2 without moving the origin.
Verification must inspect routed GridSpan values, not just manifest dimensions. There is no capsule background or intermediate
Updating label. A finite native symbol effect animates the off/on glyph change
and respects Reduce Motion. Glyph identity survives replacement of the
revision-bound hit area. Indefinite and timed assertion support remains in the
native session owner, but the prior external options menu has been removed.
Details are passive until the common addon route can present an options page
inside the notch. Credits remain bundled in CaffeinateCredits.md.
No closed-lid override, pointer synthesis, app/download triggers, battery polling,
brightness control or external executable is included in this initial scope.

Apple's public [IOPMLib header](https://github.com/apple-oss-distributions/IOKitUser/blob/main/pwr_mgt.subproj/IOPMLib.h)
defines idle assertions and native timeout actions. Idle assertions do not prevent
explicit Sleep or closed-lid sleep, and a display-idle assertion does not wake an
already sleeping display. Apple IOKit and the native coffee SF Symbol are credited.

Verification results and remaining real-app interaction checks are recorded in
`docs/superpowers/verification/2026-10-03-caffeinate.md`. Offscreen rendering and
automated lifecycle tests do not substitute for physical clicks in the running app.
