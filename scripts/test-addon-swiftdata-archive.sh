#!/bin/zsh
#
# test-addon-swiftdata-archive.sh
# Cascade
#
set -euo pipefail
if [[ $# -gt 0 ]]; then
    if [[ $# -eq 1 && "$1" == --help ]]; then
        print 'Usage: scripts/test-addon-swiftdata-archive.sh'
        print 'Runs fixed SwiftData archive cases in fresh /private/tmp storage; retains JSON and logs.'
        exit 0
    fi
    print -u2 'Only --help or no arguments are supported.'
    exit 2
fi
source_dir=${0:A:h:h}/Prototypes/AddonPlatform/SwiftDataArchive
products=$(mktemp -d /private/tmp/cascade-swiftdata-archive-XXXXXX)
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}
export CLANG_MODULE_CACHE_PATH=${CLANG_MODULE_CACHE_PATH:-/private/tmp/cascade-plugin-module-cache}
export SWIFTPM_MODULECACHE_OVERRIDE=$CLANG_MODULE_CACHE_PATH
print -u2 "Probe artifacts: $products"
trap 'result=$?; if [[ ! -f "$products/report.json" ]]; then print "{\"schema\":\"swiftdata-archive-probe-v1\",\"complete\":false,\"exitCode\":$result}" > "$products/report.json"; fi' EXIT
sw_vers > "$products/os.txt"
uname -a >> "$products/os.txt"
xcrun --show-sdk-version > "$products/sdk.txt"
xcrun swiftc --version > "$products/compiler.txt" 2>&1
architecture=$(uname -m)
if [[ "$architecture" != arm64 && "$architecture" != x86_64 ]]; then
    print -u2 'Unsupported native architecture.'
    exit 2
fi
xcrun swiftc -sdk "$(xcrun --show-sdk-path)" \
    -module-cache-path "$CLANG_MODULE_CACHE_PATH" -parse-as-library \
    -swift-version 6 -O -target "$architecture-apple-macos14.0" \
    "$source_dir/Probe.swift" -o "$products/Probe" > "$products/compile.log" 2>&1
python3 - "$products" <<'PY'
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import stat
import subprocess
import sys
import time

products = Path(sys.argv[1])
report = {
    'schema': 'swiftdata-archive-probe-v1',
    'complete': False,
    'artifacts': str(products),
    'deploymentFloor': 'macOS 14.0',
    'macOS14RuntimeQualified': False,
    'os': (products / 'os.txt').read_text().strip(),
    'sdk': (products / 'sdk.txt').read_text().strip(),
    'compiler': (products / 'compiler.txt').read_text().strip(),
    'executableSHA256': hashlib.sha256((products / 'Probe').read_bytes()).hexdigest(),
    'cases': [],
}


def inventory(root):
    entries = sorted(root.iterdir())
    allowed = {'archive.store', 'archive.store-wal', 'archive.store-shm'}
    if len(entries) > 3 or any(path.name not in allowed for path in entries):
        raise RuntimeError('unexpected managed file')
    rows = []
    for path in entries:
        information = path.lstat()
        if not stat.S_ISREG(information.st_mode) or information.st_uid != os.getuid():
            raise RuntimeError('unsafe managed file')
        if stat.S_IMODE(information.st_mode) != 0o600 or information.st_nlink != 1:
            raise RuntimeError('unsafe managed permissions or links')
        rows.append({'name': path.name, 'bytes': information.st_size, 'permissions': '0600'})
    return rows


def run_case(root, mode, ordinal):
    prefix = products / f'{ordinal:02d}-{root.name}-{mode}'
    started = time.monotonic()
    with prefix.with_suffix('.json').open('wb') as output, prefix.with_suffix('.log').open('wb') as error:
        completed = subprocess.run(
            [str(products / 'Probe'), mode, str(root)],
            stdout=output, stderr=error, timeout=90 if mode == 'repeatUpdates' else 30,
        )
    elapsed = (time.monotonic() - started) * 1000
    if completed.returncode:
        raise RuntimeError(f'{mode} failed with exit {completed.returncode}; see {prefix}.log')
    observation = json.loads(prefix.with_suffix('.json').read_text())
    if observation['mode'] != mode or not observation['openedOffMainThread'] or not observation['operatedOffMainThread']:
        raise RuntimeError('missing off-main correctness observation')
    footprint = observation['processFootprint']
    if footprint['currentBytes'] <= 0 or footprint['lifetimePeakBytes'] < footprint['currentBytes']:
        raise RuntimeError('invalid process footprint observation')
    observation.update(
        fixture=root.name, processWallTimeMilliseconds=elapsed,
        filesAfterProcessExit=inventory(root), exitCode=completed.returncode,
    )
    report['cases'].append(observation)


try:
    consistency = products / 'consistency'
    retention = products / 'retention'
    for root in [consistency, retention]:
        root.mkdir(mode=0o700)
        descriptor = os.open(root / 'archive.store', os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        os.close(descriptor)
    modes = [
        (consistency, 'initialize'), (consistency, 'readInitial'),
        (consistency, 'rollback'), (consistency, 'readInitial'),
        (consistency, 'replace'), (consistency, 'readReplacement'),
        (consistency, 'unsaved'), (consistency, 'readReplacement'),
        (retention, 'initialize'), (retention, 'repeatUpdates'), (retention, 'readRepeated'),
    ]
    for ordinal, (root, mode) in enumerate(modes, start=1):
        run_case(root, mode, ordinal)
    # Read-only inspection records framework implementation details as observations.
    # Correctness does not depend on Apple's private SQL table names remaining stable.
    with sqlite3.connect(f'file:{retention / "archive.store"}?mode=ro', uri=True) as connection:
        tables = {row[0] for row in connection.execute('SELECT name FROM sqlite_master WHERE type="table"')}
        report['historyRows'] = {
            name: connection.execute(f'SELECT count(*) FROM "{name}"').fetchone()[0]
            for name in ['ATRANSACTION', 'ACHANGE'] if name in tables
        }
        report['archiveColumns'] = list(connection.execute('PRAGMA table_info(ZARCHIVERECORD)'))
    report.update(complete=True, result='passed', exitCode=0)
except Exception as error:
    report.update(result='failed', error=str(error), exitCode=1)
finally:
    encoded = json.dumps(report, sort_keys=True, separators=(',', ':'))
    (products / 'report.json').write_text(encoded + '\n')
    print(encoded)
if not report['complete']:
    raise SystemExit(1)
PY
