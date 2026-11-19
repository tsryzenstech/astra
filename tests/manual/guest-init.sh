#!/bin/bash
# Manual test of init's guest mode (docs/GUEST.md), as root on a Linux PC or in WSL:
#   cmake --build build/dev --target astra-init && sudo bash tests/manual/guest-init.sh
# It runs init in a mount namespace with ASTRA_GUEST=1 and a test rc that tries to change the
# hostname and kernel parameters, then ends it with SIGTERM. Expected: the host's hostname and
# vm.overcommit_memory unchanged, the service started and stopped, exit=10 (a reboot request).
R=/tmp/gt
pkill -f 'sleep 1000' 2>/dev/null; rm -rf $R
mkdir -p $R/system/bin $R/system/etc/init $R/bin $R/proc $R/dev $R/sys $R/run $R/tmp $R/data $R/vendor $R/product
SRC=${SRC:-$(cd "$(dirname "$0")/../.." && pwd)}
cp $SRC/build/dev/core/init/init $R/system/bin/init
for b in /bin/sleep /bin/sh /bin/echo; do cp -L $b $R$b; done
for f in $(ldd $SRC/build/dev/core/init/init /bin/sleep /bin/sh /bin/echo | grep -o '/[^ ]*' | sort -u); do mkdir -p $R$(dirname $f); cp -L $f $R$f; done
cat > $R/system/etc/init/test.rc <<'RC'
on early-init
    hostname hacked-guest
    write /proc/sys/kernel/panic_on_oops 0
    write /proc/sys/vm/overcommit_memory 2
    mkdir /run/astra 0755 root root
on init
    exec -- /bin/echo exec-runs
    exec -- /system/bin/udevadm trigger --action=add
on boot
    start sleeper
service sleeper /bin/sleep 1000
    class main
RC
echo "host before: hostname=$(hostname) oom=$(cat /proc/sys/vm/overcommit_memory) panic=$(cat /proc/sys/kernel/panic_on_oops)"
export ASTRA_GUEST=1
unshare -m --propagation private bash -c "mount -t proc proc $R/proc; mount --bind /dev $R/dev; chroot $R /system/bin/init second_stage > $R/init.log 2>&1; echo exit=\$? > $R/exit" &
sleep 4
echo "sleeper running:"; pgrep -af "sleep 1000" | head -2
INIT=""; for p in $(pgrep -x init); do [ "$(readlink /proc/$p/root)" = "/tmp/gt" ] && INIT=$p; done
echo "init pid: $INIT"
kill -TERM $INIT
sleep 5
echo "host after: hostname=$(hostname) oom=$(cat /proc/sys/vm/overcommit_memory) panic=$(cat /proc/sys/kernel/panic_on_oops)"
echo "--- init.log"
head -30 $R/init.log
echo "--- exit"
cat $R/exit
echo "sleeper left over:"; pgrep -af "sleep 1000" | head -2
echo "uptime still: $(cut -d' ' -f1 /proc/uptime)"
