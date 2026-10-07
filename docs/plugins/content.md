# Content

A plugin's content is a `PluginDocument`: a schema version, a root `PluginNode` and the document's [glass lights](../architecture/glass-lighting.md). It is a value, the same in process and on the wire, and the kernel draws it. A plugin never supplies a view, which is what lets the kernel bound, diff and render its content without trusting its code (spec §8).

## Three tiers

1. **Tier 1, the portable vocabulary.** SwiftUI-shaped nodes and modifiers (`PluginNodeKind`, `PluginModifier`), drawn by CascadeKit's nominal, recursive `PluginNodeView`. Every node exists because a real consumer needs it.
2. **Tier 2, host-native components.** A `Component(id:version:parameters:)` node names a component the kernel draws natively. The catalog (`PluginCatalog.components`) lists `audio.spectrum`, `media.scrubber`, `audio.outputPicker`, `power.battery`, `volume.level`, `bluetooth.device` and `bluetooth.battery`, each at version 1. Cascade draws the last four today (`PluginComponentView`), from the parameters the plugin passes; the first three wait for the services and Music sub-project, which feeds them from kernel services instead. A component the kernel does not draw keeps its frame and draws nothing, and a document may show only the components its feature declared.
3. **Tier 3, real SwiftUI.** Only for system surfaces such as the file shelf. It is not part of the plugin SDK.

## The builder

`CascadePluginSDK` mirrors SwiftUI so that a plugin's content reads like the SwiftUI it becomes. Views are free functions with SwiftUI's names, collected by the `PluginNodeBuilder` result builder, and modifiers are methods on `PluginNode` that return a copy with the modifier appended, in SwiftUI's order:

```swift
HStack(spacing: 8) {

    Image(asset: "artwork")
        .frame(width: 32, height: 32)
        .clipShape(.roundedRectangle(cornerRadius: 6))

    VStack(alignment: .leading) {

        Text("Song")
            .font(.headline)
            .lineLimit(1)

        Text("Artist")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    Spacer()

    Toggle(isOn: isPlaying, action: "togglePlayback") {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
    }
    .contentTransition(.symbolEffect)
}
```

`PluginBuilderTests` checks that this row is exactly the tree written by hand. Inside a block, an `if` that does not hold adds nothing, an `if`/`else` adds the branch taken, and a `for` adds what each pass lists: the loop unrolls into fixed children, it is not a dynamic list. Building never throws and checks nothing; `PluginDocument(root:glassLights:)` validates the tree and throws when it breaks a rule. The SwiftUI style rules apply: one modifier per line, siblings separated by a blank line.

`Text` shows its string as given, so a plugin localises first, with its own String Catalog, as `VolumeNotice` does.

## Vocabulary

| Group | Builder |
| --- | --- |
| Layout | `VStack`, `HStack`, `ZStack`, `ViewThatFits(in:)`, `Spacer`, and `Regions`, the root of a notice or an activity: a notice's three children are the compact leading, compact trailing and minimal regions, an activity's four add the expanded one |
| Content | `Text`, `Image(systemName:)`, `Image(asset:)`, `Circle`, `Capsule`, `RoundedRectangle(cornerRadius:)`, `Component(id:version:parameters:)` |
| Kernel-drawn time | `Clock()`, `Today()`, `Text(_:style:)` with `.time`, `.date` or `.relative`, `Text(timerInterval:countsDown:)`, `Text(countdownTo:style:)`, `ProgressView(timerInterval:)` |
| Progress | `ProgressView(value:total:style:)`, linear or circular |
| Controls | `Button(action:label:)`, `Toggle(isOn:action:label:)`, `Slider(value:in:step:action:)` |
| Modifiers | `font`, `foregroundStyle` (color, hierarchical level or gradient of two to four colors), `frame`, `padding`, `opacity`, `clipShape`, `lineLimit`, `minimumScaleFactor`, `contentTransition` (`numericText`, `symbolEffect`), `transition` (`opacity`, `scale`, `move`), `accessibilityLabel`, `overlay`, `background`, `id` |

`overlay` and `background` take their content as the node's next layer, several nodes laid in a `ZStack`. `ViewThatFits` is how a widget, which cannot know the size the user gave it, offers a face per size, largest first, as `ClockPlugin` does. Kernel-drawn time is drawn and kept current by the kernel, so a clock or a countdown costs the plugin nothing while it ticks.

### Kernel-drawn times

`Text(countdownTo:style:)` (the `countdown` node) is the time left until a date in the Dynamic Island's compact format: whole hours from one hour (`2h`), whole minutes from five minutes (`24m`), `m:ss` below that (`4:59`), and `0:00` at the end. Every unit is floored, so it never shows less time than is left. It is redrawn only when its text changes, on a sparse `TimelineSchedule` (`CompactCountdownSchedule`) whose entries are those instants: a countdown of eight hours wakes the view eight times, not once a second, and the plugin not at all. The schedule ends with the change at `end`, so a finished countdown asks for nothing more. `Text(timerInterval:countsDown:)` stops the same way, at the end of its interval.

Both nodes draw their digits with `RollingDigitsLabel`, the control Music's progress labels use: only the digits that change roll, in the render server, and under Reduce Motion they change in place. VoiceOver reads the label as one static text with the current value.

A time node takes its font and colour only from its own modifiers: the innermost `.font(_:)` and the innermost `.foregroundStyle(color)` on the node itself. An ancestor's style does not reach it, because the label is an AppKit view and not a SwiftUI `Text`; a foreground style that is not a plain color (a hierarchical level, a gradient) falls back to white. Digits are always monospaced, so a roll never moves its neighbours.

Not in v1: `ForEach` and dynamic lists, grids and gestures. `Image(asset:)` draws nothing until the asset pipeline exists (see [Services, storage and assets](services.md)).

## Limits

`PluginDocument` enforces, in one depth-first walk that stops at the first violation, and then by encoding the document once to check its real size:

- 64 KiB per document, 256 nodes, depth 12, 16 modifiers per node, eight glass lights;
- 4 KiB per text, 512 bytes per accessibility label;
- a component takes at most 16 parameters, each a string of at most 256 bytes, a finite number or a bool;
- lengths are finite, from 0 to 10,000 points; colors, opacity and progress stay in range; a slider's range and step make sense; a timer does not end before it starts;
- only containers and labelled controls take children, and `Regions` is the root of a notice or an activity, with three regions or four. The publication then fixes the number: a notice has exactly three and an activity exactly four.

A `PluginOutput` carries at most 48 publications, one per feature and surface. A document that breaks a limit is rejected whole and the previous one stays on screen; the kernel also rejects a publication for a feature or surface its manifest does not declare, or that shows an undeclared component.

## Options page

A widget whose feature declares `supportsFullscreen` may publish a second tree with its document: `PluginDocument(root:optionsRoot:optionsAction:)`. `optionsAction` names a button in the widget that opens the page; validation rejects an options page without an opening button in `root`, an opener without a page, and a page whose root is `Regions`. Both trees share the document's limits, and every control on the page must be one of the feature's declared actions, or the kernel rejects the publication.

Cascade owns everything around the page: pressing the opener records the click, and only once the broker accepted it does the page replace the grid, in the expanded footprint below Cascade's Back control (about 400 by 86 points in the default notch, so design it to fit without scrolling). Back, Escape and closing the notch dismiss it and restore the grid. The page's controls act only while the page that drew them is shown, and a publication updates the open page in place, node by node, like the widget. The user can also open it from the widget's context menu, so a face too small to show the opener still reaches it.

`ViewThatFits` measures each face's ideal width against the tile, so a face held at a fixed width wider than its tile never fits and the widget falls back to its smallest face in every size. In the default notch a tile two manifest columns wide (`2x1`, `2x2`) is 110 points wide and a one-column tile 52: hold a large face at 100 points, as the battery and Caffeinate widgets do.

## Identity

Identity is structural by default: a node is its parent's identity, its position and its kind, so a node whose kind changes in place becomes a new node, as a SwiftUI view of another type would. `.id(_:)` gives a node an explicit identity, which follows it wherever it moves; explicit ids must be unique within a document.

## Normalization and diff

On the engine queue the kernel flattens a valid document into a `PluginNodeTable`: one contiguous entry per node, each with a hash of its own properties and a hash of its whole subtree. `PluginNodeDiff` walks the new table from the root and stops at every subtree whose hash did not change, so an unchanged subtree costs one comparison however large it is. The wire always carries full snapshots and the kernel diffs them; in process, the value passes without encoding. On the main thread `PluginNodeStore` applies the diff to one `@Observable` `PluginNodeModel` per node, touching only the models the diff names, so SwiftUI redraws only their views.
