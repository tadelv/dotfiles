#!/bin/bash

if [ "$SENDER" = "aerospace_workspace_change" ]; then
  source "$CONFIG_DIR/colors.sh"

  # Update all spaces: highlight focused, dim the rest
  for sid in $(aerospace list-workspaces --all); do
    if [ "$sid" = "$FOCUSED_WORKSPACE" ]; then
      sketchybar --set space.$sid icon.highlight=on
    else
      sketchybar --set space.$sid icon.highlight=off
    fi
  done
fi
