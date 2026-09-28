"""Fixed signed discovery probe; no extension activation or launcher admission."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

SOURCE = Path(__file__).resolve().parent
SIGNER = "4A857D842A5406C2D3071776FDE7B27B3098FE63"
HOST = "hylo.Cascade.AddonProbe"


def build():
    base = Path.home()/"Library/Developer/Xcode/DerivedData/CascadeXPCDiscoveryProbe"
    base.mkdir(parents=True, exist_ok=True)
    products = Path(tempfile.mkdtemp(prefix="probe-", dir=base))
    app = products/"DiscoveryProbe.app"
    service = app/"Contents/XPCServices/DiscoveryBroker.xpc"
    environment = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer")
    entitlements = products/"Service.entitlements"
    entitlements.write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True}))
    commands, binaries = [], []
    with (products/"build.log").open("w") as log:
        def command(args):
            commands.append(args)
            subprocess.run(args, env=environment, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=90)
        for bundle, name, identifier, broker in [(service,"DiscoveryBroker",HOST+".DiscoveryBroker",True),
                                                (app,"DiscoveryProbe",HOST,False)]:
            (bundle/"Contents/MacOS").mkdir(parents=True)
            info = dict(CFBundleIdentifier=identifier, CFBundleExecutable=name,
                        CFBundlePackageType="XPC!" if broker else "APPL",
                        CFBundleVersion="1", CFBundleShortVersionString="1.0", LSMinimumSystemVersion="14.0")
            if broker: info["XPCService"] = {"ServiceType":"Application","RunLoopType":"NSRunLoop"}
            else:
                info["LSUIElement"] = True
                (bundle/"Contents/Extensions").mkdir()
                shutil.copyfile(SOURCE.parent/"Host/Probe.appextensionpoint",bundle/"Contents/Extensions/Probe.appextensionpoint")
            plist = bundle/"Contents/Info.plist"
            plist.write_bytes(plistlib.dumps(info))
            binary = bundle/"Contents/MacOS"/name
            command(["xcrun","swiftc","-parse-as-library","-swift-version","5","-O",
                     "-target","arm64-apple-macos14.0",*(["-D","BROKER"] if broker else []),
                     str(SOURCE/"Probe.swift"),"-framework","AppKit","-framework","ExtensionFoundation","-framework","ExtensionKit",
                     "-Xlinker","-sectcreate","-Xlinker","__TEXT","-Xlinker","__info_plist",
                     "-Xlinker",str(plist),"-o",str(binary)])
            command(["codesign","--force","--timestamp=none","--options","runtime","--sign",SIGNER,
                     *(["--entitlements",str(entitlements)] if broker else []),str(bundle)])
            command(["codesign","--verify","--strict","--deep","-R",
                     f'=anchor apple generic and identifier "{identifier}" and certificate leaf = H"{SIGNER}"',str(bundle)])
            command(["codesign","-d","--entitlements","-","--xml",str(bundle)])
            binaries.append(binary)
        command(["sw_vers"]); command(["xcrun","--show-sdk-version"])
    sources = [SOURCE/"Probe.swift", SOURCE/"run_discovery.py", SOURCE.parent/"Host/Probe.appextensionpoint"]
    (products/"build.json").write_text(json.dumps(dict(commands=commands, signer=SIGNER,
        sourceHashes={str(p.relative_to(SOURCE.parent)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
        binaries={str(p.relative_to(products)):hashlib.sha256(p.read_bytes()).hexdigest() for p in binaries}),indent=2)+"\n")
    return products


def run(products, browser=False):
    manifest = json.loads((products/"build.json").read_text())
    for relative, digest in manifest["sourceHashes"].items():
        assert hashlib.sha256((SOURCE.parent/relative).read_bytes()).hexdigest() == digest
    for relative, digest in manifest["binaries"].items():
        assert hashlib.sha256((products/relative).read_bytes()).hexdigest() == digest
    prefix = "browser-" if browser else ""
    with (products/(prefix+"stdout.jsonl")).open("wb") as output, (products/(prefix+"stderr.log")).open("wb") as errors:
        # subprocess.run's timeout cleanup targets only its retained direct child.
        result = subprocess.run([str(products/"DiscoveryProbe.app/Contents/MacOS/DiscoveryProbe"),
                                 *(["--broker-browser"] if browser else [])],
                                stdout=output, stderr=errors, timeout=95 if browser else 15)
    print((products/(prefix+"stdout.jsonl")).read_text(), end="")
    return result.returncode


if __name__ == "__main__":
    if sys.argv[1:] == ["--build-only"]:
        print(build())
    elif len(sys.argv) == 3 and sys.argv[1] in {"--run", "--run-browser"}:
        raise SystemExit(run(Path(sys.argv[2]).resolve(), sys.argv[1] == "--run-browser"))
    else:
        raise SystemExit("usage: run_discovery.py --build-only | --run[-browser] PRODUCTS")
