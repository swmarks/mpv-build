#!/usr/bin/env bash
# Re-apply the swmarks fork's patches on top of an upstream mpv-build tree.
#
# Why an overlay instead of a commit that edits patches/*/series.*: upstream
# edits those series files constantly, so a fork commit touching them
# conflicts on nearly every rebase. Keeping the fork's pool files and series
# entries here, and splicing them in with this script, makes syncing a
# conflict-free "reset to upstream/main, run fork/apply.sh, commit".
#
# Layout:
#   fork/patches/<component>/pool/<name>.patch     copied into patches/<component>/pool/
#   fork/patches/<component>/series.<group>.append  lines appended to patches/<component>/series.<group>
#
# The fork patches are scoped to the android group on purpose: a patch in
# series.common moves the content keys of every platform group, which forces
# apple, linux and windows rebuilds the fork cannot publish, and then the
# all-or-nothing "Commit manifest" job refuses to record the android build.
# Android-only keeps the other groups on upstream's already-published assets.
#
# Idempotent: rerunning on an already-applied tree changes nothing.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

shopt -s nullglob
for component_dir in fork/patches/*/; do
  component="$(basename "$component_dir")"
  mkdir -p "patches/$component/pool"

  for patch in "$component_dir"pool/*.patch; do
    cp "$patch" "patches/$component/pool/"
    echo "pool:   patches/$component/pool/$(basename "$patch")"
  done

  for append in "$component_dir"series.*.append; do
    series_name="$(basename "$append" .append)"
    series="patches/$component/$series_name"
    touch "$series"
    # Guarantee the series ends in a newline before appending to it.
    if [ -s "$series" ] && [ "$(tail -c1 "$series")" != "" ]; then
      echo >> "$series"
    fi
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in ''|'#'*) continue ;; esac
      if ! grep -qxF "$line" "$series"; then
        echo "$line" >> "$series"
        echo "series: $series += $line"
      fi
    done < "$append"
  done
done

# The android binaries are published as release assets of *this* repository,
# but upstream's group.json and artifacts.json name edde746's release. The
# manifest writer keeps an existing section's assetBase (setdefault), so
# without this rewrite a successful publish would still record download URLs
# that 404. Only android is rewritten: the other groups intentionally keep
# resolving to upstream's published assets.
FORK_REPO="${FORK_REPO:-swmarks/mpv-build}"
UPSTREAM_BASE="https://github.com/edde746/mpv-build/releases/download/binaries-android"
FORK_BASE="https://github.com/${FORK_REPO}/releases/download/binaries-android"
for f in platforms/android/group.json artifacts.json; do
  if grep -qF "$UPSTREAM_BASE" "$f"; then
    sed -i "s#${UPSTREAM_BASE}#${FORK_BASE}#g" "$f"
    echo "asset:  $f android assetBase -> $FORK_BASE"
  fi
done

# Carry the previous fork build's android section forward. A reset to
# upstream drops it, which would make keys.py treat an unchanged android key
# as stale, rebuild it, and then fail publish-assets' byte-reproducibility
# check against the asset already in our release. With the section restored,
# an unchanged key is simply not stale; a changed key is rebuilt as usual.
# Usage: PREV_ARTIFACTS=<path to the previous fork main's artifacts.json>
if [ -n "${PREV_ARTIFACTS:-}" ] && [ -f "$PREV_ARTIFACTS" ]; then
  python3 - "$PREV_ARTIFACTS" "$FORK_BASE" <<'EOF'
import json, sys
prev_path, fork_base = sys.argv[1], sys.argv[2]
prev = json.load(open(prev_path, encoding="utf-8"))
section = prev.get("platforms", {}).get("android")
if not section or section.get("assetBase") != fork_base:
    print("asset:  previous android section is not a fork build; not carried forward")
    sys.exit(0)
cur = json.load(open("artifacts.json", encoding="utf-8"))
cur.setdefault("platforms", {})["android"] = section
with open("artifacts.json", "w", encoding="utf-8") as f:
    f.write(json.dumps(cur, indent=2, sort_keys=True) + "\n")
print("asset:  carried forward previous fork android section")
EOF
fi

python3 scripts/patches.py check
echo "fork overlay applied"
