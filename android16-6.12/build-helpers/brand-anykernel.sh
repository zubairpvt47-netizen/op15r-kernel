#!/bin/bash
# Rebrand the cloned AnyKernel3 template so the recovery flash log describes THIS project.
# The upstream template (WildKernels/AnyKernel3) prints WildKernels' banner, channels and repos.
# Usage: brand-anykernel.sh <anykernel-dir> <title> <version-label> <repo-url>
set -euo pipefail

AK="${1:?anykernel dir}"
TITLE="${2:?title}"
LABEL="${3:?version label}"
REPO_URL="${4:?repo url}"
SCRIPT="$AK/anykernel.sh"

[ -f "$SCRIPT" ] || { echo "::error::$SCRIPT not found"; exit 1; }

# 1) the "<name> Supported: true/false" line
sed -i 's|ui_print " " "  -> Wild Kernels Supported: \$ksu_supported"|ui_print " " "  -> GKI 2.0 kernel detected: $ksu_supported"|' "$SCRIPT"

# 2) drop everything from the first WildKernels promo line to EOF, then append our own footer.
#    The promo block starts with: ui_print " " / ui_print "WildKernels Telegram Channel:"
start=$(grep -n 'WildKernels Telegram Channel' "$SCRIPT" | head -1 | cut -d: -f1 || true)
if [ -n "${start:-}" ]; then
  # also remove the blank ui_print line directly above it
  head -n $((start - 2)) "$SCRIPT" > "$SCRIPT.new"
else
  # template changed upstream: keep it, but never leave Wild promo lines behind
  cp "$SCRIPT" "$SCRIPT.new"
  sed -i '/WildKernels\|Wild Kernels\|wildkernels\|TheWildJames/d' "$SCRIPT.new"
fi

cat >> "$SCRIPT.new" <<EOF

ui_print " "
ui_print "$TITLE $LABEL"
ui_print "Source and build workflow:"
ui_print "$REPO_URL"
ui_print " "
ui_print "Built from Google's android16-6.12 common kernel."
ui_print "Credits: SukiSU-Ultra / KernelSU-Next, SUSFS (simonpunk),"
ui_print "NoMount, Baseband-guard, GKID patches, AnyKernel3 (osm0sis)."
ui_print " "
EOF
mv "$SCRIPT.new" "$SCRIPT"

# 3) plain-ASCII banner (the upstream one is a big "W")
cat > "$AK/banner" <<EOF
==============================
  $TITLE
  $LABEL
==============================
EOF

if grep -qiE 'wildkernels|wild kernels|thewildjames' "$SCRIPT" "$AK/banner"; then
  echo "::warning::Wild branding still present in AnyKernel3 files"
  grep -niE 'wildkernels|wild kernels|thewildjames' "$SCRIPT" "$AK/banner" || true
fi
echo "AnyKernel3 rebranded: $TITLE $LABEL"
