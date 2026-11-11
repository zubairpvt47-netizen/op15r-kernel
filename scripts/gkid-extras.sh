#!/bin/bash
# Apply the optional GKID-Kernels feature groups onto a GKI android16-6.12 tree.
# (https://github.com/ahmed-alnassif/GKID-Kernels -- patches/configs vendored in android16-6.12/gkid/)
#
# Performance and battery tweaks (GKID's tuning patches, HZ=300, MGLRU force, governors, zram
# defaults) are deliberately NOT part of this script.
#
# Every group is atomic: if any step of a group fails, the tree is rolled back to the snapshot
# taken before that group and the group's kernel configs are NOT enabled (so a half-applied
# DroidSpaces/NetHunter can never change struct layouts without its kABI padding).
#
# Usage: gkid-extras.sh <common_dir> <gkid_dir> <conditional_fragment_out> <report_out>
#   env: GKID_NTSYNC GKID_DROIDSPACES GKID_NETHUNTER GKID_BBRV3 GKID_NET GKID_NET_DEFAULTS (true/false)
set -uo pipefail

COMMON="${1:?common dir}"
GK="${2:?gkid dir}"
FRAG="${3:?fragment out}"
REPORT="${4:?report out}"

GKID_NTSYNC="${GKID_NTSYNC:-true}"
GKID_DROIDSPACES="${GKID_DROIDSPACES:-true}"
GKID_NETHUNTER="${GKID_NETHUNTER:-false}"
GKID_BBRV3="${GKID_BBRV3:-false}"
GKID_NET="${GKID_NET:-true}"
GKID_NET_DEFAULTS="${GKID_NET_DEFAULTS:-false}"
RTW88_REPO="https://github.com/ahmed-alnassif/rtw88.git"
RTW88_PIN="2bdfb5a7470d922163c4ae410f6619f924cf2b7e"

: > "$FRAG"
: > "$REPORT"

cd "$COMMON"
git config user.name  "build" >/dev/null 2>&1 || true
git config user.email "build@localhost" >/dev/null 2>&1 || true

snapshot() { git add -A >/dev/null 2>&1; git commit -qm "gkid-extras snapshot" --allow-empty >/dev/null 2>&1; }
rollback() { git reset -q --hard HEAD >/dev/null 2>&1; git clean -fdq >/dev/null 2>&1; : > "$FRAG.group"; }
log()      { echo "$*" | tee -a "$REPORT"; }

# apply_one <patch>: strict (no fuzz); never leaves a half-applied patch behind
apply_one() {
  local f="$1"
  [ -f "$f" ] || { log "  MISSING $(basename "$f")"; return 1; }
  if patch -p1 -F0 --forward --dry-run < "$f" >/dev/null 2>&1; then
    patch -p1 -F0 --forward --no-backup-if-mismatch < "$f" >/dev/null 2>&1 \
      && { log "  ok      $(basename "$f")"; return 0; }
  fi
  log "  FAILED  $(basename "$f")"
  return 1
}

# group <name> <fn>: run fn (it writes its configs to $FRAG.group); on failure roll the tree back
group() {
  local name="$1" fn="$2"
  log "== $name"
  snapshot
  : > "$FRAG.group"
  if "$fn"; then
    cat "$FRAG.group" >> "$FRAG"
    log "== $name: ENABLED"
    snapshot
    return 0
  fi
  rollback
  log "== $name: SKIPPED (rolled back)"
  return 1
}

# ---------------------------------------------------------------- NTSync
# r54 already carries drivers/misc/ntsync.c; only the config is needed.
ntsync_group() {
  [ -f drivers/misc/ntsync.c ] && [ -f include/uapi/linux/ntsync.h ] || { log "  no ntsync driver in this tree"; return 1; }
  grep -q 'config NTSYNC' drivers/misc/Kconfig || { log "  no NTSYNC Kconfig symbol"; return 1; }
  echo "CONFIG_NTSYNC=y" >> "$FRAG.group"
}

# ---------------------------------------------------------------- DroidSpaces
droidspaces_group() {
  apply_one "$GK/patches/droidspaces-sysvipc-kabi-6.12.patch" || return 1
  [ -f ipc/namespace.c ] && [ -f ipc/msgutil.c ] || return 1
  # stock ships Rust binder as a module; it needs these IPC ns symbols once SYSVIPC/IPC_NS exist
  grep -q 'EXPORT_SYMBOL.*put_ipc_ns' ipc/namespace.c \
    || printf '\nEXPORT_SYMBOL_GPL(put_ipc_ns);\n' >> ipc/namespace.c
  grep -q 'EXPORT_SYMBOL.*init_ipc_ns' ipc/msgutil.c \
    || printf '\nEXPORT_SYMBOL_GPL(init_ipc_ns);\n' >> ipc/msgutil.c
  cat "$GK/config/droidspaces.fragment" >> "$FRAG.group"
}

# ---------------------------------------------------------------- NetHunter
nethunter_group() {
  apply_one "$GK/patches/nethunter-mac80211-monitor-inject.patch" || return 1
  local d; d="$(mktemp -d)"
  git clone -q "$RTW88_REPO" "$d/rtw88" && git -C "$d/rtw88" checkout -q --detach "$RTW88_PIN" || { log "  FAILED  rtw88 clone"; return 1; }
  rm -rf drivers/net/wireless/realtek/rtw88
  rm -rf "$d/rtw88/.git"
  mv "$d/rtw88" drivers/net/wireless/realtek/rtw88
  log "  ok      rtw88 @ ${RTW88_PIN:0:8}"
  cat "$GK/config/nethunter.fragment" >> "$FRAG.group"
}

# ---------------------------------------------------------------- BBRv3
bbrv3_group() {
  apply_one "$GK/patches/bbrv3.patch" || return 1
  cat "$GK/config/net-defaults.fragment" >> "$FRAG.group"
}

snapshot
[ "$GKID_NET" = "true" ]          && { log "== networking/filesystem configs"; cat "$GK/config/net.fragment" >> "$FRAG"; }
[ "$GKID_NET_DEFAULTS" = "true" ] && { log "== BBR default congestion control + fq_codel default qdisc"; cat "$GK/config/net-defaults.fragment" >> "$FRAG"; }
[ "$GKID_NTSYNC" = "true" ]       && group "NTSync"      ntsync_group
[ "$GKID_DROIDSPACES" = "true" ]  && group "DroidSpaces" droidspaces_group
[ "$GKID_NETHUNTER" = "true" ]    && group "NetHunter"   nethunter_group
[ "$GKID_BBRV3" = "true" ]        && group "BBRv3"       bbrv3_group
rm -f "$FRAG.group"

log ""
log "Conditional kernel configs:"
cat "$FRAG" | tee -a "$REPORT"
exit 0
