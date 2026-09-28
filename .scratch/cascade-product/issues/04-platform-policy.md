# Define macOS compatibility and allowed integrations

ID: 04
Parent: cascade-product
Type: grilling
Labels: wayfinder:grilling
Mode: HITL
Status: resolved
Assignee: none
Blocked by: 01, 02, 03

## Question

What is the product's minimum macOS, and which features may be available only on newer versions? The code starts from macOS 14 and already uses private SkyLight; direct distribution with Homebrew is confirmed. In light of the research, which private APIs or fragile techniques are allowed, with which fallbacks and compatibility commitments? Decide per capability, including glass, media, notifications, search, module loading and audio, without assuming that outside the Store everything is automatically feasible.

## Realignment of 14 September 2026

For the addon subsystem the current plan keeps macOS 14 as the minimum and native public APIs, without loading addon code into the graphics process. It is a project constraint, not a qualification on macOS 14. The global decisions on the other integrations and the actually verified matrix remain open. Reference: [addon plan constraints and status](../../../docs/superpowers/plans/2026-09-10-addon-runtime-completion.md).

## Choice presented: 20 September 2026

The macOS 14 minimum and the public APIs for the addon subsystem are already approved constraints; the launcher stays blocked by explicit decision. They must not be requested again.

For the product's new general integrations, it remains to choose whether to allow only public paths (accepting reduced functional coverage where necessary), or to also evaluate private techniques one by one, with fallbacks and compatibility to be verified. The private code already present does not constitute a general authorization to add more. The choice does not authorize reads of personal data, new macOS permissions or exceptions to the addon lifecycle.

The recommendation is to use public APIs as the default path and to submit each possible private exception as a scoped decision, with explicit benefit, fallback and maintenance cost. This keeps the ability to evaluate the requested capabilities without approving fragile techniques wholesale. The ticket stays open and does not attribute this preference to the user.

## Answer: 20 September 2026

The user approves the recommendation: public APIs by default; each new private exception requires a scoped decision with benefit, fallback, compatibility and maintenance cost. No general authorization for new private APIs. The existing, already approved integrations remain as they are; this choice neither rewrites nor implicitly extends them.

macOS 14 is kept as the project minimum already confirmed in the [approved interactive spec](../../../docs/superpowers/specs/2026-09-04-interactive-notch-design.md), without declaring a qualification on all versions/hardware. Newer capabilities must have explicit availability and a fallback path; absence or a denied permission does not become simulated success.

| Capability | Rule for the next increments |
| --- | --- |
| Glass and presentation | Keep the approved engine and contracts; new public integrations and a fallback consistent with the accessibility preferences. |
| Media, notifications, search | Keep the already approved integrations. Evaluate any new private access separately; no universal reading or Spotlight parity inferred. |
| Audio and devices | Favor public paths; availability, consent, hardware and quality require the tests of the dedicated tickets. |
| Addon modules | Process boundary already approved; no external code in the graphics process. Launcher blocked as long as the compliant exit proof is missing. |

This is a resolved project policy, not the passing of the native tests. The choices for the individual experiences remain in the dedicated tickets; no access to personal data or change of permissions is implied.
