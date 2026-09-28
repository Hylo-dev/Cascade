from pathlib import Path
import json,os,subprocess,time
b=Path('/Users/admin/CascadeProbe');p=b/'products';m=json.loads((p/'build.json').read_text());old=Path(m['taskObserver']).parent
provider=p/Path(m['provider']).relative_to(old);app=p/'BrokerRecovery.app';out=b/'ls-startup-diagnostic';out.mkdir(exist_ok=False)
fifo=out/'stdin';os.mkfifo(fifo);fd=os.open(fifo,os.O_RDWR|os.O_NONBLOCK);log=out/'stdout';log.touch();offset=0;buffer=''
cmd=['/usr/bin/open','-W','-n',str(app),'--stdin',str(fifo),'--stdout',str(log),'--stderr',str(out/'stderr'),'--env','CASCADE_RECOVERY_PROVIDER_BUNDLE='+str(provider)]
child=subprocess.Popen(cmd,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
def send(c):
 os.write(fd,(c+'\n').encode());print(json.dumps({'sent':c,'observed':time.monotonic()}),flush=True)
def drain(seconds):
 global offset,buffer
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  with log.open() as f:
   f.seek(offset);buffer+=f.read();offset=f.tell()
  while '\n' in buffer:
   line,buffer=buffer.split('\n',1)
   print(json.dumps({'payload':json.loads(line),'observed':time.monotonic()}),flush=True)
  time.sleep(.05)
try:
 drain(2);send('ping');send('broker-info');drain(1);send('hello')
 for _ in range(5):drain(2);send('broker-info');drain(.3)
finally:
 send('quit')
 try:child.wait(timeout=5)
 except subprocess.TimeoutExpired:child.terminate();child.wait(timeout=3)
 drain(.1);os.close(fd)
 print(json.dumps({'openExit':child.returncode,'openStdout':child.stdout.read().decode(errors='replace'),'openStderr':child.stderr.read().decode(errors='replace'),'rootStderr':(out/'stderr').read_text() if (out/'stderr').exists() else None,'note':'ordinary Launch Services startup diagnostic only; host must stop VM after logs'}),flush=True)
