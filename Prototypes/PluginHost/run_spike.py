"""Builds and runs the PluginHost spikes S1 and S2. Never linked into Cascade.

    run_spike.py --build            prints the products folder
    run_spike.py --s1 PRODUCTS      kill a hung service through its recorded incarnation
    run_spike.py --s2 PRODUCTS      TCC attribution; the user answers the system prompts

The host is launched through Launch Services (`open`), so it is its own responsible
process. Launched from a shell, TCC would attribute its requests to that shell's app.
"""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import time

SOURCE = Path(__file__).resolve().parent
SIGNER = "2016E550D39ABB541604467993BD257C4EBAF6E7"  # Apple Development, team 8KZQJ4JUGS
TEAM = "8KZQJ4JUGS"
ENVIRONMENT = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer")
VARIANTS = {
    # A: the service has no Apple Events entitlement; B: it has one. Distinct bundle
    # identifiers give each variant its own fresh TCC state.
    "A": {"host": "hylo.Cascade.PluginHostSpikeA", "serviceAppleEvents": False},
    "B": {"host": "hylo.Cascade.PluginHostSpikeB", "serviceAppleEvents": True},
}


def build():
    base = Path.home() / "Library/Developer/Xcode/DerivedData/CascadePluginHostSpike"
    products = base / time.strftime("%Y%m%d-%H%M%S")
    products.mkdir(parents=True)
    log = (products / "build.log").open("w")

    def command(arguments):
        log.write("$ " + " ".join(arguments) + "\n")
        log.flush()
        subprocess.run(arguments, env=ENVIRONMENT, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=300)

    shared = [str(SOURCE / "Shared/SpikeService.swift"), str(SOURCE / "Shared/Automation.swift")]
    for name, variant in VARIANTS.items():
        host = products / f"PluginHostSpike{name}.app"
        service = host / "Contents/XPCServices/PluginHostService.xpc"
        targets = [
            (service, variant["host"] + ".Service", "PluginHostService", str(SOURCE / "Service/main.swift"), {
                "CFBundlePackageType": "XPC!",
                "XPCService": {"ServiceType": "Application"},
            }, {"com.apple.security.automation.apple-events": True} if variant["serviceAppleEvents"] else {}),
            (host, variant["host"], "PluginHostSpike", str(SOURCE / "Host/main.swift"), {
                "CFBundlePackageType": "APPL",
                "CFBundleName": f"PluginHost Spike {name}",
                "LSUIElement": True,
                "NSAppleEventsUsageDescription": "The PluginHost spike checks who Automation is attributed to.",
                "NSBluetoothAlwaysUsageDescription": "The PluginHost spike checks who Bluetooth is attributed to.",
            }, {"com.apple.security.automation.apple-events": True}),
        ]
        for bundle, identifier, executable, main, extra, entitlements in targets:
            (bundle / "Contents/MacOS").mkdir(parents=True)
            info = dict(CFBundleIdentifier=identifier, CFBundleExecutable=executable, CFBundleVersion="1",
                        CFBundleShortVersionString="1.0", LSMinimumSystemVersion="15.0", **extra)
            (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            entitlement_file = products / f"{name}-{executable}.entitlements"
            entitlement_file.write_bytes(plistlib.dumps(entitlements))
            command(["xcrun", "swiftc", "-O", "-swift-version", "5", "-target", "arm64-apple-macos15.0",
                     *shared, main, "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                     "-Xlinker", str(bundle / "Contents/Info.plist"), "-o", str(bundle / "Contents/MacOS" / executable)])
        # The service is signed first: the host's signature seals the nested bundle.
        for bundle, identifier, executable, _, _, _ in targets:
            command(["codesign", "--force", "--timestamp=none", "--options", "runtime", "--sign", SIGNER,
                     "--entitlements", str(products / f"{name}-{executable}.entitlements"), str(bundle)])
            command(["codesign", "--verify", "--strict", "--deep", "-R",
                     f'=anchor apple generic and identifier "{identifier}" and certificate leaf[subject.OU] = "{TEAM}"',
                     str(bundle)])
            command(["codesign", "-d", "--entitlements", "-", "--xml", str(bundle)])
    command(["sw_vers"])
    command(["xcrun", "swiftc", "--version"])
    (products / "build.json").write_text(json.dumps({
        "signer": SIGNER,
        "sources": {str(p.relative_to(SOURCE)): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in sorted(SOURCE.rglob("*.swift"))},
    }, indent=2) + "\n")
    return products


def launch(products, variant, commands, label, timeout):
    """Runs the host through Launch Services and returns its JSON lines."""
    app = products / f"PluginHostSpike{variant}.app"
    output = products / f"{label}.jsonl"
    errors = products / f"{label}.stderr"
    output.write_text("")
    errors.write_text("")
    subprocess.run(["open", "-n", "-W", "--stdout", str(output), "--stderr", str(errors), str(app),
                    "--args", *commands], check=True, timeout=timeout)
    return [json.loads(line) for line in output.read_text().splitlines() if line.strip()]


def s1(products):
    commands = ["hello", "hang", "kill", "kill-stale", "hello",
                "hang", "kill", "hello",
                "hang", "kill", "hello",
                "foreign", "exit", "kill-stale"]
    events = launch(products, "A", commands, "s1", timeout=120)
    for event in events:
        print(json.dumps(event, sort_keys=True))
    return events


def s2(products):
    plans = {
        "A": ["host-automation", "com.apple.finder", "0",
              "automation", "com.apple.finder", "0",
              "automation", "com.apple.finder", "1",
              "host-automation", "com.apple.finder", "0",
              "host-bluetooth",
              "bluetooth", "0",
              "bluetooth", "1",
              "host-bluetooth",
              "bluetooth", "0"],
        "B": ["host-automation", "com.apple.finder", "0",
              "automation", "com.apple.finder", "0",
              "automation", "com.apple.finder", "1",
              "host-automation", "com.apple.finder", "0",
              "automation", "com.apple.finder", "0"],
    }
    results = {}
    for variant, commands in plans.items():
        results[variant] = launch(products, variant, commands, f"s2-{variant}", timeout=900)
        for event in results[variant]:
            print(variant, json.dumps(event, sort_keys=True), flush=True)
    return results


def custom(products, commands):
    events = launch(products, "A", commands, "custom-" + time.strftime("%H%M%S"), timeout=300)
    for event in events:
        print(json.dumps(event, sort_keys=True))
    return events


def main():
    if len(sys.argv) > 3 and sys.argv[1] == "--custom":
        custom(Path(sys.argv[2]).resolve(), sys.argv[3:])
        return 0
    if sys.argv[1:] == ["--build"]:
        print(build())
        return 0
    if len(sys.argv) == 3 and sys.argv[1] in ("--s1", "--s2"):
        products = Path(sys.argv[2]).resolve()
        (s1 if sys.argv[1] == "--s1" else s2)(products)
        return 0
    raise SystemExit(__doc__)


if __name__ == "__main__":
    raise SystemExit(main())
