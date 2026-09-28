import hashlib
import json
import pathlib
import subprocess
root = pathlib.Path(__file__).resolve().parent
helper = root / 'tart-layer-unpack'
assert helper.is_file(), 'build tart-layer-unpack first'
subprocess.run([str(root / 'make-fixture'), str(root)], check=True)
expected = (root / 'expected.bin').read_bytes()
digest = hashlib.sha256(expected).hexdigest()
prefix, suffix = b'P' * 8315, b'S' * 8283
target = root / 'synthetic-disk.img'
results = []
def invoke(source, count=len(expected), sha=digest):
    return subprocess.run([str(helper), str(source), str(target), str(len(prefix)), str(count), 'sha256:' + sha], capture_output=True, text=True)
for name in ('nsdata.lz4', 'outputfilter.lz4'):
    target.write_bytes(prefix + b'\xa5' * len(expected) + suffix)
    before = target.stat().st_blocks * 512
    result = invoke(root / name)
    assert result.returncode == 0, result.stderr
    assert target.read_bytes() == prefix + expected + suffix
    assert target.stat().st_blocks * 512 < before // 2, 'zero ranges were not deallocated'
    results.append({'case': name, 'status': 'PASS', 'allocatedBefore': before, 'allocatedAfter': target.stat().st_blocks * 512, 'result': json.loads(result.stdout)})
assert invoke(root / 'nsdata.lz4').returncode == 0
assert target.read_bytes() == prefix + expected + suffix
results.append({'case': 'repeat-existing-range', 'status': 'PASS'})
result = invoke(root / 'nsdata.lz4', sha='0' * 64)
assert result.returncode != 0 and 'hashMismatch' in result.stderr
assert target.read_bytes() == prefix + expected + suffix
results.append({'case': 'wrong-hash-rejected', 'status': 'PASS'})
target.write_bytes(prefix + b'\xa5' * len(expected) + suffix)
original = target.read_bytes()
result = invoke(root / 'nsdata.lz4', count=1000)
assert result.returncode != 0 and 'outputLimit' in result.stderr
assert target.read_bytes() == original
results.append({'case': 'output-limit-no-overwrite', 'status': 'PASS'})
broken = root / 'truncated.lz4'
encoded = (root / 'nsdata.lz4').read_bytes()
broken.write_bytes(encoded[:len(encoded) // 2])
result = invoke(broken)
assert result.returncode != 0
actual = target.read_bytes()
assert actual[:len(prefix)] == prefix and actual[-len(suffix):] == suffix
results.append({'case': 'truncated-rejected-bounds-preserved', 'status': 'PASS'})
result = invoke(root / 'nsdata.lz4', count=len(expected) + len(suffix) + 1)
assert result.returncode != 0 and 'invalidRange' in result.stderr
results.append({'case': 'out-of-file-range-rejected', 'status': 'PASS'})
print(json.dumps({'cases': results, 'allPassed': True}, indent=2))
