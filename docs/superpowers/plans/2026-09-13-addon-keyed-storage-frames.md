# C6 — dedicated keyed-storage frame contracts and optional protocol1.1

2026-09-13. Implemented, independently reviewed and delivered. The proposal and dispatch history below preserve the approved scope. This is contract/codec work, not authenticated SDK transport, app bootstrap or C0d qualification.

## Approved basis and files

`docs/addons/storage.md:154–174,289–292` already requires exact1…256 UTF-8-byte keys without NUL,0…65,536-byte values, absent distinct from empty, SDK data class only, and a dedicated negotiated frame within512KiB. Generic ServiceInvocation/ServiceResponse payloads remain64KiB. SDK read/write/remove signatures remain unchanged.

Own NEW `CascadeKit/Sources/CascadeContracts/StorageRequest.swift`, `StorageResponse.swift`, `StorageFrameCodec.swift`; modify ONLY `CascadeKit/Sources/CascadeRuntime/Admission/ProtocolNegotiator.swift`; NEW focused `CascadeContractsTests/StorageFrameTests.swift` and `CascadeRuntimeTests/StorageProtocolNegotiationTests.swift`. Existing ProtocolAdmissionTests/ProtocolOfferTests are adjacent verification, with changes only if an assertion explicitly tests opt-in1.1. No changes to AddonRuntime, backend, coordinator, ProtocolOffer fields, ProtocolVersion, AddonFailure, SDK or Package.swift are necessary. Production/test formatting follows CODE_STYLE, with Xcode headers and aligned multiline arguments.

Reuse Foundation JSONEncoder/JSONDecoder, ContractValidation.require, WireKey and exact closed-field validation from AssetHandle/ProtocolOffer. Do not introduce a binary parser, custom JSON syntax scanner, generic message bus, request queue or wrapper service. Read ProtocolAdmissionTests first to preserve default behavior.

## Public value API and exact schema1 wire shape

All values Codable, Equatable, Sendable with throwing construction/validate, immutable fields. `StorageOperation: String` is read/write/remove. `StorageResultKind: String` is value/missing/acknowledged/failure. Enums may live beside their DTO rather than new files.

StorageRequest fields:
- schemaVersion:Int, exactly1 (initializer default1).
- requestID:UUID, required, no constructor default.
- operation:StorageOperation.
- key:String, UTF-8 count1…256, no NUL; never normalize, trim or interpret as a path.
- value:Data?; required nonnull for write, including empty Data; ABSENT for read/remove.

Implement StorageRequest Equatable explicitly: compare schemaVersion, requestID, operation and value normally, but compare key.utf8.elementsEqual(other.key.utf8). Synthesized String equality uses canonical Unicode equivalence and would incorrectly equate distinct byte-addressed storage keys. No normalized or copied key representation is needed. Include composed/decomposed unequal-request assertions with otherwise identical fields.

Exact JSON field sets: read/remove `{schemaVersion,requestID,operation,key}`; write adds `value`. No unknown keys, no explicit null substitutes, no value on nonwrite. Decode schema and operation first, check the exact appropriate key set before decoding key/value. Encode only the exact operation's fields. No owner, connection/grant, pathname, class, batch, archive, migration or deadline field is added. The future authenticated envelope supplies session/deadline/transport authority independently.

StorageResponse fields:
- schemaVersion:Int exactly1; requestID:UUID; operation:StorageOperation.
- result:StorageResultKind.
- value:Data? only with result=value, required nonnull0…65,536 bytes; only read may return value.
- failureCode:AddonFailure.Code? and failureReason:String? only with result=failure, both required nonnull. Reason has the existing1…4,096 UTF-8-byte AddonFailure bound; code is the existing closed enum.

Exact JSON field sets: base `{schemaVersion,requestID,operation,result}`; value adds `value`; failure adds `failureCode,failureReason`. missing permits read only; acknowledged permits write/remove only; failure permits any operation and forbids value. No key echo is necessary. Decode discriminants/check field set before materializing variable scalars. Use flat failure fields so the new frame is closed without changing AddonFailure's existing nested decoder (which currently ignores unknown nested keys). Validate incoming failure reason rather than truncating it. A convenience constructor from an already bounded AddonFailure may call its validate; no broad NSError/Error/userInfo conversion in Contracts.

Suggested initializers retain direct explicit fields (including optional fields defaultnil), rejecting invalid combinations; convenience static constructors are unnecessary. Add `StorageResponse.validate(matching request:StorageRequest) throws`: validate both values, then require identical requestID AND operation. No retained request map or key comparison is created.

This helper proves correlation only. The requester mints one fresh UUID per outstanding operation and the responder echoes it. Zero UUID is still a valid UUID-shaped correlation value; the DTO does not prove randomness, ownership, freshness or uniqueness. Future client/handler must match canonical outstanding request+connection, consume the result once and reject unsolicited/duplicate/stale replies. Matching another request's wire UUID alone never authenticates storage access. No replay/dedup state or implicit retry is part of this slice; outcomeUnknown already exists for later uncertain writes.

Closed-field checks are semantic checks through Foundation keyed containers. They do not claim lexical duplicate-JSON-key rejection (Foundation has already interpreted such syntax); do not add a custom parser or assert a stronger property in tests/docs.

## Codec API and byte proof

In StorageFrameCodec.swift:

```swift
public enum StorageFrameProfile: Sendable { case v1_1 }
public enum StorageFrameCodec {
    public static let maximumEncodedBytes = 196_608 //192KiB, each request or response
    public static let maximumValueBytes = 65_536
    public static let maximumKeyBytes = 256
    public static let maximumFailureReasonBytes = 4_096
    public static func encode(_ request:StorageRequest, profile:StorageFrameProfile?) throws ->Data
    public static func encode(_ response:StorageResponse, profile:StorageFrameProfile?) throws ->Data
    public static func decodeRequest(_ data:Data, profile:StorageFrameProfile?) throws ->StorageRequest
    public static func decodeResponse(_ data:Data, profile:StorageFrameProfile?) throws ->StorageResponse
}
```

Make StorageFrameProfile Equatable as well; it is a caller-supplied capability profile, not Codable authority. Nil means unavailable. Gate profile FIRST and throw AddonFailure.versionConflict without touching untrusted JSON; then guard raw count<=maximumEncodedBytes BEFORE JSONDecoder. Encode validates profile and DTO before encoding and checks returned count; use JSONEncoder with sortedKeys only, default Foundation Data/base64 strategy, no pretty printing. JSONDecoder uses default Data/base64. Raw syntax/type failures may remain DecodingError; semantic field/limit/schema errors use AddonFailure.invalidPayload. Frame decoders read operation/result/failureCode as String and explicitly validate their enum raw values, throwing AddonFailure.invalidPayload for unknown strings rather than inheriting synthesized enum DecodingError. A non-string enum field remains a type DecodingError. Apply this classification to the frame codec/DTO custom decoders; no change to AddonFailure or unrelated enum decoding is required. No fake resourceDenied from value-layer admission.

192KiB is a conservative bound fitting maximum legal output even if Foundation escapes every slash:
- Base64 for65,536 bytes: `4*ceil(65,536/3)=87,384` ASCII bytes; allowing two JSON bytes for every base64 character gives174,768 (only slash actually needs this allowance).
- Worst key escaping:6*256=1,536 bytes. This covers control characters encoded as `\uXXXX`, quotes/backslashes, and Unicode relative to original UTF-8 bytes. NUL remains prohibited but other valid controls are allowed by the existing key contract.
- Reserve512 bytes for all fixed field names, separators, quotes, UUID, enum values and schema1 literal. Maximum request bound174,768+1,536+512=176,816<196,608.
- Maximum value response has no key and also fits. Failure response has no value and is bounded by6*4,096+512=25,088. Mutually exclusive outcomes never add both maxima.

No new lower key/value/error semantic cap is introduced.192KiB stays below512KiB and leaves outer-envelope space; final transport must still check TOTAL envelope bytes, not assume any arbitrary wrapper fits. A peer may choose more verbose whitespace/Unicode escapes; equivalent semantic values represented above192KiB are rejected. The guarantee is every legal DTO can be encoded within the bound, not every possible verbose JSON spelling will be accepted. No base64-in-ServiceInvocation workaround.

Direct Codable decoding remains available like existing Contracts; callers consuming untrusted raw frames must use codec entry points for raw bound/profile gate. `validate()` alone cannot supply those raw/capability checks. This documentation prevents synthesized Codable convenience from being mistaken for a transport admission surface.

## Optional version support: preserve every default1.0 caller

Current ProtocolOffer schema1 already carries major/minimumMinor/maximumMinor and rejects additional fields. ProtocolVersion has major/minimumMinor. Reuse them unchanged.

Extend ProtocolNegotiator.negotiate with a final `supportsKeyedStorageFrames: Bool = false`. This is an explicit host IMPLEMENTATION policy, not an untrusted offer flag. Supported host minor ceiling is0 when false,1 when true; host floor remains0. Validate existing offer/manifest/content-schema policy first; require major1 on both. Compute `lower=max(offer.minimumMinor,manifestProtocol.minimumMinor)` and `upper=min(offer.maximumMinor,hostCeiling)`. Reject versionConflict if lower>upper, otherwise select upper. No arithmetic wrap or unbounded search. Retain sorted content-schema intersection and its current1/2 ceiling.

Change fileprivate NegotiatedProtocol initializer to receive selected minor. Add computed `public var storageFrameProfile: StorageFrameProfile?` returning.v1_1 only for negotiated minor1; minor0 returnsnil. Keep NegotiatedProtocol immutable/nondecodable/fileprivate construction. The profile itself is not proof of handshake authority; the later runtime handler must use its canonical negotiated result, not a profile named by provider input.

Defaults preserve current Runtime/PublicationStore/Broker call sites at1.0 even when a peer advertises0…65,535. Do NOT change runtime offers, make it automatically select1.1, or claim installed storage dispatch. Pure negotiator callers/tests explicitly opt into1.1; operational enablement is postponed until the handler is implemented. Protocol1.1 adds this bounded frame vocabulary without changing1.0 messages. Provider requiring minimum1 still fails on default host; minimum0/max0 falls back0 even on opted-in host. Manifest minimum2 always fails because neither implemented profile meets it. Existing content-schema behavior is independent.

## Caller quota/ownership boundary

No governor, fake admission token, resource reservation or retained operation is added to Contracts. Codec calls are synchronous bounded transformations; Data/String/DTO results are owned by the caller. The future transport must preadmit raw frame retention BEFORE receiving/staging it, then controlled decoding scratch and decoded value/metadata BEFORE invoking the codec, and keep output reservations until actual handoff/release. Encode input and returned Data can coexist; neither is free because COW could share storage.

Exact semantic maxima this slice exposes are192KiB encoded frame,64KiB value,256-byte key or4KiB failure text plus fixed scalar metadata. At a decoding boundary, incoming Data and one result coexist; at encoding, one input DTO and encoded Data coexist. These are bounds for application values, not a claim that Foundation parser internals consume exactly their sum. Deep/oversized malformed JSON is capped by the raw192KiB ingress limit, but Foundation's parser workspace/RSS is not qualified by these tests. The authenticated-handler preflight must explicitly select/admit its bounded decode workspace using the existing governor and must not treat these value maxima as a proved framework heap formula. No outstanding table, queue or generic lifetime abstraction belongs here.

## Meaningful compiling RED matrix and freeze

1. Real JSONEncoder round trips all four successful operation/outcome combinations and failure for each operation; read missing != read present empty; wrong-ID and wrong-operation correlation rejected.
2. A65,536-byte all0xFF write (base64 slash-heavy) plus a256-byte allowed-control key encodes under192KiB and decodes byte-exact; do not rely only on ASCII sample data. Exercise256-byte composed/decomposed or multibyte keys, exact bytes, dots/slashes allowed, zero/257-byte/NUL rejected;65,537-byte value rejected.
3. Parameterized invalid field combinations, null versus absent, missing required fields, extra root fields, schema0/future, unknown operation/result/code, empty and4,097-byte failure reasons. Include value poison on a read request with an illegal value key to demonstrate field-shape rejection before decoding the value.
4. Oversize raw input with poison JSON must raise AddonFailure.invalidPayload before DecodingError; unsupported/nil profile must raise versionConflict even for poison/oversize input, proving gate order. Inputs under raw bound with syntax errors remain errors; no swallowed failures.
5. Full failure4,096-byte worst-escaping reason encodes within frame maximum. No truncation on decode. Case outcomeUnknown round-trip stays distinct from success; no retry semantics are invented.
6. Default existing1.0 behavior and content-schema intersection unchanged; opt-in1.1 picks highest common; opted-in host/old0 peer selects0; min1 works only opt-in; min2/future-only and major mismatch fail; upper/lower interval boundaries; arbitrary future offered alongside common version does not become supported. Selected0 profile cannot encode/decode a storage frame, selected1 can.
7. Existing ServiceInvocation/ServiceResponse65,536-byte cap remains enforced. Full-value dedicated frame succeeds without editing generic service limits or SDK signatures.

Tests first; observe actual compiling behavioral RED, then implementation/GREEN against the focused new tests plus adjacent contract/protocol suites. No native process fixture, app changes or storage I/O required. Freeze exact preimages/diff/hashes/API/byte-bound evidence for independent review. Full app delivery remains root-owned after review. No new user architecture choice or unresolved design contradiction was found for this scope.


Independent preflight refinements incorporated: explicit UTF-8-byte StorageRequest equality; known enum-string validation with invalidPayload for unknown semantic strings and DecodingError for wrong JSON types. The 192KiB proof and optional/default1.0 compatibility direction were independently confirmed; source implementation remains undispatched.


Status: independent preflight approved with byte-exact key equality and explicit enum-error classification incorporated. Implementation remains gated on C5 full delivery and remaining weekly budget; no C6 code dispatched. Exact review: `/private/tmp/cascade-keyed-storage-frames-preflight-review.md`.


Dispatch ledger: C5 fully delivered with 710 tests / 71 suites, 383 frozen inputs, signed build/link and verified PID 2818. Root dispatched this exact C6 scope at 47% weekly use to the sole implementation worker, with the existing scratch/cache. Implementation review and full delivery remain pending.


Delivery ledger: independent implementation review approved all six frozen files. Focused verification passed 51 tests in six suites, including 13 new tests; full serial package passed 723 tests in 73 suites. All 388 build/test inputs and 40 accumulated approved source/test hashes match. Signed build, Applications link update and normal restart PID 2818 → 4658 verified. Weekly use: 48%. See [delivery evidence](../verification/2026-09-13-addon-keyed-storage-frames.md).
