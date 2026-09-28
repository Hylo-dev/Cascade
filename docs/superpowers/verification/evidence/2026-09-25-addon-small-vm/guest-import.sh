set -eu
printf '\nPAYLOAD_SOURCE_HASH\n'
/usr/bin/shasum -a 256 '/Volumes/My Shared Files/probe/payload.tar.gz'
mkdir -p /Users/admin/CascadeProbe
/usr/bin/tar -xzf '/Volumes/My Shared Files/probe/payload.tar.gz' -C /Users/admin/CascadeProbe
printf '\nPYTHON_PREFLIGHT\n'
/Users/admin/CascadeProbe/python/bin/python3.12 -I -B -c 'import hashlib,json,select,subprocess,pathlib,plistlib,sys; print(json.dumps({"version":sys.version,"kqueue":hasattr(select,"kqueue")}))'
printf '\nGUEST_LAUNCHCTL_DEBUG_HELP\n'
/bin/launchctl help debug
printf '\nPAYLOAD_METADATA\n'
/usr/bin/xattr -lr /Users/admin/CascadeProbe/products
