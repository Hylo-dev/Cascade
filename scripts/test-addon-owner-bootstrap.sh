#!/bin/zsh
#
# test-addon-owner-bootstrap.sh
# Cascade
#
set -euo pipefail
source_dir=${0:A:h:h}/Prototypes/AddonPlatform/Tracing
products=$(mktemp -d /private/tmp/cascade-owner-bootstrap-XXXXXX)
identity=4A857D842A5406C2D3071776FDE7B27B3098FE63
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
exec > >(tee "$products/build-run.log") 2>&1
print "Products: $products"
trap 'result=$?; print "Script exit: $result"; if [[ ! -f "$products/owner-report.json" ]]; then print "{\"schema\":\"owner-bootstrap-observation-v1\",\"result\":\"unknown\",\"complete\":false,\"nativeLauncherAdmitted\":false,\"productionTemplateVerifierQualified\":false,\"managedDeathCharacterizationPerformed\":false,\"allVMProtectionsPreserved\":\"unknown\",\"cases\":[],\"setupExit\":$result}" > "$products/owner-report.json"; fi' EXIT
set -x
sw_vers > "$products/os.txt"
uname -a >> "$products/os.txt"
xcrun --show-sdk-path > "$products/sdk.txt"
xcrun --show-sdk-version >> "$products/sdk.txt"
xcrun clang --version > "$products/compiler.txt"
python3 -c 'import sys; print(sys.executable)' > "$products/observer.txt"
codesign -dvvv "$(python3 -c 'import sys; print(sys.executable)')" >> "$products/observer.txt" 2>&1 || true
python3 - "$products" "$source_dir" <<'PY'
import json
import os
from pathlib import Path
import plistlib
import sys
import uuid
products, source = map(Path, sys.argv[1:])
run_id = uuid.uuid4().hex
prefix = 'hylo.Cascade.OwnerFixture.' + run_id
user_home = str(Path.home())
if not user_home.startswith('/Users/') or any(ord(c) < 32 or ord(c) > 126 or c in '\\"' for c in user_home):
    raise ValueError('unsupported lossless fixed user home')
if len((user_home + '/Library/Application Support/CascadeOwner-' + run_id + '/control').encode()) >= 512:
    raise ValueError('foreign control path cap')
manifest = dict(schema='owner-bootstrap-build-v1', prefix=prefix, runID=run_id, userHome=user_home, products={})
lines = ['// Generated fixed fixture identity table; no provider-controlled entries.',
         '#define OWNER_RUN_ID ' + json.dumps(run_id), '#define OWNER_USER_HOME ' + json.dumps(user_home)]
for key in ['Supervisor', 'A.Stub', 'A.Worker', 'B.Stub', 'B.Worker']:
    name = 'Owner' + key.replace('.', '')
    identifier = prefix + '.' + key
    container = Path(user_home) / 'Library/Containers' / identifier
    if os.path.lexists(container):
        raise ValueError('fresh identity collision')
    macro = key.upper().replace('.', '_')
    lines += ['#define OWNER_' + macro + '_ID ' + json.dumps(identifier),
              '#define OWNER_' + macro + '_PATH ' + json.dumps(str(products / name))]
    info = plistlib.loads((source / 'Info.plist').read_bytes())
    info.update(CFBundleIdentifier=identifier, CFBundleExecutable=name)
    (products / (key + '.plist')).write_bytes(plistlib.dumps(info))
    manifest['products'][key] = dict(path=str(products / name), identity=identifier)
(products / 'OwnerFixtureConfig.h').write_text('\n'.join(lines) + '\n')
(products / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
for key in Supervisor A.Stub A.Worker B.Stub B.Worker; do
    role=${key##*.}
    owner=${key%%.*}
    [[ "$key" == Supervisor ]] && owner=""
    executable="$products/Owner${key//./}"
    identifier=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["products"][sys.argv[2]]["identity"])' "$products/manifest.json" "$key")
    xcrun clang -Wall -Wextra -Werror -O2 -mmacosx-version-min=14.0 \
        -DOWNER_FIXTURE=1 -DOWNER_COMPILED_OWNER=\"$owner\" -DPROBE_ROLE=\"$role\" -DSIGNER_HASH=\"$identity\" \
        -I "$products" -Wl,-sectcreate,__TEXT,__info_plist,"$products/$key.plist" \
        "$source_dir/TraceProbe.c" "$source_dir/OwnerStorage.m" \
        -framework Security -framework CoreFoundation -framework Foundation -o "$executable"
    if [[ "$role" == Supervisor ]]; then
        codesign --force --timestamp=none --options runtime --sign "$identity" --identifier "$identifier" "$executable"
    else
        entitlement="$source_dir/Worker.entitlements"
        [[ "$role" == Worker ]] && entitlement="$source_dir/InheritedWorker.entitlements"
        codesign --force --timestamp=none --options runtime --sign "$identity" --entitlements "$entitlement" --identifier "$identifier" "$executable"
    fi
    codesign --verify --strict --all-architectures -R "=anchor apple generic and identifier \"$identifier\" and certificate leaf = H\"$identity\"" "$executable"
    codesign -dvvv --requirements - "$executable" > "$products/$key-requirements.txt" 2> "$products/$key-signature.txt"
    codesign -d --entitlements - --xml "$executable" > "$products/$key-entitlements.plist" 2> "$products/$key-entitlement-diagnostics.txt"
    codesign -d --extract-certificates="$products/$key-certificate-" "$executable"
    xcrun otool -L "$executable" > "$products/$key-dependencies.txt"
    xcrun otool -l "$executable" > "$products/$key-load-commands.txt"
    shasum -a 256 "$executable" >> "$products/hashes.txt"
done
python3 - "$products" "$source_dir" "$identity" <<'PY'
import hashlib
import json
from pathlib import Path
import plistlib
import re
import struct
import sys
products, source = map(Path, sys.argv[1:3])
sys.path.insert(0, str(source))
from owner_run import exact_profile, manifest_valid
manifest = json.loads((products / 'manifest.json').read_text())
for key, item in manifest['products'].items():
    content = Path(item['path']).read_bytes()
    # This bounded read locates signed Info in the current single-slice Mach-O.
    # It is not a template equivalence, distribution or canonicalization verifier.
    if len(content) < 32 or struct.unpack_from('<I', content)[0] != 0xfeedfacf:
        raise ValueError('unsupported fixture Mach-O')
    commands = struct.unpack_from('<I', content, 16)[0]
    if commands > 128:
        raise ValueError('load command bound')
    offset, embedded = 32, []
    for _ in range(commands):
        command, length = struct.unpack_from('<II', content, offset)
        if length < 8 or offset + length > len(content):
            raise ValueError('load command bounds')
        if command == 0x19:
            sections = struct.unpack_from('<I', content, offset + 64)[0]
            if sections > 32 or 72 + sections * 80 > length:
                raise ValueError('section bounds')
            for index in range(sections):
                section = offset + 72 + index * 80
                name, segment = struct.unpack_from('<16s16s', content, section)
                if name.rstrip(b'\0') == b'__info_plist' and segment.rstrip(b'\0') == b'__TEXT':
                    size, location = struct.unpack_from('<QI', content, section + 40)
                    if size > 8192 or location + size > len(content):
                        raise ValueError('Info bounds')
                    embedded.append(content[location:location + size])
        offset += length
    if len(embedded) != 1 or plistlib.loads(embedded[0]) != plistlib.loads((products / (key + '.plist')).read_bytes()):
        raise ValueError('signed Info mismatch')
    (products / (key + '-signed-Info.plist')).write_bytes(embedded[0])
    details = (products / (key + '-signature.txt')).read_text()
    def field(pattern):
        match = re.search(pattern, details, re.M)
        if not match:
            raise ValueError('missing signature field: ' + pattern)
        return match.group(1)
    if field(r'^Identifier=(.+)$') != item['identity']:
        raise ValueError('signing identifier mismatch')
    flags = int(field(r'flags=(0x[0-9a-f]+)'), 16)
    version = [int(part) for part in field(r'^Runtime Version=([0-9.]+)$').split('.')]
    version += [0] * (3 - len(version))
    entitlements = (products / (key + '-entitlements.plist')).read_bytes()
    entitlements = plistlib.loads(entitlements) if entitlements.strip() else {}
    if entitlements != exact_profile(key) or any(type(value) is not bool or value is not True for value in entitlements.values()):
        raise ValueError('exact entitlement profile mismatch')
    leaf = products / (key + '-certificate-0')
    if hashlib.sha1(leaf.read_bytes()).hexdigest().upper() != sys.argv[3]:
        raise ValueError('leaf signer mismatch')
    dependencies = (products / (key + '-dependencies.txt')).read_text().splitlines()[1:]
    for dependency in dependencies:
        path = dependency.strip().split(' (')[0]
        if path not in ['/usr/lib/libSystem.B.dylib', '/usr/lib/libobjc.A.dylib',
            '/System/Library/Frameworks/Security.framework/Versions/A/Security',
            '/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation',
            '/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation']:
            raise ValueError('unexpected fixture dependency ' + path)
    if 'LC_RPATH' in (products / (key + '-load-commands.txt')).read_text():
        raise ValueError('unexpected fixture rpath')
    item.update(infoIdentifier=plistlib.loads(embedded[0])['CFBundleIdentifier'], hash=hashlib.sha256(content).hexdigest(),
                cdhash=field(r'^CDHash=([0-9a-f]+)$'), team=field(r'^TeamIdentifier=(.+)$'), flags=flags,
                runtime=(version[0] << 16) | (version[1] << 8) | version[2],
                entitlements=entitlements, strictVerified=True, signerLeafSHA1=sys.argv[3],
                dependencies=dependencies)
manifest['team'] = manifest['products']['Supervisor']['team']
if not manifest_valid(manifest, products):
    raise ValueError('static fixture manifest rejected')
(products / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
PY
python3 "$source_dir/owner_run.py" "$products"
