# Task 1 native-path qualification

## Verdict

**Blocked. A signed real provider cannot currently use the common `CascadeAddonSDK` service client through `CascadeRuntime` in the shipping app.** The typed SDK client and the runtime broker/service path exist, but the production native transport/bootstrap and app composition that join them do not.

This means Task 1 can add and test contracts, `FileWorkspaceClient`, and host-side authorization logic, but it cannot satisfy the brief's signed-provider/native-path qualification or claim production mounting. An in-process adapter would only reproduce the existing test arrangement and would violate the explicit no-bypass requirement.

## Concrete composition found

- `TransportServiceClient` is the real public `AddonServiceClient` conformer. It requires an injected `AddonServiceMessageChannel` (`CascadeKit/Sources/CascadeAddonSDK/Services/TransportServiceClient.swift:6,24,37`). The channel contract explicitly says it is not a native transport (`CascadeKit/Sources/CascadeAddonSDK/Services/AddonServiceMessageChannel.swift:11-20`).
- `AddonRuntime` requires an injected `AddonRuntimeAdapter`; protocol 1.3/1.4 service support activates only when that object also conforms to `AddonRuntimeServiceAdapter` / `AddonRuntimeServiceSubscriptionAdapter` (`CascadeKit/Sources/CascadeRuntime/AddonRuntime.swift:553-615`). The base protocol itself records that it has no production conformer (`CascadeKit/Sources/CascadeRuntime/AddonRuntimeTransport.swift:106-112`).
- The only concrete complete runtime service adapter in the checkout is test code: `InvocationMessageAdapter` conforms to the subscription, storage, and asset adapter protocols (`CascadeKit/Tests/CascadeRuntimeTests/ServiceInvocationMessageIntegrationTests.swift:1146-1149`). The codebase graph likewise finds this as the sole concrete `AddonRuntimeServiceSubscriptionAdapter` implementor; other runtime-adapter classes are test fixtures.
- The only `AddonServiceMessageChannel` conformers are test channels. The most complete one, `SubscriptionRuntimeChannel`, is private test code (`CascadeKit/Tests/CascadeRuntimeTests/ServiceSubscriptionMessageIntegrationTests.swift:711-725`). The test at lines 631-675 composes it with `TransportServiceClient`, `AddonRuntime`, modeled process exit, and the test adapter. It proves the internal byte/receipt path, not OS transport or a signed provider.
- The app target links only the `CascadeKit` product (`Cascade.xcodeproj/project.pbxproj:118-124`). That product depends on `CascadeContracts` and `CascadePresentation`, not `CascadeRuntime` or `CascadeAddonSDK` (`CascadeKit/Package.swift:93-98`). `CascadeApp` imports `CascadeKit` and constructs no `AddonRuntime` (`Cascade/CascadeApp.swift:7-15,30-58`). `AddonRuntime` is also an internal actor in the separate runtime product (`CascadeKit/Sources/CascadeRuntime/AddonRuntime.swift:10-12`).
- The signed native probes are separate fixtures with their own `ProbeBootstrap` / `ProbeChannel` XPC vocabulary and do not import `CascadeAddonSDK` or `CascadeRuntime` (`Prototypes/AddonPlatform/Provider/ProbeProvider.swift:6-35`). They therefore do not supply the missing common-SDK/runtime adapter.

## Existing qualification evidence

- The SDK/runtime delivery record calls the composed path an injected internal message path and says it is not a delivered native transport/bootstrap (`docs/superpowers/verification/2026-09-18-addon-service-subscriptions-host-sdk.md:3-5`). It leaves launcher, authenticated OS transport, physical process death, native parity, and distribution unqualified (`:37`).
- The service documentation states that a production native transport adapter remains separate and that the modeled adapters/exits do not qualify native death (`docs/addons/services.md:18-21,217,239`).
- The generated addon is source-only: no bootstrap, signing, installation, or runtime admission is provided (`CascadeKit/Sources/CascadeAddonTool/ScaffoldCommand.swift:5-6,43`).
- The managed-death/native admission gate is still an unconditional hold with exit 78 (`scripts/test-addon-managed-death.sh:7-12`).

## Smallest feasible next work

Within the file-shelf scope, implement only the public wire models, `FileWorkspaceClient` over `AddonServiceClient`, and host-side `FileWorkspaceService` authorization/revision behavior, with tests through the existing injected/model adapter seam. Record those results as internal/model qualification and leave production mounting blocked.

Unblocking the native requirement is a separate prerequisite, not a small File Workspace patch. It needs, at minimum:

1. a production authenticated bootstrap/launcher admitted by the existing native gate;
2. a production runtime adapter conforming to the cumulative service protocols;
3. a production `AddonServiceMessageChannel` for the SDK side;
4. app wiring that owns `AddonRuntime` and connects both sides;
5. a signed provider using `CascadeAddonSDK`, with observed authorization, revocation, and physical exit on that exact path.

No code, tests, build, app restart, or native fixture execution was performed for this read-only qualification.

## Feature implementation checkpoint

- Isolated checkout `codex/file-shelf`, baseline snapshot `5f8f45c`; the snapshot contains pre-existing work and is not part of the file-shelf implementation diff.
- Public bounded wire values are implemented in commit `eb18b8e`; seven focused contract tests pass. Root reviewed spec compliance and code quality.
- SDK client and internal canonical service boundary are implemented in commit `f402d8c`. Root reviewed the production code and tests and requested two corrections: preserve stable domain errors and sanitize host error text. Both corrections are covered by regression tests.
- No file acquisition, persistent shelf, UI mounting, or FFmpeg conversion is delivered by this checkpoint. Task 1 production qualification remains blocked; tasks 2–9 are not completed.
- The managed launcher hold remains unchanged. This verification record does not qualify native transport, process exit, or production availability.

## Final checkpoint verification

- Root ran `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test --package-path CascadeKit --filter FileWorkspace` after the final code commit: exit 0, 21 tests passed (7 contracts, 4 client, 10 authority).
- Implementer ran the existing `ServiceBrokerTests`: 22 passed. The full package run reproduced the baseline failure in `controlDragKeepsExpandedContentAliveUntilMouseUp` at `NotchControllerTests.swift:1385`; its focused rerun passed. The full suite is therefore not claimed green.
- Root ran `scripts/build-development.sh` with `CASCADE_DERIVED_DATA=/Users/c4v4h/Library/Developer/Xcode/DerivedData/CascadeFileShelf`: exit 0, SDK boundary checks and codesign verification passed. `/Applications/Cascade.app` points to that build.
- Cascade was quit, relaunched, and verified at PID 68339 with its executable under the same DerivedData directory.
- Weekly account budget at completion: 2% used, 98% remaining. The requested 80% reserve was preserved.

The worktree remains attached on `codex/file-shelf`. The original checkout was not edited during implementation. The native prerequisite is the blocker for activation; it was not replaced with a privileged in-process path.

## Persistenza interna — 26 settembre 2026

Commit `bbe1144`, implementato da GPT-5.6 Sol e revisionato dal root: manifest POSIX atomico con fsync; gestione dell’incertezza del commit senza eliminare copie potenzialmente referenziate; bookmark con descriptor e scope; un solo writer per lifetime host, close esplicito prima della riapertura; copie gestite e ricevute parziali, pin sovrapposti, quote disco/stato/memoria reali. Test indipendente root: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test --package-path CascadeKit --scratch-path /tmp/cascade-task2-build2 --filter 'FileWorkspace|ResourceGovernorTests'`, exit 0, 39 runtime + 4 SDK + 7 contratti = 50 test.

Limiti: input promesso già completato, ricevitore nativo non implementato; nessun montaggio nella app. I consumer delle consegne devono usare il descriptor lease. Identità device/inode/generation conservativa dopo rimontaggio; filesystem senza generation significativa non danno identica protezione dal riuso inode. Dati sconosciuti e cleanup falliti restano preservati e addebitati. Build/riavvio della tranche corrente seguiranno gli altri incrementi indipendenti.

## Componente condiviso — 26 settembre 2026

Commit `b8b3756`, implementato da GPT-5.6 Sol e revisionato dal root. Schema contenuti3 con opt-in esplicito; compatibilità1/2 e glass lights preservata; descrittori azione immutabili, asset dichiarati e rimappati in archivio. Renderer comune con fan4/+N, lista paginata, transizioni finite e Riduci movimento, comandi nativi, input/freccia/risultati distinti e avanzamento reale.

Verifica root: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test --package-path CascadeKit --filter 'FileWorkspace|ProtocolAdmissionTests|GlassLightTests|ContentValidationTests|ActionAuthorizerTests'`, exit0, 48 runtime +17 presentation +21 contracts =86 test. Root ha ispezionato le PNG prodotte da NSHostingView/NSWindow in `/private/tmp/cascade-file-shelf-preview/`; corrette righe oltre il bordo, titoli sovrapposti, gruppi sopra la freccia, anteprime erroneamente attribuite ai risultati e comando Convert ambiguo.

Limiti: prova su stati assestati, non su animazioni del notch produttivo; VoiceOver non navigato manualmente. Schema3 non attivato nella app, nessun widget privilegiato o bootstrap abilitato. La prova nativa rimane requisito dei ticket successivi.
