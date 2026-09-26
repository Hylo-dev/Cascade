set -eu
/Users/admin/CascadeProbe/python/bin/python3.12 -I -B - <<'PY'
from pathlib import Path
import json,subprocess
p=Path('/Users/admin/CascadeProbe/products');m=json.loads((p/'build.json').read_text());provider=p/Path(m['provider']).relative_to(Path(m['taskObserver']).parent)
commands=[['/usr/bin/codesign','-dvvvv',str(provider)],['/usr/bin/codesign','-d','-r-',str(provider)]]
for requirement in m['providerRequirement'].split(' and '):commands.append(['/usr/bin/codesign','--verify','--strict','-R','='+requirement,str(provider)])
commands.append(['/usr/bin/codesign','--verify','--strict','--arch','arm64','-R','='+m['providerRequirement'],str(provider)])
for command in commands:
 r=subprocess.run(command,capture_output=True,text=True,timeout=8); print(json.dumps({'command':command,'exitCode':r.returncode,'stdout':r.stdout,'stderr':r.stderr}))
PY
