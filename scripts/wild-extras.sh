#!/bin/bash
# Apply the WildKernels feature set (kernel_patches repo) onto a GKI android16-6.12 tree.
#
# Every group is atomic: if any patch in a group fails, the tree is rolled back to the
# snapshot taken before that group and the group's kernel configs are NOT enabled.
# That matters for Droidspaces (SYSVIPC/USER_NS change struct layouts -> would break
# vendor modules without the kABI padding patches).
#
# Usage: wild-extras.sh <common_dir> <kernel_patches_dir> <conditional_fragment_out> <report_out>
#   env: WILD_PERF WILD_NTSYNC WILD_DROIDSPACES WILD_UNICODE (true/false)
set -uo pipefail

COMMON="${1:?common dir}"
KP="${2:?kernel_patches dir}"
FRAG="${3:?fragment out}"
REPORT="${4:?report out}"

WILD_PERF="${WILD_PERF:-true}"
WILD_NTSYNC="${WILD_NTSYNC:-true}"
WILD_DROIDSPACES="${WILD_DROIDSPACES:-true}"
WILD_UNICODE="${WILD_UNICODE:-true}"

P="$KP/common"
: > "$FRAG"
: > "$REPORT"

cd "$COMMON"
git config user.name  "build" >/dev/null 2>&1 || true
git config user.email "build@localhost" >/dev/null 2>&1 || true

snapshot() { git add -A >/dev/null 2>&1; git commit -qm "wild-extras snapshot" --allow-empty >/dev/null 2>&1; }
rollback() { git reset -q --hard HEAD >/dev/null 2>&1; git clean -fdq >/dev/null 2>&1; }
log()      { echo "$*" | tee -a "$REPORT"; }

# apply_one <patch> -> 0 ok / 1 fail (never leaves a half-applied patch behind)
apply_one() {
  local f="$1"
  [ -f "$f" ] || { log "  MISSING $(basename "$f")"; return 1; }
  if patch -p1 --forward -F3 --dry-run < "$f" >/dev/null 2>&1; then
    patch -p1 --forward -F3 --no-backup-if-mismatch < "$f" >/dev/null 2>&1 \
      && { log "  ok      $(basename "$f")"; return 0; }
  fi
  log "  FAILED  $(basename "$f")"
  return 1
}

# group <name> <fn>: run fn; on failure roll the tree back
group() {
  local name="$1" fn="$2"
  log "== $name"
  snapshot
  if "$fn"; then
    log "== $name: ENABLED"
    snapshot
    return 0
  fi
  rollback
  log "== $name: SKIPPED (rolled back)"
  return 1
}

# ---------------------------------------------------------------- performance/tuning
perf_group() {
  local ok=0
  # Each tuning patch is independent; one failing does not sink the others.
  # NOTE: file_struct_8bytes_align is intentionally NOT applied: it changes the declared alignment
  # of struct file, which alters the modversions CRC of every symbol touching struct file/path/inode
  # (and the Rust binder bindings), so vendor modules would no longer match the stock ABI.
  for p in optimized_mem_operations reduce_cache_pressure \
           mem_opt_prefetch optimise_memcmp minimise_wakeup_time int_sqrt \
           reduce_gc_thread_sleep_time add_timeout_wakelocks_globally \
           f2fs_reduce_congestion reduce_freeze_timeout clear_page_16bytes_align \
           add_limitation_scaling_min_freq re_write_limitation_scaling_min_freq \
           adjust_cpu_scan_order avoid_extra_s2idle_wake_attempts disable_cache_hot_buddy \
           f2fs_enlarge_min_fsync_blocks increase_ext4_default_commit_age \
           increase_sk_mem_packets reduce_pci_pme_wakeups silence_irq_cpu_logspam \
           silence_system_logspam use_unlikely_wrap_cpufreq; do
    snapshot
    apply_one "$P/$p.patch" || rollback
  done
  # BBR is enabled in this build, so force_tcp_nodelay is intentionally NOT applied
  # (same rule WildKernels uses).
  return 0
}

# ---------------------------------------------------------------- NTSync
ntsync_group() {
  rm -f include/uapi/linux/ntsync.h drivers/misc/ntsync.c
  apply_one "$P/ntsync/ntsync_compat_android16-6.12.patch" || return 1
  apply_one "$P/ntsync/ntsync_base.patch" || return 1
  echo "CONFIG_NTSYNC=y" >> "$FRAG"
}

# ---------------------------------------------------------------- Droidspaces
droidspaces_group() {
  apply_one "$P/droidspaces/fix_sysvipc_kabi_a16-6.12.patch" || return 1
  apply_one "$P/droidspaces/0001-Return-ghost-task-if-task-is-null-and-is-requested-b.patch" || return 1
  [ -f ipc/namespace.c ] && [ -f ipc/msgutil.c ] || return 1
  # stock kernel ships Rust binder as a module; it needs these IPC ns symbols
  grep -q 'EXPORT_SYMBOL.*put_ipc_ns' ipc/namespace.c \
    || printf '\nEXPORT_SYMBOL_GPL(put_ipc_ns);\n' >> ipc/namespace.c
  grep -q 'EXPORT_SYMBOL.*init_ipc_ns' ipc/msgutil.c \
    || printf '\nEXPORT_SYMBOL_GPL(init_ipc_ns);\n' >> ipc/msgutil.c
  cat >> "$FRAG" <<'EOF'
CONFIG_SYSVIPC=y
CONFIG_DEVTMPFS=y
CONFIG_PID_NS=y
CONFIG_POSIX_MQUEUE=y
CONFIG_NETFILTER_XT_TARGET_REJECT=y
CONFIG_NETFILTER_XT_TARGET_LOG=y
CONFIG_NETFILTER_XT_MATCH_RECENT=y
CONFIG_USER_NS=y
CONFIG_MACVLAN=y
EOF
}

# ---------------------------------------------------------------- Unicode bypass fix
unicode_group() {
  apply_one "$P/unicode_bypass_fix_6.1+.patch"
}

snapshot
[ "$WILD_PERF" = "true" ]        && { log "== performance/tuning patches"; perf_group; }
[ "$WILD_NTSYNC" = "true" ]      && group "NTSync"      ntsync_group
[ "$WILD_DROIDSPACES" = "true" ] && group "Droidspaces" droidspaces_group
[ "$WILD_UNICODE" = "true" ]     && group "Unicode bypass fix" unicode_group

log ""
log "Conditional kernel configs:"
cat "$FRAG" | tee -a "$REPORT"
exit 0
