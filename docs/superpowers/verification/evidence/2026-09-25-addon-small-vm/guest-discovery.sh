set -eu
/usr/bin/log show --last 2m --style compact --info --debug --predicate 'eventMessage CONTAINS "hylo.Cascade" OR process == "ProbeProvider" OR process == "DiscoveryBroker"' 2>&1 | /usr/bin/tail -180
printf '\nCRASH_FILES\n'
/bin/ls -lt /Users/admin/Library/Logs/DiagnosticReports | /usr/bin/head -12
printf '\nEXTENSION_REGISTRATION\n'
/usr/bin/pluginkit -m -A -D -v -i hylo.Cascade.AddonProbeContainer.Provider
