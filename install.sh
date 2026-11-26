#!/bin/bash
# Links (or copies) the skills into the folders AI coding tools read skills from.
#
# Usage: ./install.sh [claude] [agents] [copilot] [--copy]
#   claude   ~/.claude/skills    Claude Code (Cursor reads it too)
#   agents   ~/.agents/skills    Cursor, Codex, Gemini CLI, Windsurf
#   copilot  ~/.copilot/skills   GitHub Copilot in VS Code
#   (no target given: claude and agents)
#   --copy   copy the folders instead of symlinking (symlinks follow `git pull`)
set -e
REPO="$(cd "$(dirname "$0")" && pwd)"
MODE=link; TARGETS=()
for a in "$@"; do
  case "$a" in
    --copy) MODE=copy ;;
    claude) TARGETS+=("$HOME/.claude/skills") ;;
    agents) TARGETS+=("$HOME/.agents/skills") ;;
    copilot) TARGETS+=("$HOME/.copilot/skills") ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown option: $a"; exit 1 ;;
  esac
done
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=("$HOME/.claude/skills" "$HOME/.agents/skills")

for dir in "${TARGETS[@]}"; do
  mkdir -p "$dir"
  for skill in "$REPO"/skills/*/; do
    name=$(basename "$skill"); dest="$dir/$name"
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
      echo "skip $dest (a folder already exists there; move it away first)"; continue
    fi
    if [ "$MODE" = copy ]; then
      rm -f "$dest"; cp -r "${skill%/}" "$dest"
    else
      ln -sfn "${skill%/}" "$dest"
    fi
    echo "installed $name -> $dest"
  done
done
echo "Next: run skills/oncue/scripts/setup.sh once (Linux + PipeWire), or ask your agent to \"set up oncue\"."
