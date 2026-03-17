#!/bin/bash

sketchybar --add event aerospace_workspace_change

AEROSPACE_LIST=$(aerospace list-workspaces --all)
AEROSPACE_FOCUSED=$(aerospace list-workspaces --focused)

while read -r sid; do
  # Show spaces on their assigned monitor: 1-4 on built-in (display 1), 5-9 on LG (display 2)
  if [ "$sid" -le 4 ]; then
    DISPLAY_ID=1
  else
    DISPLAY_ID=2
  fi

  space=(
    icon="$sid"
    icon.font="$FONT:Bold:14.0"
    icon.color=$GREY
    icon.highlight_color=$WHITE
    icon.padding_left=6
    icon.padding_right=6
    padding_left=2
    padding_right=2
    label.drawing=off
    background.drawing=off
    display=$DISPLAY_ID
    click_script="aerospace workspace $sid"
    script="$PLUGIN_DIR/aerospace.sh"
  )

  sketchybar --add item space.$sid left \
    --set space.$sid "${space[@]}" \
    --subscribe space.$sid aerospace_workspace_change

  # Set initial highlight for focused workspace
  if [ "$sid" = "$AEROSPACE_FOCUSED" ]; then
    sketchybar --set space.$sid icon.highlight=on
  fi
done <<< "$AEROSPACE_LIST"
