#!/bin/bash
# Shows a suggested answer as a desktop pop-up and appends it to answers.md in the current session.
# Usage: notify.sh "question" "answer"   (ONCUE_NO_POPUP=1 skips the pop-up)
# A multi-line answer (a recap) keeps its lines: blank lines are dropped and the rest indented under it.
HOME_DIR="${ONCUE_HOME:-$HOME/oncue}"
F=$(cat "$HOME_DIR/sessions/LATEST" 2>/dev/null)
A=$(printf '%s\n' "$2" | sed '/^[[:space:]]*$/d' | sed '2,$s/^[[:space:]]*/    /')
[ -n "$F" ] && printf -- "- **Q (%s):** %s\n  **Say:** %s\n\n" "$(date +%H:%M:%S)" "$1" "$A" >> "$(dirname "$F")/answers.md"
[ -z "$ONCUE_NO_POPUP" ] && command -v notify-send >/dev/null && notify-send -u critical -a "oncue" "💬 $1" "$2"
true
