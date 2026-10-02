# Actions

A plugin's controls are nodes in its document: `Button`, `Toggle` and `Slider`, each naming an action its feature declares. The kernel owns what happens between the user's touch and the plugin's answer, so a slow or broken plugin can never leave a control stuck, and a stale or forged request finds nothing to run (spec §9).

## Optimistic state

The renderer keeps a control's local value in its `PluginNodeModel`, apart from the published value.

- A `Button` is stateless: SwiftUI shows the press, the action is sent, and whatever it changes arrives as the next publication.
- A `Toggle` flips at once, animated, and sends its action with the new state.
- A `Slider` sends its value when it is released. While it is dragged, incoming publications do not move its thumb.
- The next publication always wins, even when it contradicts the optimistic value.
- With no publication within 1.5 seconds (`PluginNodeStore.confirmationTimeout`), or when the kernel refuses the action, the value reverts, animated.

## From a touch to the plugin

The renderer reports a `PluginActionRequest`: the publication and the revision it was showing, the node it touched and the new value. It names no action. The kernel reads the action from that node in that revision, with the rules of `PluginActionAuthorizer`:

- the request names the revision the store holds now;
- the node exists in it and is a control whose value fits: none for a button, a bool for a toggle, a number within its range for a slider;
- the feature is available and declares the control's action.

Anything else is refused, and the refusal reaches the renderer, which reverts at once. An accepted action becomes a `PluginActionEvent` with the feature, the action and the value, and queues ahead of every other pending event. Grants are checked again when its turn comes, and an action that waited past 1.5 seconds (`PluginKernel.actionTimeout`), which the renderer has already reverted, is refused rather than run late. At most eight actions wait per plugin.

The plugin answers with a publication that shows the new state, which is the confirmation.

## Actions Cascade invokes

Cascade's menu can invoke a declared action for the user, such as the notices' `preview`, through `PluginEngine.invoke`. Such an action reaches the plugin only while it runs and its feature is available and declares the action. There is no control to revert, so a refused one is simply dropped.

## Never repeated

An action is delivered at most once. If PluginHost dies or the plugin throws while handling it, the kernel's retry primes the plugin with its sources' latest states and a `refresh`; the action is not sent again, because its effect may already have happened. A plugin that must make an effect safe to repeat does so itself.
