# Creating an addon source project

`cascade-addon init` prepares a Swift project built on the public `CascadeAddonSDK` and `CascadeContracts` products. The result is a source project with a provider, a manifest and tests: it is not yet an installable bundle and it does not launch addon processes inside Cascade.

## Generation

Give the path of the SDK package and an identifier chosen by the developer:

```sh
CASCADE_SDK="/path/Cascade/CascadeKit"
ADDON_ID="com.example.mywidget"

swift run --package-path "$CASCADE_SDK" cascade-addon init \
  --name MyWidget \
  --identifier "$ADDON_ID" \
  --destination "$PWD/MyWidget" \
  --sdk-path "$CASCADE_SDK"
```

Replace the example identifier with your own project's. The command does not assign a verified publisher, a signature or a certificate. The destination must be new and its parent folder must already exist: even an empty directory or an existing symbolic link is rejected.

The project explicitly declares its dependency on the given local SDK package. It does not introduce an invented remote repository and does not embed private sources of the notch engine. If the SDK package is moved, update the dependency in `Package.swift`.

## Verification

```sh
swift run --package-path "$CASCADE_SDK" cascade-addon validate "$PWD/MyWidget/Manifest.json"
swift test --package-path "$PWD/MyWidget"
```

Generation does not run these commands automatically. Validation confirms the manifest's syntax and contracts; the build and the tests verify the use of the public APIs. None of the three steps qualifies signature, process identity, installation, authorizations or native transport.

## Generated provider

The provider implements `AddonProvider`. It produces a widget publication for a `refresh` request with a host-assigned identity and keeps an increasing revision in its own instance. It answers `stop` without publishing new content and explicitly rejects the events it does not implement.

The content document is built with the public values of `CascadeContracts`; rendering stays in the host. The generated model does not replace the restoration of the revision and state that a restarted provider needs, nor does it implement an IPC receive loop.

Next steps: [content](content.md), [lifecycle and actions](lifecycle.md), [services and permissions](services.md), [storage](storage.md), [image client](assets.md). Native distribution requires the qualified bootstrap and launcher path planned in the [addon plan](../superpowers/plans/2026-09-10-addon-runtime-completion.md).
