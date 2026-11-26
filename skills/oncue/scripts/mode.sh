#!/bin/bash
# Lists the answer modes or switches the current one. The current mode is stored in $ONCUE_HOME/mode.txt
# (missing means meeting). Built-in modes are in the skill's modes/ folder; your own modes go in
# $ONCUE_HOME/modes/<name>.md, and one with the same name as a built-in mode replaces it.
#
# Usage: mode.sh            list modes, the current one marked with *
#        mode.sh NAME       switch to NAME (e.g. interview)
#        mode.sh --path     print the current mode's file (for the agent to read)
source "$(dirname "$0")/_lib.sh"

# mode_file NAME: prints the file for mode NAME (yours first); fails for unknown or malformed names.
mode_file() {
  case "$1" in ''|[!a-z0-9]*|*[!a-z0-9_-]*) return 1 ;; esac
  if [ -f "$HOME_DIR/modes/$1.md" ]; then echo "$HOME_DIR/modes/$1.md"
  elif [ -f "$SKILL_DIR/modes/$1.md" ]; then echo "$SKILL_DIR/modes/$1.md"
  else return 1; fi
}
current_mode() {
  local m
  m=$(tr -d '[:space:]' 2>/dev/null < "$HOME_DIR/mode.txt")
  if [ -n "$m" ] && mode_file "$m" > /dev/null; then echo "$m"; else echo meeting; fi
}
list_modes() {
  local cur n note
  cur=$(current_mode)
  for f in "$SKILL_DIR"/modes/*.md "$HOME_DIR"/modes/*.md; do [ -f "$f" ] && basename "$f" .md; done | sort -u |
  while read -r n; do
    mode_file "$n" > /dev/null || continue
    note=""
    if [ -f "$HOME_DIR/modes/$n.md" ]; then
      note="(yours)"; [ -f "$SKILL_DIR/modes/$n.md" ] && note="(yours, replaces the built-in one)"
    fi
    if [ "$n" = "$cur" ]; then printf '* %-12s %s\n' "$n" "$note"; else printf '  %-12s %s\n' "$n" "$note"; fi
  done | sed 's/ *$//'
}

case "${1:-}" in
  "") list_modes ;;
  --path) mode_file "$(current_mode)" ;;
  -h|--help) sed -n '2,9p' "$0" ;;
  *)
    name=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
    if ! file=$(mode_file "$name"); then
      echo "unknown mode: $1. Modes:" >&2; list_modes >&2; exit 1
    fi
    echo "$name" > "$HOME_DIR/mode.txt"
    echo "mode: $name ($file)"
    ;;
esac
