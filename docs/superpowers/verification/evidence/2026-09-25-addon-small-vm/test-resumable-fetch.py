"""Exercise real curl resume against a disposable loopback HTTP server only."""
from pathlib import Path
from unittest.mock import patch
from http.server import HTTPServer,BaseHTTPRequestHandler
import ast,contextlib,hashlib,io,json,subprocess,tempfile,threading,time,urllib.request
source=Path('/private/tmp/cascade-addon-vm/fetch-resumable.py').read_text()
nodes=ast.parse(source).body
functions=ast.Module(body=[x for x in nodes if isinstance(x,ast.FunctionDef) and x.name in ('digest_file','emit','fetch')],type_ignores=[])
payload=bytes(range(256))*4096;digest=hashlib.sha256(payload).hexdigest();requests=[]
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*_):pass
    def do_GET(self):
        header=self.headers.get('Range');requests.append(header)
        if len(requests)==1:
            self.send_response(200);self.send_header('Content-Length',str(len(payload)));self.end_headers();self.wfile.write(payload[:65536]);self.wfile.flush();self.close_connection=True
        elif self.server.ignore_range:
            self.send_response(200);self.send_header('Content-Length',str(len(payload)));self.end_headers();self.wfile.write(payload)
        else:
            offset=int(header.removeprefix('bytes=').removesuffix('-'))
            self.send_response(206);self.send_header('Content-Length',str(len(payload)-offset));self.send_header('Content-Range',f'bytes {offset}-{len(payload)-1}/{len(payload)}');self.end_headers();self.wfile.write(payload[offset:])
server=HTTPServer(('127.0.0.1',0),Handler);server.ignore_range=False
thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
results=[]
try:
    for scenario in ('resume-after-disconnect','range-ignored','bad-digest'):
        requests.clear();server.ignore_range=scenario=='range-ignored'
        with tempfile.TemporaryDirectory(prefix='cascade-fetch-test-',dir='/private/tmp') as tmp:
            root=Path(tmp)
            def child_run(command,timeout,log=None):
                command=list(command);command[-1]=f'http://127.0.0.1:{server.server_port}/blob'
                result=subprocess.run(command,stdin=subprocess.DEVNULL,capture_output=True,timeout=10)
                return result.returncode,result.stdout,result.stderr
            env=dict(Path=Path,hashlib=hashlib,json=json,time=time,shutil=__import__('shutil'),subprocess=subprocess,urllib=__import__('urllib'),BASE=root,CACHE=root,cancel=threading.Event(),start=time.monotonic(),child_run=child_run)
            exec(compile(functions,'fetch-functions','exec'),env)
            if scenario=='bad-digest':(root/(digest+'.partial')).write_bytes(b'x'*len(payload))
            error=None
            with patch('urllib.request.urlopen',lambda *a,**k:io.BytesIO(b'{"token":"loopback-test-token"}')),contextlib.redirect_stdout(io.StringIO()):
                try:result=env['fetch'](1,dict(digest='sha256:'+digest,size=len(payload)))
                except RuntimeError as caught:error=str(caught)
            if scenario=='resume-after-disconnect':
                assert error is None and result.read_bytes()==payload and requests==[None,'bytes=65536-']
            elif scenario=='range-ignored':
                assert 'non-retryable curl status 33' in error and (root/(digest+'.partial')).read_bytes()==payload[:65536]
            else:assert 'compressed digest mismatch' in error and not requests
            results.append(dict(scenario=scenario,passed=True,requests=requests.copy(),error=error))
finally:server.shutdown();server.server_close();thread.join(timeout=2)
record=dict(controllerSHA256=hashlib.sha256(source.encode()).hexdigest(),nativeVMOperations=False,networkScope='127.0.0.1 only',checks=results)
Path('/private/tmp/cascade-addon-vm/resumable-fetch-tests.json').write_text(json.dumps(record,indent=2)+'\n')
print(json.dumps(record))
