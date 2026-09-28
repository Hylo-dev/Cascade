import hashlib
import json
import pathlib
import random
import subprocess

root = pathlib.Path(__file__).resolve().parent
helper = root / 'compact-zero-blocks'
assert helper.is_file(), 'build compact-zero-blocks first'
path = root / 'compact-synthetic.img'
block = 65536
payload = bytearray(random.Random(9127).randbytes(128 * block + 91))
for index in range(1, 127, 2):
    payload[index * block:(index + 1) * block] = bytes(block)
expected = bytes(payload)
digest = 'sha256:' + hashlib.sha256(expected).hexdigest()
path.write_bytes(expected)
initial = path.stat()

def run(*args):
    return subprocess.run([str(helper), *map(str, args)], capture_output=True, text=True)

result = run(path, '--stopped')
assert result.returncode == 0, result.stderr
first = json.loads(result.stdout)
assert first['sha256Before'] == first['sha256After'] == digest
assert path.read_bytes() == expected
assert path.stat().st_size == initial.st_size
assert path.stat().st_blocks < initial.st_blocks
result = run(path, '--stopped')
assert result.returncode == 0, result.stderr
second = json.loads(result.stdout)
assert second['allocatedBeforeBytes'] == second['allocatedAfterBytes'] == first['allocatedAfterBytes']
assert path.read_bytes() == expected
assert second['sha256Before'] == second['sha256After'] == digest
assert run(path).returncode != 0
assert 'restrictedPath' in run('/etc/hosts', '--stopped').stderr
alias = root / 'compact-hardlink.img'
alias.hardlink_to(path)
try:
    rejected = run(path, '--stopped')
    assert rejected.returncode != 0 and 'regularUnlinkedFileRequired' in rejected.stderr
finally:
    alias.unlink()
assert path.read_bytes() == expected
print(json.dumps({'allPassed': True, 'first': first, 'second': second,
                  'guards': ['stopped-ack-required', 'outside-lab-rejected', 'hardlink-rejected'],
                  'checks': ['all-bytes-unchanged', 'size-unchanged', 'allocation-reduced', 'second-pass-idempotent']}, indent=2))
