from pathlib import Path
import importlib.util,json,os,select,subprocess,time
b=Path('/Users/admin/CascadeProbe');p=b/'products';m=json.loads((p/'build.json').read_text());old=Path(m['taskObserver']).parent
paths={k:p/Path(m[k]).relative_to(old) for k in ('brokerHost','provider')}
spec=importlib.util.spec_from_file_location('runner',b/'run_vm_suspended_arm64.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
root=subprocess.Popen([str(paths['brokerHost'])],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,bufsize=0,env=dict(os.environ,CASCADE_RECOVERY_PROVIDER_BUNDLE=str(paths['provider'])))
stream=module.Stream(root,'root',[])
def send(c):
 root.stdin.write((c+'\n').encode());root.stdin.flush();print(json.dumps({'sent':c,'observed':time.monotonic()}),flush=True)
def drain(seconds):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  e=stream.read(min(.25,end-time.monotonic()))
  if e is not None:print(json.dumps({'event':e,'observed':time.monotonic()}),flush=True)
try:
 drain(.5);send('broker-info');drain(.5);send('hello')
 for _ in range(5):
  drain(2);send('broker-info');drain(.3)
finally:
 if root.poll() is None:
  send('quit')
  try:root.wait(timeout=3)
  except subprocess.TimeoutExpired:root.terminate();root.wait(timeout=3)
 print(json.dumps({'rootExit':root.returncode,'stderr':root.stderr.read().decode(errors='replace'),'note':'ordinary-startup diagnostic only; host must stop whole VM after log collection'}),flush=True)
