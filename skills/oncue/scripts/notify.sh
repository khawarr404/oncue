#!/bin/bash
# Shows a suggested answer as a desktop pop-up and appends it to answers.md in the current session.
# Usage: notify.sh "question" "answer"   (ONCUE_NO_POPUP=1 skips the pop-up)
HOME_DIR="${ONCUE_HOME:-$HOME/oncue}"
F=$(cat "$HOME_DIR/sessions/LATEST" 2>/dev/null)
[ -n "$F" ] && printf -- "- **Q (%s):** %s\n  **Say:** %s\n\n" "$(date +%H:%M:%S)" "$1" "$2" >> "$(dirname "$F")/answers.md"
[ -z "$ONCUE_NO_POPUP" ] && command -v notify-send >/dev/null && notify-send -u critical -a "oncue" "💬 $1" "$2"
true
