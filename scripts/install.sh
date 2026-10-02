#!/bin/sh
# Install the binary and an importable rule; never edit karabiner.json.
set -eu

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
# Tests can stage the normal absolute destinations below a temporary directory.
# This does not change HOME or the paths embedded in the Karabiner rule.
staging_root=${CARDINAL_INSTALL_STAGING_ROOT:-}
case "$staging_root" in
  ''|/*) ;;
  *) echo 'CARDINAL_INSTALL_STAGING_ROOT must be absolute.' >&2; exit 2 ;;
esac
workaround_dir="$staging_root$HOME/.config/karabiner/cardinal-insert-workaround"
assets_dir="$staging_root$HOME/.config/karabiner/assets/complex_modifications"
asset_name=cardinal_insert.json

if [ ! -x "$repo_dir/build/cardinal-insert" ]; then
  echo 'Run make before installing.' >&2
  exit 1
fi
if [ -z "$staging_root" ] && /usr/bin/pgrep -x cardinal-insert >/dev/null; then
  echo 'Stop using the shortcut and wait for its worker to exit, then retry.' >&2
  exit 1
fi

mkdir -p "$workaround_dir" "$assets_dir"
if [ -e "$workaround_dir/cardinal-insert" ] || [ -e "$assets_dir/$asset_name" ]; then
  backup_dir="$workaround_dir/backups/$(date -u +%Y%m%dT%H%M%SZ)-$$"
  mkdir -p "$backup_dir"
  if [ -e "$workaround_dir/cardinal-insert" ]; then
    cp -p "$workaround_dir/cardinal-insert" "$backup_dir/cardinal-insert"
  fi
  if [ -e "$assets_dir/$asset_name" ]; then
    cp -p "$assets_dir/$asset_name" "$backup_dir/$asset_name"
  fi
  printf 'Previous files backed up to: %s\n' "$backup_dir"
fi

# Replace only these two owned files, using a temporary file in the same folder.
cleanup() {
  rm -f "$workaround_dir/cardinal-insert.new" "$assets_dir/$asset_name.new"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
install -m 755 "$repo_dir/build/cardinal-insert" "$workaround_dir/cardinal-insert.new"
mv -f "$workaround_dir/cardinal-insert.new" "$workaround_dir/cardinal-insert"
install -m 644 "$repo_dir/karabiner/$asset_name" "$assets_dir/$asset_name.new"
mv -f "$assets_dir/$asset_name.new" "$assets_dir/$asset_name"

printf 'Installed helper: %s/cardinal-insert\n' "$workaround_dir"
printf 'Installed import file: %s/%s\n' "$assets_dir" "$asset_name"
printf '%s\n' 'No active Karabiner rules or permissions were changed.' 'Next: follow docs/KARABINER.md to enable the rule and check Accessibility.'
