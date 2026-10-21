#!/bin/bash

# Toggle the named Hyprland rule aditya-opaque.
# on: every window is fully solid. off: Omarchy's stock transparency.

FLAG="${HOME}/.local/state/omarchy/toggles/opaque"

# The flag is the saved state. A name-only rule lookup reports enabled even
# when the opacity override is not applied, so status follows the flag.
is_enabled() {
  [[ -f $FLAG ]]
}

set_rule() {
  local enabled=$1
  local out

  # repl changes the live rule. eval re-commits the config and drops the change.
  out=$(hyprctl repl "local r = hl.window_rule({ name = \"aditya-opaque\", match = { class = \".*\" }, opacity = \"1 override 1 override 1 override\" }); if not r then return \"missing\" end; r:set_enabled(${enabled}); return tostring(r:is_enabled())") || return 1
  [[ ${out//$'\n'/} == "$enabled" ]]
}

enable() {
  set_rule true || return 1
  mkdir -p "$(dirname "$FLAG")"
  touch "$FLAG"
}

disable() {
  set_rule false || return 1
  rm -f "$FLAG"
}

refresh_shell() {
  omarchy-shell -q opaque refresh
}

case "${1:-toggle}" in
  --enabled)
    is_enabled
    exit
    ;;
  on|enable)
    enable || exit 1
    ;;
  off|disable)
    disable || exit 1
    ;;
  toggle|"")
    if is_enabled; then
      disable || exit 1
    else
      enable || exit 1
    fi
    ;;
  *)
    echo "Usage: toggle.sh [--enabled|toggle|on|off]" >&2
    exit 1
    ;;
esac

refresh_shell
