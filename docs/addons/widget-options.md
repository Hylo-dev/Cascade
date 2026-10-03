# Widget detail options

A widget can open bounded detail content inside Cascade's existing expanded
notch. The host supplies native Back, the sensor reservation, finite transitions
and restoration of the ordinary widget grid. The provider supplies values and
declared actions, never a window, frame or executable host view.

The host reserves the entire upper navigation band for the physical cutout,
`chevron.left` Back and Settings. A native divider marks its lower edge. Detail
content is clipped below that band and scrolls vertically when it exceeds the
configured notch body; providers cannot draw over the chrome or enlarge the notch.
Providers supply only body content and do not duplicate navigation or top padding.

## Declare the feature

Set `supportsFullscreen: true` on the feature canonically assigned to the widget
publication. The default is false, and false is omitted from encoded manifests.
Declare both the opening action and every compact/detail control action:

```json
{
  "id": "display",
  "REQUIRES": [
    { "kind": "hostCapability", "id": "notch.options.v1", "version": ">=1.0.0" }
  ],
  "actions": ["options", "brightness", "dim"],
  "supportsFullscreen": true
}
```

This is a feature fragment, not a complete manifest. Options are negotiated with
the cumulative protocol 1.5 assembly. A host advertises `notch.options.v1` only
when runtime validation and the presenter adapter are connected; without it, the
feature is unavailable. System controls inside detail still need their usual
broker grants and permissions.

## Publish separate compact controls

Use a normal action node for the title/disclosure, alongside independent frequent
controls. Existing content primitives offer progress and buttons; native value
inputs and pickers are separate SDK work.

```swift
let compact = try ContentDocument(
    root: .column([
        .action(ActionDescriptor(id: "options", label: "Display options ›", payload: Data())),
        .progress(value: 0.6),
        .action(ActionDescriptor(id: "brightness", label: "Increase brightness", payload: Data()))
    ]),
    privacy: .publicContent,
    accessibilityLabel: "Display controls"
)
```

Publish this as the widget's ordinary `PresentationSet.widget`. Only the accepted
`options` action should return the detail operation; a brightness action updates
its own state. In a provider importing `CascadeAddonSDK` and `CascadeContracts`:

```swift
func openOptions(
    for action: ActionRequest,
    document: ContentDocument,
    leaseID: UUID
) throws -> OperationRequest {
    try AddonOptions.present(
        for: action,
        document: document,
        leaseID: leaseID
    )
}
```

Return the operation in `ProviderOutput.operations` while handling the delivered
opening action. The document can reuse an existing `PresentationSet.expanded`
value. Retained detail controls use the same declared-action admission, payload
checks, deadlines and final delivery validation as ordinary actions.

## Refresh and lifetime

Keep the initial opening action request ID and accepted lease ID. A same-lease
refresh uses `AddonOptionsRequest` with the current source publication revision,
the initial action request ID and a replacement document. It cannot extend the
original expiry. A source revision change immediately disables old controls;
only a valid refreshed document restores them. `OperationRequest.dismissOptions`
requests dismissal of the canonically owned lease.

There is one active detail and one pending opening globally. Only a visible
ordinary widget can open it. A later compact click revokes the earlier pending
origin. Selected activities and the file shelf have no hidden widget entry
surface. Back, Escape, close, withdrawal, expiry, disable, source/display removal
and connection-generation invalidation revoke authority. Late replies cannot
reopen the page. The unselected contextual shelf slot survives the overlay.

Documents are limited to 128 nodes, depth 8 and 64 KiB, and share existing
aggregate publication/options and owner retained-memory budgets. Runtime replay
history retains at most 256 lease bindings across all live connection generations,
charged at 128 bytes each: 32 KiB total. Back refunds document memory but keeps the
binding charge. Exact owner/generation invalidation refunds only its matching
history. At capacity new leases fail closed; history is never silently evicted.

## Host composition and Debug evidence

The generic host seam is `AddonPresentationBridge` on the service-owned
`NotchEngine`. Its `onWidgetAction` supplies the exact opaque host origin. The
runtime validates canonical owner, feature, generation, accepted action and
resources before supplying `AddonOptionsPresentation` to the bridge. The
synchronous options adapter must preserve that exact origin across actor hops.
Deferred `dismissOptions(leaseID:origin:)` and
`invalidateOptionsControls(leaseID:origin:)` must pass the originally captured
origin; a UUID alone can later refer to another generation's page.

The opt-in Debug app fixture uses the same bridge and container with temporary
widget arrangements and default display preferences. It starts before builtin
sources, media/file-shelf monitors and startup permission requests. It changes
only mock brightness data and never runs a provider or changes display settings.

```sh
/Applications/Cascade.app/Contents/MacOS/Cascade --preview-addon-widget-detail
/Applications/Cascade.app/Contents/MacOS/Cascade --check-addon-widget-detail
/Applications/Cascade.app/Contents/MacOS/Cascade --check-addon-widget-detail --preview-addon-widget-detail
```

The finite compiled-app check presses accessibility compact/detail controls and
native Back, checks exact-origin refresh, pending A/B ordering, stale controls,
rapid transitions and withdrawal, and prints the expanded display/frame plus
visible native hosting-view count. It fails if the visible source is unavailable,
including a locked screen. The check alone terminates after withdrawal; combining
the flags leaves a valid detail open for idle measurement. Programmatic checks
do not prove physical input, hardware multi-display behavior or performance.

External native launcher qualification remains on hold. This host-owned Debug
composition is container evidence, not production transport, addon activation or
launcher qualification.

## Builtin Caffeinate compatibility

The builtin PluginHost v2 adapter uses the same native container. A widget feature
must declare `supportsFullscreen: true`; the host's `PluginEngine` capability
defaults to false and is enabled by the app only when its container is composed.
Legacy absent/false flags remain false and false is omitted from encoding. This
compatibility bridge does not advertise the external `notch.options.v1` assembly
or qualify its launcher.

`PluginDocument.optionsRoot` carries the detail tree, and `optionsAction` names its
ordinary opening button. The two roots share 256 nodes, depth 12, 64 KiB and one
action authorization table. IDs must be unique across both roots. Every control
action must be declared. Busy publications may retain passive detail without an
opening action. One live store refreshes the compact and detail models together;
removed models, revoked origins and stale broker revisions cannot dispatch.

Click the Caffeinate title/disclosure to open options; at the icon-only size,
right-click its widget and choose **Options**. The cup toggles the session.
Duration offers indefinite, 15, 30, 60, 120, 240 and 480 minutes. Selecting a new
duration while off stores the next session's preference; while active it replaces
the deadline from selection, with indefinite removing the deadline. Changing
**Keep display awake** reconfigures native assertions while preserving the current
absolute deadline. **Stop** is inactive while off. **Credits** toggles the inline
functional acknowledgments. Busy snapshots disable all detail actions.

The opener captures a genuine mounted widget origin before broker submission.
The acceptance callback retains that exact click, including when equal requests
arrive out of order. Back/Escape, hiding, withdrawal/disable, display removal and
termination revoke the origin. The underlying contextual slot and selection
remain owned by the common container. No periodic options timer is introduced;
the existing one-shot session deadline handles expiration.

Automated package/controller checks establish these contracts. Native rendered
input, multiple displays and runtime measurements still need their own evidence;
the opt-in Caffeinate Debug preview is intended for that qualification.

```sh
/Applications/Cascade.app/Contents/MacOS/Cascade --preview-caffeinate-options
/Applications/Cascade.app/Contents/MacOS/Cascade --check-caffeinate-options
```

The preview uses the real bundled source, a temporary widget grid and the user's
Caffeinate preferences. The finite check drives rendered accessibility controls
and native session changes, uses a unique isolated preference suite, cleans it
on exit and terminates. An unavailable native control fails the check; a blocked
AX or screen-capture session must be reported separately from package tests.
