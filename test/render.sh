#!/usr/bin/env bash
# Test the status line renders within its width budget at every terminal size,
# degrades monotonically, and survives degenerate payloads.
#
#   ./test/render.sh          # assert only
#   ./test/render.sh -v       # also print each rendered line
#
# Requires python3 (to measure display width with ANSI stripped).
set -uo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SL="$here/../statusline.sh"
MEASURE="$here/measure.py"
verbose=0
[ "${1:-}" = "-v" ] && verbose=1

fail=0
pass() { printf '  ok    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }

strip() { python3 -c 'import re,sys; sys.stdout.write(re.sub(r"\x1b\[[0-9;]*m","",sys.stdin.read()))'; }

payload() { # $1 = used_percentage
  printf '{"model":{"display_name":"Opus 5 (1M context)"},
           "workspace":{"current_dir":"%s"},
           "context_window":{"used_percentage":%s},
           "cost":{"total_cost_usd":0.4712,"total_lines_added":156,"total_lines_removed":23},
           "rate_limits":{"five_hour":{"used_percentage":23.5},
                          "seven_day":{"used_percentage":41.2}}}' "$PWD" "$1"
}

# Mirror of the script's budget rule: COLUMNS minus a reserve for the
# notification area, where the reserve never exceeds a quarter of the width.
budget_for() {
  local c=$1 r=14 q=$(( $1 / 4 ))
  [ "$r" -gt "$q" ] && r=$q
  local b=$(( c - r ))
  [ "$b" -lt 12 ] && b=12
  echo "$b"
}

echo "width budget + monotonic degradation"
prev_bar=999
for c in 200 160 140 130 120 115 110 105 100 95 90 85 80 75 70 65 60 55 50 45 40 35 30 25 20 16 10; do
  out=$(payload 47 | CLAUDE_STATUSLINE_COLUMNS=$c "$SL")
  w=$(printf '%s' "$out" | python3 "$MEASURE")
  bar=$(printf '%s' "$out" | strip | tr -cd '█░' | wc -c | tr -d ' ')
  b=$(budget_for "$c")
  [ "$w" -gt "$b" ] && bad "cols=$c overflows: $w > $b"
  [ "$bar" -gt "$prev_bar" ] && bad "cols=$c bar grew while narrowing ($prev_bar -> $bar)"
  prev_bar=$bar
  [ "$verbose" = 1 ] && printf '  %4s cols (budget %3s, used %3s)  %s\n' \
    "$c" "$b" "$w" "$(printf '%s' "$out" | strip)"
done
[ "$fail" = 0 ] && pass "27 widths within budget, bar never grows as width shrinks"

echo "severity marker"
# Deliberately omit cwd so no repo/branch segments precede the context one —
# then the first token of the line is the marker (or the bar when there is
# none), regardless of which other segments the layout kept.
for spec in "8:" "47:" "69:" "70:!" "78:!" "89:!" "90:!!" "95:!!"; do
  pct=${spec%%:*}; want=${spec#*:}
  got=$(printf '{"model":{"display_name":"Opus 5"},"context_window":{"used_percentage":%s}}' "$pct" \
        | "$SL" | strip)
  got=${got%% *}
  case "$want" in
    '')  case "$got" in
           '!'*) bad "$pct% should have no marker, got '$got'" ;;
           *)    pass "$pct% -> no marker" ;;
         esac ;;
    *)   if [ "$got" = "$want" ]; then pass "$pct% -> $want"
         else bad "$pct% should be '$want', got '$got'"; fi ;;
  esac
done

echo "degenerate payloads"
check() { # $1 label, $2 json, $3 substring that must appear
  local out
  out=$(printf '%s' "$2" | "$SL" | strip)
  case "$out" in
    *"$3"*) pass "$1" ;;
    *)      bad "$1 (got: $out)" ;;
  esac
}
check "no rate_limits"  '{"model":{"display_name":"Opus 5"},"context_window":{"used_percentage":40}}' '40%'
check "5h limit only"   '{"model":{"display_name":"Opus 5"},"context_window":{"used_percentage":12},"rate_limits":{"five_hour":{"used_percentage":88}}}' '5h 88%'
check "null context"    '{"model":{"display_name":"Opus 5"},"context_window":{"used_percentage":null}}' '--%'
check "empty object"    '{}' 'Unknown'
check "non-git cwd"     '{"model":{"display_name":"Opus 5"},"workspace":{"current_dir":"/usr"}}' 'Opus 5'

echo "malformed input stays silent"
for junk in 'not json' '' '{"unterminated":'; do
  out=$(printf '%s' "$junk" | "$SL" 2>/dev/null); rc=$?
  if [ -n "$out" ]; then bad "junk input produced output: $out"
  elif [ "$rc" != 0 ]; then bad "junk input exited $rc (should be 0)"
  else pass "silent on: ${junk:-<empty>}"
  fi
done

echo
if [ "$fail" = 0 ]; then echo "PASS"; else echo "FAIL"; fi
exit "$fail"
