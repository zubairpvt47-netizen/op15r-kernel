#!/bin/bash
# Apply NTSync and the networking/filesystem config set onto a GKI android16-6.12 tree.
# (configs from https://github.com/ahmed-alnassif/GKID-Kernels, NTSync patches from
# https://github.com/WildKernels/kernel_patches -- both vendored in android16-6.12/gkid/)
#
# The NTSync group is atomic: if any step fails, the tree is rolled back to the snapshot taken before
# it and CONFIG_NTSYNC is NOT enabled; the final-config check in the workflow then fails the build.
#
# Usage: gkid-extras.sh <common_dir> <gkid_dir> <conditional_fragment_out> <report_out>
#   env: GKID_NTSYNC GKID_NET GKID_NET_DEFAULTS (true/false)
set -uo pipefail

COMMON="${1:?common dir}"
GK="${2:?gkid dir}"
FRAG="${3:?fragment out}"
REPORT="${4:?report out}"

GKID_NTSYNC="${GKID_NTSYNC:-true}"
GKID_NET="${GKID_NET:-true}"
GKID_NET_DEFAULTS="${GKID_NET_DEFAULTS:-true}"

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
# r54 carries an old drivers/misc/ntsync.c but its Kconfig entry says "depends on BROKEN", so
# CONFIG_NTSYNC=y alone is silently dropped (no /dev/ntsync). Same as WildKernels' ntsync action for
# android16-6.12 (WildKernels/kernel_patches common/ntsync @10c98a49): remove the stock copy, drop the
# BROKEN dependency, install the current driver.
ntsync_group() {
  grep -q 'config NTSYNC' drivers/misc/Kconfig || { log "  no NTSYNC Kconfig symbol"; return 1; }
  grep -q 'obj-$(CONFIG_NTSYNC)' drivers/misc/Makefile || { log "  no NTSYNC Makefile rule"; return 1; }
  rm -f include/uapi/linux/ntsync.h drivers/misc/ntsync.c
  apply_one "$GK/patches/ntsync_compat_android16-6.12.patch" || return 1
  apply_one "$GK/patches/ntsync_base.patch" || return 1
  [ -f drivers/misc/ntsync.c ] && [ -f include/uapi/linux/ntsync.h ] || { log "  ntsync driver files missing after patch"; return 1; }
  if grep -A3 '^config NTSYNC' drivers/misc/Kconfig | grep -q 'depends on BROKEN'; then log "  NTSYNC still depends on BROKEN"; return 1; fi
  echo "CONFIG_NTSYNC=y" >> "$FRAG.group"
}

snapshot
[ "$GKID_NET" = "true" ]          && { log "== networking/filesystem configs"; cat "$GK/config/net.fragment" >> "$FRAG"; }
[ "$GKID_NET_DEFAULTS" = "true" ] && { log "== BBR default congestion control + fq_codel default qdisc"; cat "$GK/config/net-defaults.fragment" >> "$FRAG"; }
[ "$GKID_NTSYNC" = "true" ]       && group "NTSync" ntsync_group
rm -f "$FRAG.group"

log ""
log "Conditional kernel configs:"
cat "$FRAG" | tee -a "$REPORT"
exit 0
