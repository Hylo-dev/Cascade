set -eu
umask 077
mkdir -p "$HOME/.ssh"
printf '%s\n' 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMliaaizgRav6SISGoIg3hCxMSsik276gno/26o9KcBa cascade-disposable-vm' >> "$HOME/.ssh/authorized_keys"
chmod 600 "$HOME/.ssh/authorized_keys"
printf '\nGUEST_IDENTITY\n'
/usr/bin/sw_vers
/usr/sbin/sysctl -n hw.model
/usr/sbin/sysctl -n kern.bootsessionuuid
/usr/bin/stat -f %Su /dev/console
/usr/bin/id
sudo -n /usr/bin/true
/usr/bin/csrutil status
/usr/bin/csrutil authenticated-root status
printf '\nREMOVE_GUEST_INTERNET_ROUTES\n'
for family in inet inet6; do
  /usr/sbin/netstat -rn -f "$family" | /usr/bin/awk '$1=="default" {print $2, $3, $4}' | while read -r gateway flags interface; do
    case "$flags" in
      *I*) sudo -n /sbin/route -n delete -"$family" -ifscope "$interface" default "$gateway" ;;
      *) sudo -n /sbin/route -n delete -"$family" default "$gateway" ;;
    esac
  done
done
printf '\nGUEST_ROUTES_IPV4\n'
/usr/sbin/netstat -rn -f inet
printf '\nGUEST_ROUTES_IPV6\n'
/usr/sbin/netstat -rn -f inet6
printf '\nGUEST_STORAGE_AND_SHARE\n'
/bin/df -h /
/bin/ls -l '/Volumes/My Shared Files/probe/payload.tar.gz'
