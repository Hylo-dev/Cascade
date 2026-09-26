set -eu
/Users/admin/CascadeProbe/python/bin/python3.12 -I -B - <<'PY'
from pathlib import Path
import json,os,subprocess
p=Path('/Users/admin/CascadeProbe/products');m=json.loads((p/'build.json').read_text());old=Path(m['taskObserver']).parent
host=p/Path(m['host']).relative_to(old);provider=p/Path(m['provider']).relative_to(old)
cmd=[str(host/'Contents/MacOS/ProbeHost'),'standalone-echo']
r=subprocess.run(cmd,capture_output=True,text=True,timeout=8,env=dict(os.environ,CASCADE_RECOVERY_PROVIDER_BUNDLE=str(provider)))
print(json.dumps({'command':cmd,'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr,'scope':'direct app-to-extension compatibility control; no managed-death claim'}))
PY
