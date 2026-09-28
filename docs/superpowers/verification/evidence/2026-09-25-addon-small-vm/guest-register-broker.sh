set -eu
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Users/admin/CascadeProbe/products/BrokerRecovery.app
/usr/bin/codesign --verify --strict --deep /Users/admin/CascadeProbe/products/BrokerRecovery.app
/Users/admin/CascadeProbe/python/bin/python3.12 -I -B /Users/admin/CascadeProbe/guest-phase-probe.py
