#!/usr/bin/env bash
# Give extra built-in LSMs their own static-call slot.
#
# MAX_LSM_COUNT (include/linux/lsm_count.h) is derived only from the upstream LSM configs. On this
# kernel that is capability, selinux, safesetid, bpf, landlock = 5, and every slot is used, so:
#   - KernelSU/SukiSU calling security_add_hooks() for a 6th LSM hits
#     `panic("Too many LSMs registered")` ~0.4 s into boot (the old "hang at the logo");
#   - a static LSM such as Baseband Guard makes append_ordered_lsm() WARN and silently drop the
#     last ordered LSM (bpf), which also breaks anything that chains through the BPF LSM.
# Counting them gives each its own slot. The slot table (struct lsm_static_calls_table) is
# private to security/security.c and not exported, so vendor modules are unaffected.
#
# usage: add-lsm-slots.sh <common-dir> NAME=CONFIG_SYMBOL [NAME=CONFIG_SYMBOL ...]
set -euo pipefail
F="${1:?common dir}/include/linux/lsm_count.h"; shift
[ -f "$F" ] || { echo "add-lsm-slots: $F not found" >&2; exit 1; }
for spec in "$@"; do
  name="${spec%%=*}"; cfg="${spec#*=}"
  if grep -q "define ${name}_ENABLED" "$F"; then echo "add-lsm-slots: $name already present"; continue; fi
  python3 - "$F" "$name" "$cfg" <<'PY'
import re, sys
path, name, cfg = sys.argv[1:]
s = open(path, encoding="utf-8").read()
anchor = "/*\n *  There is a trailing comma"
if s.count(anchor) != 1:
    sys.exit("add-lsm-slots: trailing-comma comment anchor not found exactly once")
block = f"#if IS_ENABLED({cfg})\n#define {name}_ENABLED 1,\n#else\n#define {name}_ENABLED\n#endif\n\n"
s = s.replace(anchor, block + anchor, 1)
# append NAME_ENABLED as the last argument of COUNT_LSMS(...) inside MAX_LSM_COUNT
s, n = re.subn(r"(\t\t\w+_ENABLED)\)(\s*\n\s*#else)", r"\1\t\\\n\t\t" + name + r"_ENABLED)\2", s, count=1)
if n != 1:
    sys.exit("add-lsm-slots: end of COUNT_LSMS(...) list not found")
open(path, "w", encoding="utf-8").write(s)
PY
  echo "add-lsm-slots: added slot $name ($cfg)"
done
grep -n "_ENABLED)" "$F"
