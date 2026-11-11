#!/bin/bash
# Capture evidence for the "soft reboot when a game injector (ESP overlay / SDK) is enabled" problem.
# Run on the PC (Git Bash) with the phone connected over adb and root granted to the shell.
#
#   1. bash tools/capture-injector-reboot.sh start      (streams dmesg + logcat to the PC)
#   2. enable the injector on the phone until it reboots
#   3. when adb reconnects:  bash tools/capture-injector-reboot.sh collect
#
# It tells a kernel panic (boot_id changes, pstore/last-kmsg has a panic) from a Zygote/
# system_server restart (boot_id unchanged, uptime keeps counting).
set -u
OUT="${OUT:-./injector-capture}"
export MSYS_NO_PATHCONV=1
mkdir -p "$OUT"

case "${1:-}" in
start)
  adb wait-for-device
  adb shell 'cat /proc/sys/kernel/random/boot_id; cut -d. -f1 /proc/uptime; uname -r' | tee "$OUT/before.txt"
  adb shell 'su -c "echo 7 > /proc/sys/kernel/printk"' 2>/dev/null
  # kernel ring buffer, followed live (survives until the kernel dies, which is the point)
  (adb shell 'su -c "dmesg -w"' > "$OUT/dmesg-live.txt" 2>&1 &)
  (adb logcat -b all -v threadtime > "$OUT/logcat-live.txt" 2>&1 &)
  echo "capturing to $OUT -- now trigger the injector. Leave this window open."
  ;;
collect)
  adb wait-for-device
  until adb shell 'getprop sys.boot_completed' 2>/dev/null | grep -q 1; do sleep 3; done
  adb shell 'cat /proc/sys/kernel/random/boot_id; cut -d. -f1 /proc/uptime' | tee "$OUT/after.txt"
  echo "--- boot_id before vs after (different = whole-kernel reboot):"; head -1 "$OUT/before.txt"; head -1 "$OUT/after.txt"
  adb shell 'getprop ro.boot.bootreason; getprop sys.boot.reason; getprop sys.boot.reason.last' | tee "$OUT/bootreason.txt"
  adb shell 'su -c "ls -la /sys/fs/pstore/ 2>&1; for f in /sys/fs/pstore/*; do echo \"=== \$f\"; cat \$f; done"' > "$OUT/pstore.txt" 2>&1
  adb shell 'su -c "cat /proc/last_kmsg 2>/dev/null; ls /data/vendor/diag /data/oplus/log /data/system/dropbox 2>/dev/null | tail -50"' > "$OUT/extra.txt" 2>&1
  adb shell 'su -c "dmesg"' > "$OUT/dmesg-after.txt" 2>&1
  adb bugreport "$OUT/bugreport.zip" >/dev/null 2>&1
  echo "done. Look in $OUT/pstore.txt and dmesg-live.txt for 'Kernel panic', 'BUG:', 'Oops', 'susfs', 'nomount'."
  grep -inE "kernel panic|BUG:|Oops|Unable to handle|Call trace|susfs|nomount|bbg|baseband" "$OUT"/pstore.txt "$OUT"/dmesg-live.txt 2>/dev/null | head -40
  ;;
*) echo "usage: $0 start|collect"; exit 1 ;;
esac
