# Durable addon content

`CascadeContracts`, `CascadePresentation` and `CascadeAddonSDK` are public Swift 6
products with a macOS 15 floor. Every future Cascade widget uses these same
contracts and components as external addons. They grant no origin-based bypass.

`CascadeContent` is a value description, not a transparent replacement for every
`SwiftUI.View`. Components have throwing constructors so validation happens while
building a document, before constructing views. A provider constructs values in
its controlled process; the host renders an admitted document after that process
has exited. No arbitrary view introspection, serialized closures or provider
objects are retained by this path.

```swift
import CascadeContracts
import CascadePresentation

let stop = try ActionDescriptor(id: "stop", label: "Stop focus")
let content = try CascadeColumn {
    try CascadeRow {
        try CascadeSymbol("moon.fill")
        try CascadeText("Focus")
    }
    try CascadeCountdown(until: deadline)
    try CascadeProgress(value: 0.5)
    try CascadeButton(stop)
}
let document = try ContentDocument(
    root: content.contentNode,
    privacy: .publicContent,
    accessibilityLabel: "Focus session"
)
let archive = try document.encode()
let restored = try ContentDocument.decode(archive)
```

## Components and limits

| Component | Description |
| --- | --- |
| CascadeText | Plain text; no markup or URLs are executed. |
| CascadeSymbol | System symbol name, lowercase letters/digits separated by dots; no URL or path. Decorative for VoiceOver; put meaning in text/document labels. |
| CascadeImage | Declared asset ID and required accessible label. A host asset resolver supplies the admitted image; this module never opens a path or URL. |
| CascadeRow / CascadeColumn | Bounded horizontal/vertical composition. The builder supports conditional branches, optional branches and loops. |
| CascadeProgress | Finite value clamped to 0...1 at the Swift factory. Invalid out-of-range wire values are rejected. Native shape rendering exposes a localized percentage. |
| CascadeCountdown | Finite absolute deadline; SwiftUI timer text counts down and stops at zero. |
| CascadeClock | Closed hourMinute/hourMinuteSecond format, localized through SwiftUI. Updates follow minute/second boundaries while mounted. |
| CascadeButton | ActionDescriptor containing ID, required accessible label, schemaVersion 1 and at most 4 KiB opaque payload. No provider closure. |

Documents have a 64 KiB encoded limit and a raw-byte check before JSON decoding.
Tree depth is at most 8, counting the root as 1; at most 128 total nodes; text and
labels at most 4 KiB UTF-8; at most 64 unique declared asset IDs and 64 unique
action IDs. Referenced images must occur in the document asset list. Strings with
invalid image/button labels, duplicate actions, unknown schema/fields, mixed node
fields, nonfinite progress/dates and URL-shaped symbol/asset identifiers fail
before view construction. Symbol syntax is validated without importing AppKit
into contracts; actual symbol availability depends on the host OS. Asset
ownership, decoded-image quotas and service payload schema validation are host
admission responsibilities in P2.

The existing validated `ContentNode` struct remains the wire representation;
throwing static factories provide enum-like construction without a parallel model.
New optional fields are `accessibilityLabel` (image only), `actionPayload` (action
only), and `clockFormat` (clock only). A clock without a format defaults to
hourMinute. Legacy actions without a payload dispatch empty Data.
`ContentDocument.assetIDs` and its convenience initializer expose the requested
SDK spelling; the existing wire field remains `assets`. Privacy now encodes
`publicContent`/`sensitive`; decoding accepts the initial `public` spelling and
Swift `.public` remains an alias for `.publicContent` during v1 development.

## Optional glass lighting

Content schema1 remains supported and is still the default. Schema2 adds the optional
`glassLights` array: at most eight immutable `GlassLight` values, with finite normalized
sRGB color, position, radius and intensity. These values count within the same64KiB
content budget. A schema1 document cannot carry the new field, even as explicit null;
a schema2 document may omit it or use an empty array. No provider process is kept alive
merely to retain a light value.

The [lighting contract](../architecture/glass-lighting.md) shows both the serializable
Swift document and the native `.notchGlassLights` modifier. Both feed the same host
renderer. The host clips lights to expanded glass, clears replaced/hidden/private
sources, and keeps its reduced-transparency fallback. Music derives its light response
from existing artwork colors and spectrum data; pause and reduced motion use static
ambient color.

Library support does not authorize a format for a particular connection. The host must
negotiate content schemas and reject an unsupported document anywhere in an output,
including future timeline entries. It must not remove the light field and silently
reinterpret schema2 as schema1. [Session admission](sessions.md).

## One renderer and preview

`ContentRenderer(document:assets:dispatch:)` validates before constructing views.
`ContentPreview(document:assets:previewDispatcher:)` wraps exactly that renderer;
pass an explicit preview dispatcher to inspect actions, with no runtime attached.
`ContentAssetResolving` returns host-supplied SwiftUI images on the main actor.
The production host dispatcher must create a fresh ActionRequest with its own
request ID, admitted publication/revision, deadline and authorization checks.
A view click itself grants no capability.

Text, buttons and images expose semantic accessible labels. Progress exposes a
localized percentage; clock formatting uses locale conventions. The content renderer exports optional light values to the host; the host owns the
expanded-glass effect and reduced-motion/transparency behavior. The host owns mount/unmount visibility, privacy policy and
any transport dispatch. An ImageRenderer snapshot is not a VoiceOver audit or a
visibility/power measurement. Those require a mounted desktop integration.

Advanced arbitrary SwiftUI scenes are a separate remote process presentation
mode with a visibility lease. This durable-content implementation neither creates
remote scenes nor substitutes an in-process execution path for them.

## Provider seam

`AddonProvider.handle(_:context:) async throws -> ProviderOutput` is Sendable and
not MainActor-isolated. Inputs are versioned AddonEvent values: refresh, scheduled,
action, serviceChanged, serviceRequest and stop. Service events carry subscription
UUID, a Grant token (including connection generation), and bounded ServiceResponse;
contract and operation must match the token. Raw AddonEvent decoding is capped at
128 KiB to accommodate the base64 encoding of a 64 KiB service payload plus grant
metadata. ServiceInvocation retains request UUID, contract, operation, payload and
deadline from Contracts.

AddonContext only injects AddonServiceClient, AddonStorageClient, generation and a
bounded, unique grant snapshot. Stale-generation grants are rejected. Clients use
typed wire request/response values and async storage operations. These are
abstractions for P2, not transport implementations. The broker still authenticates
peers, checks revocation/expiry, grants, storage key/size quotas, service schemas,
response correlation, and current generation for every operation. Codable/Sendable
values alone never authenticate a caller. No SDK target imports CascadeKit or
references its engine, NSApp, host factories or catalog.
