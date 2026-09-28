# Public ServiceConsumer source example

The approved C12 work and user’s sustained Codex-only continuation authorize an independent source example. [Read-only design](../../../.scratch/codex-addon/20260918-continuation/service-consumer-design.md). No concrete public service implementation was found; an explicit synthetic pair demonstrates the client contract without inventing service availability or modifying StandaloneFocus.

## Accepted design

Create Examples/ServiceConsumer only: SwiftPM library products for a shared example contract, an example service provider and a consumer provider, plus two truthful source manifests, README and public-only tests. Explicit absolute CASCADE_SDK_PATH configuration, Swift6.2/6, macOS14 declaration, direct SDK/Contracts dependencies only. Consumer does not depend on provider implementation. No executable, host registration, hidden local fallback, remote SDK URL, signing or installed-addon claim.

Example-only contract com.example.focus.sessions1.0.0/read, exactly empty request, strict <=256byte response JSON with exactly schemaVersion1 and completedSessions integer0...1000. Fixed synthetic count3, explicitly not real history or a service exported by StandaloneFocus. Consumer REQUIRES >=1.0.0 <2.0.0, provider PROVIDES1.0.0; no source-app requirement/permissions invented. No SemVer/resolver implementation in example.

Consumer accepts exact host assignment/owner and injected civil clock. Select exactly one supplied grant matching owner/service/summary-read scope/currentgeneration/unexpiredfiniteexpiry. Ambiguity rejected; no usable grant yields exactly one scoped requestService and no invocation. No automatic acquisition loop/redispatch/subscription. Grant snapshots contain no provider version/identity/digest and cannot prove canonical authority.

Invoke once with fresh requestID, schema1, explicitcontract/read/emptydata and positive finite deadline=min(now+2seconds,grantExpiry). Validate response identity and strict bounded payload before finite widget output labeled as example data. Outbound service invocation completion belongs to client/transport: consumerrefresh has completionnil. Propagate structured clientfailures, no automaticretry/unknown-success transformation. Busyflag acrossawaits; cancellation andstop/unrelatedevents neveremitlatefakevalidity. Validate sameassignmentbeforeinvoke. Memory-only boundedrevision is explicitly fresh-assignment behavior, not recovery support.

Synthetic provider handles validated serviceRequest andstop; rejectswrongidentity/operation/payload/expiredrequest. Returns correlated servicecompletion with requestID andmatchingresponse, no publications/operations. No sideeffects/storage/processes.

Host responsibilities stay explicit: versionresolution, canonicalgrantlookup/consent/providerbinding, monotonicdeadline/late-response rejection/revocation, grantdelivery andnativeauthenticatedtransport. No C0d orfullSDKparity claim.

## Verification and delivery

Capture directory absence. Tests use only publicSDK/Contracts/example APIs, unavailable storage andscripted/recordingservices; successfixture dispatches actual exampleprovider andvalidates completion publicly. Covermanifestdeclarations (includingincompatibleversionfixture) without pretendingtoresolve, grantselection/ambiguity/zero-invoke,no-grantrequest, exactinvocation/deadline, strictpayload/correlation, errorpropagation/revocation-outcomes, cancellation/busy/stop and finitewidget. Scriptedresults verifyconsumerbehavior only; disabled/cycle/realREQUIRES remainhosttests.

MeaningfulRED/Green evidence withhonestcompile-failurelabels, independentcopyoutsidecheckout, publicdependency/import audit, manifestvalidation, freshindependentreview. No rootSDK/Runtime/app changes, no git/worktrees. Dedicatedsource-examplecaches coordinatedwithroot; root owns finalrecord/restart. Continue other remaining work whenCodexavailable.

## Source increment verified

Independent source build/tests and review PASS. [Evidence and remaining native gaps](../verification/2026-09-18-service-consumer-source.md). Updated-SDK integration and final app delivery belong to the ongoing storage-client increment.
