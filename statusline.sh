#!/usr/bin/env bash
# Claude Code status line
#   repo · branch · context bar · cost · code velocity · rate limits · model
#
# Text only, no emoji. Severity still has a non-color encoding: a "!" prefix
# appears at 70% context and "!!" at 90%, so the warning survives both a
# color-vision-deficient palette and a monochrome terminal. Below 70% the
# marker is absent, keeping the common case quiet.
#
# Palette:
#   "daltonized" (default) ramps blue → purple → red. That is the blue/red
#   axis, which stays distinguishable under protan and deuteran color vision,
#   unlike the usual green → yellow → red. Luminance is kept mid-range so the
#   bar reads on both TokyoNight Day (light) and TokyoNight (dark).
#   "classic" restores the original green → yellow → red gradient.
#
# Width:
#   Claude Code captures stdout rather than attaching it to the terminal, so
#   `tput cols` reports a useless default. It exports COLUMNS/LINES instead
#   (v2.1.153+). System notifications also render on the RIGHT of this same
#   row, so we budget for less than the full width — see RESERVE.
#
# Speed:
#   This runs after every assistant message, and a slow script blocks status
#   line updates, so the hot paths avoid subshells: colors and rounding use
#   `printf -v`, and git is a single invocation in the common case.
#
# Env overrides:
#   CLAUDE_STATUSLINE_PALETTE=classic     original green→red gradient
#   CLAUDE_STATUSLINE_PALETTE_FILE=<path> sourced RGB overrides, so a terminal
#                                         theme can own the colours (see below).
#                                         Defaults to
#                                         ~/.config/claude-code-statusline/palette.sh
#   CLAUDE_STATUSLINE_RESERVE=<n>         columns kept clear for notifications
#   CLAUDE_STATUSLINE_COLUMNS=<n>         force a width (for testing)
PALETTE="${CLAUDE_STATUSLINE_PALETTE:-daltonized}"
RESERVE="${CLAUDE_STATUSLINE_RESERVE:-14}"

input=$(cat)

# ── One jq pass. Delimited by \x1f (unit separator) rather than tab: tab is an
# IFS whitespace char, so bash would collapse runs of them and shift fields
# whenever an optional value (e.g. used_percentage) is absent.
# On malformed input, exit silently — the docs specify that no output leaves
# the status line blank, which beats rendering a half-parsed row. ──
parsed=$(printf '%s' "$input" | jq -r '[
    (.model.display_name // "Unknown"),
    (.context_window.used_percentage // ""),
    (.cost.total_cost_usd // 0),
    (.cost.total_lines_added // 0),
    (.cost.total_lines_removed // 0),
    (.workspace.current_dir // .cwd // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.seven_day.used_percentage // "")
  ] | map(tostring) | join("\u001f")' 2>/dev/null) || exit 0
[ -n "$parsed" ] || exit 0
IFS=$'\x1f' read -r model used cost lines_add lines_del cwd lim5h lim7d <<<"$parsed"

# ── Terminal width ──
cols="${CLAUDE_STATUSLINE_COLUMNS:-${COLUMNS:-}}"
case "$cols" in
  ''|*[!0-9]*) cols=120 ;;                 # unset or non-numeric
  *) [ "$cols" -eq 0 ] && cols=120 ;;      # 0 means "not reported"
esac
case "$RESERVE" in ''|*[!0-9]*) RESERVE=14 ;; esac
# Never spend more than a quarter of a narrow terminal on notification
# headroom — reserving 14 of 24 columns would leave nothing to show.
quarter=$(( cols / 4 ))
[ "$RESERVE" -gt "$quarter" ] && RESERVE=$quarter
avail=$(( cols - RESERVE ))
[ "$avail" -lt 12 ] && avail=12

# ── Palette ──
BOLD=$'\033[1m'
RESET=$'\033[0m'
esc() { printf -v "$1" '\033[38;2;%d;%d;%dm' "$2" "$3" "$4"; }

# An external palette file lets an editor/terminal theme own these colours, so
# the status line matches its surroundings instead of approximating them. It is
# sourced, not parsed — one file read, no subshell, which this hot path cares
# about. Sourcing executes it: only point this at a file you control.
#
# It defines RGB triples; any it omits fall back to the built-in palette below,
# so a file can restyle one segment without restating all of them:
#   PAL_LO PAL_MID PAL_HI         severity ramp (low → mid → high)
#   PAL_REPO PAL_BRANCH PAL_COST PAL_ADD PAL_DEL PAL_MODEL PAL_DIM PAL_EMPTY
#
# Keep PAL_LO→PAL_MID→PAL_HI on the blue→red axis. That is what keeps the ramp
# readable under protan and deuteran vision; a green→red ramp collapses.
# Falls back to a conventional path so a theme can drop a palette in place and
# have it picked up with no env var to plumb through — which matters because
# the status line is spawned by Claude Code, not by a shell you control.
PALETTE_FILE="${CLAUDE_STATUSLINE_PALETTE_FILE:-$HOME/.config/claude-code-statusline/palette.sh}"
if [ -n "$PALETTE_FILE" ] && [ -r "$PALETTE_FILE" ]; then
  # shellcheck disable=SC1090
  . "$PALETTE_FILE" 2>/dev/null || true
fi

if [ "$PALETTE" = "classic" ]; then
  LO=(0 200 80); MID=(220 200 0); HI=(220 40 20)
  esc C_REPO 220 200 0;  esc C_BRANCH 0 190 190; esc C_COST 220 200 0
  esc C_ADD 0 200 80;    esc C_DEL 220 40 20;    esc C_MODEL 200 90 200
  esc C_EMPTY 60 60 60
else
  # Okabe-Ito adjacent, brightened for dark backgrounds
  LO=(86 148 222); MID=(176 110 200); HI=(232 86 74)
  esc C_REPO 196 128 40; esc C_BRANCH 48 152 172; esc C_COST 196 128 40
  esc C_ADD 48 152 172;  esc C_DEL 232 86 74;     esc C_MODEL 176 110 200
  esc C_EMPTY 128 128 128
fi
esc C_DIM 128 128 128

# Apply whatever the palette file defined, over the built-ins. Each is optional,
# so a partial file overrides only the segments it names.
[ "${#PAL_LO[@]:-0}"  = 3 ] && LO=("${PAL_LO[@]}")
[ "${#PAL_MID[@]:-0}" = 3 ] && MID=("${PAL_MID[@]}")
[ "${#PAL_HI[@]:-0}"  = 3 ] && HI=("${PAL_HI[@]}")
[ "${#PAL_REPO[@]:-0}"   = 3 ] && esc C_REPO   "${PAL_REPO[@]}"
[ "${#PAL_BRANCH[@]:-0}" = 3 ] && esc C_BRANCH "${PAL_BRANCH[@]}"
[ "${#PAL_COST[@]:-0}"   = 3 ] && esc C_COST   "${PAL_COST[@]}"
[ "${#PAL_ADD[@]:-0}"    = 3 ] && esc C_ADD    "${PAL_ADD[@]}"
[ "${#PAL_DEL[@]:-0}"    = 3 ] && esc C_DEL    "${PAL_DEL[@]}"
[ "${#PAL_MODEL[@]:-0}"  = 3 ] && esc C_MODEL  "${PAL_MODEL[@]}"
[ "${#PAL_EMPTY[@]:-0}"  = 3 ] && esc C_EMPTY  "${PAL_EMPTY[@]}"
[ "${#PAL_DIM[@]:-0}"    = 3 ] && esc C_DIM    "${PAL_DIM[@]}"

# Interpolate LO → MID → HI at position 0..100 into $GRAD
grad() {
  local p=$1 a
  [ "$p" -gt 100 ] && p=100
  [ "$p" -lt 0 ] && p=0
  if [ "$p" -le 50 ]; then
    R=$(( LO[0] + (MID[0] - LO[0]) * p / 50 ))
    G=$(( LO[1] + (MID[1] - LO[1]) * p / 50 ))
    B=$(( LO[2] + (MID[2] - LO[2]) * p / 50 ))
  else
    a=$(( p - 50 ))
    R=$(( MID[0] + (HI[0] - MID[0]) * a / 50 ))
    G=$(( MID[1] + (HI[1] - MID[1]) * a / 50 ))
    B=$(( MID[2] + (HI[2] - MID[2]) * a / 50 ))
  fi
  printf -v GRAD '\033[38;2;%d;%d;%dm' "$R" "$G" "$B"
}

trunc() { # $1 string, $2 max columns → $TR
  if [ "${#1}" -le "$2" ]; then TR="$1"; else TR="${1:0:$(( $2 - 1 ))}…"; fi
}

# ── Git. One rev-parse yields both toplevel and ref; the extra call for a
# short SHA only happens on a detached HEAD, which matters here because
# submodule work in this repo routinely detaches. ──
branch=""
repo=""
if [ -n "$cwd" ] && [ -d "$cwd" ]; then
  gi=$(git -C "$cwd" --no-optional-locks rev-parse --show-toplevel --abbrev-ref HEAD 2>/dev/null)
  if [ -n "$gi" ]; then
    top=${gi%%$'\n'*}
    ref=${gi##*$'\n'}
    repo=${top##*/}
    if [ "$ref" = "HEAD" ]; then
      sha=$(git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
      [ -n "$sha" ] && branch="@$sha"          # detached
    elif [ "$ref" != "$top" ]; then
      branch="$ref"                            # equal means HEAD is unborn
    fi
  fi
fi

# ── Values ──
used_int=""
[ -n "$used" ] && printf -v used_int '%.0f' "$used"
printf -v cost_str '$%.2f' "$cost"
lim5h_int=""; lim7d_int=""
[ -n "$lim5h" ] && printf -v lim5h_int '%.0f' "$lim5h"
[ -n "$lim7d" ] && printf -v lim7d_int '%.0f' "$lim7d"

mark=""
if [ -n "$used_int" ]; then
  if   [ "$used_int" -ge 90 ]; then mark='!! '
  elif [ "$used_int" -ge 70 ]; then mark='! '
  fi
fi

# Model without its parenthetical, e.g. "Opus 5 (1M context)" → "Opus 5"
model_short="${model%% (*}"

# ── Bar width by available columns. Emoji count as 2 display columns. ──
if   [ "$avail" -ge 108 ]; then barw=20
elif [ "$avail" -ge 90 ];  then barw=14
elif [ "$avail" -ge 72 ];  then barw=10
elif [ "$avail" -ge 54 ];  then barw=6
else                            barw=0
fi
barw_max=$barw

# ── Segments ──
show_repo=1; show_branch=1; show_cost=1; show_vel=1; show_lim=1; show_model=1
branch_max=64
[ -n "$repo" ] || show_repo=0
[ -n "$branch" ] || show_branch=0
[ -n "$lim5h_int$lim7d_int" ] || show_lim=0

lim_txt=""
[ -n "$lim5h_int" ] && lim_txt="5h ${lim5h_int}%"
[ -n "$lim7d_int" ] && lim_txt="${lim_txt:+$lim_txt }7d ${lim7d_int}%"

recalc() { # → $TOTAL
  local n=0 t=0 b
  if [ "$show_repo" = 1 ]; then t=$(( t + ${#repo} )); n=$(( n + 1 )); fi
  if [ "$show_branch" = 1 ]; then
    b=${#branch}; [ "$b" -gt "$branch_max" ] && b=$branch_max
    t=$(( t + b + 2 )); n=$(( n + 1 ))   # "(branch)"
  fi
  # context: marker + bar + space + "NN%"
  if [ -n "$used_int" ]; then t=$(( t + ${#mark} + ${#used_int} + 1 )); else t=$(( t + 3 )); fi
  [ "$barw" -gt 0 ] && t=$(( t + barw + 1 ))
  n=$(( n + 1 ))
  if [ "$show_cost" = 1 ]; then t=$(( t + ${#cost_str} )); n=$(( n + 1 )); fi
  if [ "$show_vel" = 1 ]; then t=$(( t + ${#lines_add} + ${#lines_del} + 3 )); n=$(( n + 1 )); fi
  if [ "$show_lim" = 1 ]; then t=$(( t + ${#lim_txt} )); n=$(( n + 1 )); fi
  if [ "$show_model" = 1 ]; then t=$(( t + ${#model} )); n=$(( n + 1 )); fi
  TOTAL=$(( t + (n - 1) * 3 ))           # " | " separators
}

# ── Degrade until it fits. Order = least valuable sacrificed first. ──
recalc
if [ "$TOTAL" -gt "$avail" ] && [ "$model_short" != "$model" ]; then
  model="$model_short"; recalc
fi
for step in branch16 vel cost repo lim branchfit branch bar model12 model6 model; do
  [ "$TOTAL" -le "$avail" ] && break
  case "$step" in
    branch16) branch_max=16 ;;
    vel)      show_vel=0 ;;
    cost)     show_cost=0 ;;
    repo)     show_repo=0 ;;
    lim)      show_lim=0 ;;
    branchfit)
      # Shrink the branch by exactly the overflow rather than dropping it —
      # a stub like "tab-b…" beats leaving the columns empty.
      b=${#branch}; [ "$b" -gt "$branch_max" ] && b=$branch_max
      b=$(( b - (TOTAL - avail) ))
      if [ "$b" -ge 4 ]; then branch_max=$b; else show_branch=0; fi
      ;;
    branch)   show_branch=0 ;;
    bar)      barw=0 ;;
    model12)  trunc "$model" 12; model="$TR" ;;
    model6)   trunc "$model" 6; model="$TR" ;;
    model)    show_model=0 ;;   # floor: context emoji + percentage only
  esac
  recalc
done

# Grow the bar back into leftover slack, but never past the tier for this
# width. Uncapped growth is non-monotonic — dropping a segment frees space, so
# narrowing the window could make the bar jump *bigger*, which reads as a bug.
# The cap trades a few unused columns at narrow widths for a bar that only ever
# shrinks as the window shrinks.
while [ "$barw" -lt "$barw_max" ]; do
  saved=$barw
  barw=$(( barw == 0 ? 6 : barw + 2 ))
  recalc
  if [ "$TOTAL" -gt "$avail" ]; then barw=$saved; recalc; break; fi
done

# ── Render ──
bar=""
if [ "$barw" -gt 0 ]; then
  if [ -n "$used_int" ]; then filled=$(( (used_int * barw + 50) / 100 )); else filled=0; fi
  for (( i = 0; i < barw; i++ )); do
    if [ "$i" -lt "$filled" ]; then
      grad $(( i * 100 / (barw - 1) ))
      bar+="${GRAD}█"
    else
      bar+="${C_EMPTY}░"
    fi
  done
  bar+="${RESET} "
fi

if [ -n "$used_int" ]; then
  grad "$used_int"
  ctx="${GRAD}${mark}${bar}${GRAD}${used_int}%${RESET}"
else
  ctx="${bar}${C_EMPTY}--%${RESET}"
fi

SEP="${C_DIM} | ${RESET}"
out=""
add() { out="${out:+$out$SEP}$1"; }

[ "$show_repo" = 1 ] && add "${BOLD}${C_REPO}${repo}${RESET}"
if [ "$show_branch" = 1 ]; then
  trunc "$branch" "$branch_max"
  add "${BOLD}${C_BRANCH}(${TR})${RESET}"
fi
add "$ctx"
[ "$show_cost" = 1 ] && add "${C_COST}${cost_str}${RESET}"
[ "$show_vel" = 1 ] && add "${C_ADD}+${lines_add}${RESET} ${C_DEL}-${lines_del}${RESET}"

if [ "$show_lim" = 1 ]; then
  lim_out=""
  if [ -n "$lim5h_int" ]; then
    grad "$lim5h_int"; lim_out="${C_DIM}5h ${GRAD}${lim5h_int}%${RESET}"
  fi
  if [ -n "$lim7d_int" ]; then
    grad "$lim7d_int"; lim_out="${lim_out:+$lim_out }${C_DIM}7d ${GRAD}${lim7d_int}%${RESET}"
  fi
  add "$lim_out"
fi

[ "$show_model" = 1 ] && add "${C_MODEL}${model}${RESET}"

# %s, not %b: $out already holds real escape bytes, and a branch or model name
# containing a backslash must not be reinterpreted.
printf '%s' "$out"
