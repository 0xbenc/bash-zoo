#!/usr/bin/env bash

set -euo pipefail

panel=(
  "+------------------------------+"
  "| enter   open     h/left  up  |"
  "| space   select   .       hide|"
  "| ctrl-g  search   ctrl-e  edit|"
  "| ctrl-y  copy     alt-m   move|"
  "| ctrl-d  delete   ctrl-p  props|"
  "| ctrl-b  mkdir    ctrl-n  new |"
  "+------------------------------+"
)

if [[ ! -t 1 ]]; then
  printf '%s\n' "${panel[@]}"
  exit 0
fi

rows=$(tput lines)
cols=$(tput cols)
height=${#panel[@]}
width=0

for line in "${panel[@]}"; do
  line_len=${#line}
  if (( line_len > width )); then
    width=$line_len
  fi
done

start_row=$(( rows - height + 1 ))
if (( start_row < 1 )); then
  start_row=1
fi
start_col=$(( cols - width + 1 ))
if (( start_col < 1 )); then
  start_col=1
fi

printf '\033[s'
for i in "${!panel[@]}"; do
  row=$(( start_row + i ))
  printf '\033[%d;%dH' "$row" "$start_col"
  printf '%-*s' "$width" ""
  printf '\033[%d;%dH%s' "$row" "$start_col" "${panel[i]}"
done
printf '\033[u'
