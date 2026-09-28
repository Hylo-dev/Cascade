"""Fetch the pinned lab image with persistent HTTP-range checkpoints; no VM launch."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import hashlib,json,os,re,shutil,signal,subprocess,threading,time,urllib.request
BASE=Path('/private/tmp/cascade-addon-vm')
PIN='a6dc5a325aae43a90244953af0a85091fbe93e8f58583138c5ac96dd707fd700'
PART=BASE/'state/tmp/caac213d4e30fe6f2c8ad4af455d0dc4'
CACHE=BASE/'resumable-blobs'
REPORT=BASE/'resumable-result.json'
FLOOR=3*2**30
cancel=threading.Event();lock=threading.RLock();children=set();start=time.monotonic()
record=dict(started=time.time(),minimumFreeBytes=FLOOR,timeoutSeconds=21600,sourceSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),verified=[],failures=[],nativeGuestStarted=False)

def digest_file(path,offset=0,length=None):
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        stream.seek(offset)
        while length is None or length:
            block=stream.read(min(4*2**20,length) if length is not None else 4*2**20)
            if not block:
                if length: raise RuntimeError('short disk range')
                break
            digest.update(block)
            if length is not None:length-=len(block)
    return digest.hexdigest()

def emit(**event):
    print(json.dumps(dict(elapsedSeconds=round(time.monotonic()-start),freeGiB=round(shutil.disk_usage(BASE).free/2**30,2),**event)),flush=True)

def stop(reason):
    with lock:
        if not cancel.is_set(): record['stopReason']=reason
        cancel.set()
        for child in list(children):
            if child.poll() is None: child.terminate()

def watch():
    while not cancel.wait(.25):
        if shutil.disk_usage(BASE).free<FLOOR:stop('space-floor')
        elif time.monotonic()-start>record['timeoutSeconds']:stop('timeout')
        elif (BASE/'stop-resumable').exists():stop('requested')

def child_run(command,timeout,log=None):
    with lock:
        if cancel.is_set():raise RuntimeError('cancelled before subprocess')
        child=subprocess.Popen(command,stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=log if log is not None else subprocess.PIPE)
        children.add(child)
    try:
        stdout,stderr=child.communicate(timeout=timeout)
        return child.returncode,stdout,stderr
    except BaseException:
        child.kill();child.wait(timeout=5);raise
    finally:
        with lock:children.discard(child)

def fetch(index,layer):
    expected=layer['digest'].split(':',1)[1];size=layer['size'];path=CACHE/(expected+'.partial')
    for attempt in range(200):
        if cancel.is_set():raise RuntimeError('download cancelled')
        current=path.stat().st_size if path.exists() else 0
        if current>size:raise RuntimeError('oversized compressed checkpoint')
        if current==size:
            if digest_file(path)!=expected:raise RuntimeError('compressed digest mismatch at layer '+str(index))
            emit(event='compressed-layer-verified',layer=index,bytes=size)
            return path
        token_url='https://ghcr.io/token?scope=repository:cirruslabs/macos-sonoma-vanilla:pull'
        try:
            with urllib.request.urlopen(token_url,timeout=20) as response:
                token=json.load(response)['token']
            command=['/usr/bin/curl','--silent','--show-error','--location','--fail','--connect-timeout','15','--max-time','180','--continue-at','-','--output',str(path),'--header','Authorization: Bearer '+token,'--write-out','%{http_code}', 'https://ghcr.io/v2/cirruslabs/macos-sonoma-vanilla/blobs/'+layer['digest']]
            with (CACHE/(str(index)+'.curl.log')).open('ab') as log:
                status,output,_=child_run(command,190,log)
            received=path.stat().st_size if path.exists() else 0
            emit(event='range-checkpoint',layer=index,attempt=attempt,status=status,http=output.decode(errors='replace'),bytes=received,total=size)
            if received>size:raise RuntimeError('oversized compressed response')
            if status not in (0,18,28,35,52,55,56):raise RuntimeError('non-retryable curl status '+str(status))
        except (TimeoutError,urllib.error.URLError) as error:
            emit(event='registry-retry',layer=index,error=str(error))
        if cancel.wait(1):raise RuntimeError('cancelled after checkpoint')
    raise RuntimeError('layer retry bound exceeded')

signal.signal(signal.SIGTERM,lambda *_:stop('signal'))
signal.signal(signal.SIGINT,lambda *_:stop('signal'))

# Fail before network or disk mutation unless the previous owned downloader exited.
previous=json.loads((BASE/'download-compact-four-result.json').read_text())
assert previous.get('stopReason')=='requested' and previous['exitCode']==-15
raw=(BASE/'sonoma14.1-manifest.json').read_bytes()
assert hashlib.sha256(raw).hexdigest()==PIN
manifest=json.loads(raw);layers=manifest['layers'];assert len(layers)==34
assert PART.is_dir() and (PART/'disk.img').stat().st_size==50000000000
assert not REPORT.exists() and not (BASE/'state/vms/cascade-addon-small').exists()
for layer in layers:
    assert re.fullmatch('sha256:[0-9a-f]{64}',layer['digest']) and 0<layer['size']<600*2**20
positions={};offset=0
for index,layer in enumerate(layers):
    if layer['mediaType']=='application/vnd.cirruslabs.tart.disk.v2':
        annotation=layer['annotations'];length=int(annotation['org.cirruslabs.tart.uncompressed-size'])
        assert length>0 and re.fullmatch('sha256:[0-9a-f]{64}',annotation['org.cirruslabs.tart.uncompressed-content-digest'])
        positions[index]=(offset,length,annotation['org.cirruslabs.tart.uncompressed-content-digest'].split(':')[1]);offset+=length
assert offset==50000000000 and set(positions)==set(range(1,33))
assert layers[0]['mediaType']=='application/vnd.cirruslabs.tart.config.v1' and layers[33]['mediaType']=='application/vnd.cirruslabs.tart.nvram.v1'
helper=BASE/'layer-helper/tart-layer-unpack';assert helper.is_file()
record['helperSHA256']=digest_file(helper)
CACHE.mkdir(exist_ok=True)
(BASE/'resumable-started.json').write_text(json.dumps(record,indent=2)+'\n')
thread=threading.Thread(target=watch,daemon=True);thread.start()
try:
    needed=[]
    for index,layer in enumerate(layers):
        if cancel.is_set():raise RuntimeError('cancelled during initial verification')
        if index in positions:
            offset,length,expected=positions[index]
            matched=digest_file(PART/'disk.img',offset,length)==expected
        else:
            local=PART/('config.json' if index==0 else 'nvram.bin')
            matched=local.is_file() and local.stat().st_size==layer['size'] and digest_file(local)==layer['digest'].split(':')[1]
        if matched:
            record['verified'].append(dict(layer=index,reused=True));emit(event='existing-layer-verified',layer=index)
        else:needed.append(index)
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures={pool.submit(fetch,index,layers[index]):index for index in needed}
        try:
            for future in as_completed(futures):
                index=futures[future];blob=future.result()
                if cancel.is_set():raise RuntimeError('cancelled before decode')
                if index in positions:
                    offset,length,expected=positions[index]
                    command=[str(helper),str(blob),str(PART/'disk.img'),str(offset),str(length),'sha256:'+expected]
                    status,output,error=child_run(command,180)
                    if status!=0:raise RuntimeError('decode failed '+str(index)+': '+error.decode(errors='replace'))
                    detail=json.loads(output)
                else:
                    shutil.copyfile(blob,PART/('config.json' if index==0 else 'nvram.bin'))
                    detail=dict(kind='metadata',sha256=layers[index]['digest'].split(':')[1])
                record['verified'].append(dict(layer=index,reused=False,detail=detail))
                (BASE/'resumable-checkpoint.json').write_text(json.dumps(record,indent=2)+'\n')
                blob.unlink();emit(event='image-layer-verified',layer=index,verified=len(record['verified']),total=34)
        except BaseException:
            stop('download-or-decode-failure')
            for future in futures:future.cancel()
            raise
    assert not cancel.is_set() and {entry['layer'] for entry in record['verified']}==set(range(34))
    assert (PART/'config.json').stat().st_size==layers[0]['size'] and (PART/'nvram.bin').stat().st_size==layers[33]['size']
    # Verification only: a separate host step will publish after this process exits.
    record['imageVerified']=True;record['vmPath']=str(PART)
except BaseException as error:
    stop('failure');record['error']=repr(error);record['imageVerified']=False
finally:
    cancel.set();thread.join(timeout=2)
    if record.get('stopReason'):record['imageVerified']=False
    record.update(finished=time.time(),elapsedSeconds=round(time.monotonic()-start),freeBytes=shutil.disk_usage(BASE).free)
    REPORT.write_text(json.dumps(record,indent=2)+'\n')
    emit(event='verification-result',imageVerified=record.get('imageVerified'),error=record.get('error'))
raise SystemExit(0 if record.get('imageVerified') and not record.get('stopReason') else 2)
