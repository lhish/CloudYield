#!/bin/bash
set -euo pipefail

APP_NAME="NeteaseMusic"
MENU_BAR_ITEM_NAME="控制"
PLAY_MENU_ITEM_NAME="播放"
PAUSE_MENU_ITEM_NAME="暂停"

is_running="$(osascript -e "application \"${APP_NAME}\" is running" 2>/dev/null || true)"
if [[ "${is_running}" != "true" ]]; then
  echo "not_running"
  exit 0
fi

result="$(osascript <<EOF 2>/dev/null || true
tell application "System Events"
    tell process "${APP_NAME}"
        try
            set menuItemName to name of menu item 1 of menu "${MENU_BAR_ITEM_NAME}" of menu bar item "${MENU_BAR_ITEM_NAME}" of menu bar 1
            return menuItemName
        on error
            return "error"
        end try
    end tell
end tell
EOF
)"

case "${result}" in
  "${PAUSE_MENU_ITEM_NAME}")
    echo "playing"
    ;;
  "${PLAY_MENU_ITEM_NAME}")
    echo "paused"
    ;;
  *)
    echo "unknown:${result}"
    ;;
esac

