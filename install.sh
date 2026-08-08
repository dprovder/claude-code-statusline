#!/usr/bin/env bash
# Install statusline.sh into your Claude Code config and register it.
#
#   ./install.sh              # install to ~/.claude (or $CLAUDE_CONFIG_DIR)
#   ./install.sh --symlink    # link instead of copy, so repo edits apply live
#
# Existing settings.json is backed up to settings.json.bak before any change.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dest="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
mode="copy"
[ "${1:-}" = "--symlink" ] && mode="symlink"

command -v jq >/dev/null 2>&1 || {
  echo "error: jq is required (brew install jq / apt install jq)" >&2
  exit 1
}

mkdir -p "$dest"

if [ "$mode" = "symlink" ]; then
  ln -sf "$here/statusline.sh" "$dest/statusline.sh"
  echo "linked  $dest/statusline.sh -> $here/statusline.sh"
else
  cp "$here/statusline.sh" "$dest/statusline.sh"
  chmod +x "$dest/statusline.sh"
  echo "copied  $here/statusline.sh -> $dest/statusline.sh"
fi

settings="$dest/settings.json"
if [ -f "$settings" ]; then
  cp "$settings" "$settings.bak"
  echo "backup  $settings.bak"
else
  echo '{}' > "$settings"
fi

tmp=$(mktemp)
jq --arg cmd "$dest/statusline.sh" \
   '.statusLine = {type: "command", command: $cmd, padding: 0}' \
   "$settings" > "$tmp"
mv "$tmp" "$settings"
echo "wired   statusLine in $settings"
echo
echo "Done. Restart Claude Code to pick it up."
