# C5b: keyed storage, 12 September 2026

The host backend is implemented and approved; C5 as a whole remains open.
`AddonKeyedStorage` keeps distinct values per key and verified identity, separate
from the checkpoint and from the cache. The resizable reservations of the shared governor
maintain the quotas across staging, errors, close and reconciliation too. The public
contract of the host path and the limits are described in [storage](../../addons/storage.md).

## Fix and checks

The initial review required F01: the existence of a created folder does not prove
that its parent was synced. The first error correctly preserved the quota, but a
retry/reopen could skip the sync. The fix separates the two states with bounded
metadata, repairs the parent before success and does not add ancestor syncs to
normal, already confirmed writes. F01 re-review: approved, no required finding open.
The initial files and the first review are preserved separately.

- Behavioral RED:3 tests,42 issues across9 scenarios (root/data/cache, direct retry,
  reopening the same backend and reopening with a new governor).
- Targeted final GREEN:38 tests,34 keyed and4 resize. The successful syncs are real
  filesystem calls; the tests record folder identity, order and exact quotas.
- Final package:474 tests passed, exit0, `--no-parallel`: Runtime243,
  Presentation20, Engine169, Contracts38, tool4. Xcode-beta and scratch already prepared.
  Log `/private/tmp/cascade-c5b-fix1-full-package.log`, SHA-256
  `b8607b28637c9092dea4cef66b4b00a73391741d6e91818efeda667b0ee2204c`.
- The15 scope hashes are unchanged before/after the full verification. Nine
  source/test files changed relative to this increment's baseline.
- The initial verification of471 tests is not reattributed to the fix. The historical
  limitation of the UI test under concurrent execution remains distinct from the serial result.

Covered: limits, isolation, byte-exact Unicode, corrupt/future records, revocation and
cancellation during real admissions, failed cleanup, commit with uncertain durability,
quotas shared with the checkpoint, bounded inventory and close/reopen. These are
filesystem/host tests; they do not qualify power loss, sandbox or the native launcher.

## Delivery

Integrated 13 files (9 sources/tests and 4 documents), preserving the pre-existing changes.
Compared 337 build inputs, identical between the original checkout and the local copy.
Signed build succeeded, exit 0, through `scripts/build-development.sh` from the verified
local copy. The `/Applications/Cascade.app` link points to the build just created
in `CascadeAddonDevelopment`. Relaunch observed: PID 47210 quit without forcing,
new instance PID 51942 stable at the expected path. Logs
`/private/tmp/cascade-c5b-20260912-app-build.log` and
`/private/tmp/cascade-c5b-20260912-restart.json`. No commit or staging.
This delivery completes C5b, not the overall feature.

## Remaining work

Authenticated SDK transport with sessions/permissions and a dedicated frame for the maximum
value, a global barrier before admission at startup, assets and decoders, restoration of
publications and notices without replay. Also remaining: control of the real processes,
connection to the app, our own widgets on the same SDK and final qualification. No
production adapter is enabled by C5b.
