set -eu
cp '/Volumes/My Shared Files/probe/cleanup-qualified.json' /Users/admin/cleanup-qualified.json
/Users/admin/CascadeProbe/python/bin/python3.12 -I -B - <<'PY'
from pathlib import Path
import json,subprocess
p=Path('/Users/admin/CascadeProbe/products');m=json.loads((p/'build.json').read_text());old=Path(m['taskObserver']).parent
paths={k:p/Path(m[k]).relative_to(old) for k in ('host','container','provider')}
for k in ('host','container'):
 subprocess.run(['/usr/bin/codesign','--verify','--strict',str(paths[k])],check=True)
 subprocess.run(['/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister','-f',str(paths[k])],check=True)
subprocess.run(['/usr/bin/open','-g',str(paths['container'])],check=True)
subprocess.run(['/usr/bin/open','-n',str(paths['host']),'--args','--browse'],check=True)
print(json.dumps({k:str(v) for k,v in paths.items()}))
PY
