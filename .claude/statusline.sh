#!/usr/bin/env bash
# Single-row Claude Code statusline (omp-style, high contrast)
#
# Shrink-to-fit:
#   1. Prefer ALL components
#   2. Shrink the context bar first
#   3. Then shorten path
#   4. Last resort: drop @agent → dirty → branch
#
# Order:
#   VIM ▶ [Model] ▶ effort ▶ 5h/7d ▶ $cost ▶ ⏱ ▶ cache ▶ @agent ▶ /path ▶ branch ▶ dirty ▶ ████░░░░ 42%
#
# Trailing unit (always last):  ████░░░░ 42%
# Claude clips from the RIGHT — keep the line short enough that % survives.

set -euo pipefail

input=$(cat)

# --- palette ---
BG=$'\033[48;5;233m'
FG=$'\033[39m'
BOLD=$'\033[1m'
RESET=$'\033[0m'
SEP_C=$'\033[38;5;236m'
VIM_INS=$'\033[38;5;48m'
VIM_NRM=$'\033[38;5;39m'
VIM_VIS=$'\033[38;5;213m'
MODEL_C=$'\033[38;5;204m'
EFFORT_C=$'\033[38;5;141m'   # soft violet
AGENT_C=$'\033[38;5;214m'
PATH_C=$'\033[38;5;255m'
BRANCH_C=$'\033[38;5;48m'
DIRTY_C=$'\033[38;5;203m'    # rose for dirty counts
COST_C=$'\033[38;5;220m'
LIMIT_C=$'\033[38;5;209m'
DUR_C=$'\033[38;5;117m'      # sky duration
CACHE_WARM_C=$'\033[38;5;48m'
CACHE_COLD_C=$'\033[38;5;245m'
BAR_OK=$'\033[38;5;48m'
BAR_WARN=$'\033[38;5;220m'
BAR_CRIT=$'\033[38;5;196m'
BAR_EMPTY=$'\033[38;5;238m'
PCT_C=$'\033[38;5;255m'

# --- fields (aliases for schema drift) ---
MODEL=$(jq -r '.model.display_name // .model.displayName // "Claude"' <<<"$input")
DIR=$(jq -r '.workspace.current_dir // .cwd // ""' <<<"$input")
AGENT=$(jq -r '.agent.name // empty' <<<"$input")
SESSION_ID=$(jq -r '.session_id // "default"' <<<"$input")
PCT=$(jq -r '
  .context_window.used_percentage
  // .context_window.usedPercentage
  // 0
' <<<"$input" | cut -d. -f1)
COST=$(jq -r '.cost.total_cost_usd // .cost.totalCostUsd // 0' <<<"$input")
DURATION_MS=$(jq -r '.cost.total_duration_ms // .cost.totalDurationMs // 0' <<<"$input")
VIM=$(jq -r '.vim.mode // empty' <<<"$input")
EFFORT=$(jq -r '.effort.level // empty' <<<"$input")
FIVE_H=$(jq -r '
  .rate_limits.five_hour.used_percentage
  // .rate_limits.five_hour.usedPercentage
  // empty
' <<<"$input")
WEEK=$(jq -r '
  .rate_limits.seven_day.used_percentage
  // .rate_limits.seven_day.usedPercentage
  // empty
' <<<"$input")
# NOTE: jq `//` treats false as missing — use explicit null checks for booleans
CACHE_WARM=$(jq -r 'if (.prompt_cache.warm | type) == "boolean" then (.prompt_cache.warm | tostring) else empty end' <<<"$input")
CACHE_HIT=$(jq -r '
  if (.prompt_cache.hit_ratio | type) == "number" then .prompt_cache.hit_ratio
  elif (.prompt_cache.hitRatio | type) == "number" then .prompt_cache.hitRatio
  else empty end
' <<<"$input")

# --- git branch + dirty (session-cached): branch|staged|unstaged ---
CACHE_FILE="/tmp/claude-statusline-git-${SESSION_ID}"
CACHE_MAX_AGE=5
BRANCH=""
STAGED=0
UNSTAGED=0

cache_is_stale() {
  [[ ! -f "$CACHE_FILE" ]] || \
  [[ $(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0))) -gt $CACHE_MAX_AGE ]]
}

if [[ -n "$DIR" ]]; then
  if cache_is_stale; then
    if git -C "$DIR" rev-parse --git-dir >/dev/null 2>&1; then
      b=$(git -C "$DIR" branch --show-current 2>/dev/null || true)
      # numstat lines = file counts (fast enough when cached 5s)
      s=$(git -C "$DIR" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
      u=$(git -C "$DIR" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
      printf '%s|%s|%s\n' "${b:-}" "${s:-0}" "${u:-0}" >"$CACHE_FILE"
    else
      # keep 3-field shape: branch|staged|unstaged
      echo "|0|0" >"$CACHE_FILE"
    fi
  fi
  IFS='|' read -r BRANCH STAGED UNSTAGED <"$CACHE_FILE" || true
  STAGED=${STAGED:-0}
  UNSTAGED=${UNSTAGED:-0}
fi

# --- colors ---
if (( PCT >= 90 )); then
  BAR_FILL_C="$BAR_CRIT"
elif (( PCT >= 70 )); then
  BAR_FILL_C="$BAR_WARN"
else
  BAR_FILL_C="$BAR_OK"
fi

VIM_C="$VIM_NRM"
case "$VIM" in
  INSERT) VIM_C="$VIM_INS" ;;
  NORMAL) VIM_C="$VIM_NRM" ;;
  VISUAL|VISUAL\ LINE|V-BLOCK|REPLACE) VIM_C="$VIM_VIS" ;;
esac

COST_FMT=$(printf '$%.2f' "$COST")
LIMITS=""
[[ -n "$FIVE_H" ]] && LIMITS+="5h:$(printf '%.0f' "$FIVE_H")%"
[[ -n "$WEEK" ]] && LIMITS+="${LIMITS:+ }7d:$(printf '%.0f' "$WEEK")%"

# Session duration: 45s / 12m / 1h23m
DUR_TXT=""
if [[ -n "$DURATION_MS" && "$DURATION_MS" != "0" && "$DURATION_MS" != "null" ]]; then
  DUR_S=$((DURATION_MS / 1000))
  if (( DUR_S < 60 )); then
    DUR_TXT="${DUR_S}s"
  elif (( DUR_S < 3600 )); then
    DUR_TXT="$((DUR_S / 60))m"
  else
    DUR_TXT="$((DUR_S / 3600))h$(( (DUR_S % 3600) / 60 ))m"
  fi
fi

# Prompt-cache: ⚡91% warm / ❄ cold / hidden until first API response
CACHE_TXT=""
if [[ "$CACHE_WARM" == "true" ]]; then
  if [[ -n "$CACHE_HIT" && "$CACHE_HIT" != "null" ]]; then
    HIT_PCT=$(awk -v h="$CACHE_HIT" 'BEGIN { printf "%.0f", h * 100 }')
    CACHE_TXT="⚡${HIT_PCT}%"
  else
    CACHE_TXT="⚡"
  fi
elif [[ "$CACHE_WARM" == "false" ]]; then
  CACHE_TXT="❄"
fi

# Git dirty: +staged ~unstaged (hidden when clean)
DIRTY_TXT=""
if (( STAGED > 0 || UNSTAGED > 0 )); then
  (( STAGED > 0 )) && DIRTY_TXT+="+${STAGED}"
  (( UNSTAGED > 0 )) && DIRTY_TXT+="${DIRTY_TXT:+ }~${UNSTAGED}"
fi

SEP=" ${SEP_C}▶${RESET} "
SEP_PLAIN=" ▶ "
MIN_BAR=4
# Claude chrome / right-edge clip budget. Keep this generous.
RIGHT_MARGIN=24

vis_len() {
  # Character width (not bytes) — strip ANSI first
  local s
  s=$(sed $'s/\x1b\\[[0-9;]*m//g' <<<"$1")
  printf '%s' "$s" | wc -m | tr -d ' '
}

render() {
  local out="" first=1 seg
  for seg in "$@"; do
    [[ -z "$seg" ]] && continue
    if (( first )); then
      out="$seg"
      first=0
    else
      out+="${SEP}${seg}"
    fi
  done
  printf '%s' "$out"
}

render_w() {
  vis_len "$(render "$@")"
}

shorten_path() {
  local budget=$1
  local base="${DIR##*/}"
  if (( budget <= 0 )) || [[ -z "$DIR" ]]; then
    printf ''
    return
  fi
  if (( ${#DIR} <= budget )); then
    printf '%s' "$DIR"
  elif (( budget >= ${#base} + 2 )); then
    printf '…%s' "${DIR:$(( ${#DIR} - budget + 1 ))}"
  elif (( budget >= ${#base} )); then
    printf '%s' "$base"
  elif (( budget >= 2 )); then
    printf '…%s' "${base:$(( ${#base} - budget + 1 ))}"
  else
    printf ''
  fi
}

make_bar() {
  local width=$1
  (( width < 1 )) && width=1
  local filled=$((PCT * width / 100))
  (( filled > width )) && filled=$width
  (( filled < 0 )) && filled=0
  local empty=$((width - filled))
  local fill pad
  printf -v fill "%${filled}s"
  printf -v pad "%${empty}s"
  printf '%s' "${BAR_FILL_C}${fill// /█}${BAR_EMPTY}${pad// /░}${RESET}"
}

# Center text inside a fixed-width cell (left/right pad)
center_in() {
  local text="$1" width="$2"
  local len=${#text}
  local pad=$((width - len))
  if (( pad <= 0 )); then
    printf '%s' "${text:0:width}"
    return
  fi
  local left=$((pad / 2))
  local right=$((pad - left))
  printf '%*s%s%*s' "$left" '' "$text" "$right" ''
}

# --- segments ---
# Black BG only on the VIM pill. Everything else (incl. separators) stays clear.
VIM_CELL_W=10
SEG_VIM=""
if [[ -n "$VIM" ]]; then
  VIM_PADDED=$(center_in "$VIM" "$VIM_CELL_W")
  SEG_VIM="${BG}${BOLD}${VIM_C}${VIM_PADDED}${RESET}"
fi
SEG_MODEL="${BOLD}${MODEL_C}[${MODEL}]${RESET}"
SEG_EFFORT=""
[[ -n "$EFFORT" ]] && SEG_EFFORT="${BOLD}${EFFORT_C}${EFFORT}${RESET}"
SEG_LIMITS=""
[[ -n "$LIMITS" ]] && SEG_LIMITS="${BOLD}${LIMIT_C}${LIMITS}${RESET}"
SEG_COST="${BOLD}${COST_C}${COST_FMT}${RESET}"
SEG_DUR=""
[[ -n "$DUR_TXT" ]] && SEG_DUR="${BOLD}${DUR_C}${DUR_TXT}${RESET}"
SEG_CACHE=""
if [[ -n "$CACHE_TXT" ]]; then
  if [[ "$CACHE_WARM" == "true" ]]; then
    SEG_CACHE="${BOLD}${CACHE_WARM_C}${CACHE_TXT}${RESET}"
  else
    SEG_CACHE="${BOLD}${CACHE_COLD_C}${CACHE_TXT}${RESET}"
  fi
fi
SEG_AGENT=""
[[ -n "$AGENT" ]] && SEG_AGENT="${BOLD}${AGENT_C}@${AGENT}${RESET}"
SEG_BRANCH=""
[[ -n "$BRANCH" ]] && SEG_BRANCH="${BOLD}${BRANCH_C}${BRANCH}${RESET}"
SEG_DIRTY=""
[[ -n "$DIRTY_TXT" ]] && SEG_DIRTY="${BOLD}${DIRTY_C}${DIRTY_TXT}${RESET}"
PCT_LABEL="${PCT}%"
SEG_PCT="${BOLD}${PCT_C}${PCT_LABEL}${RESET}"

TERM_COLS=${COLUMNS:-120}
# Hard cap: never target more than TERM_COLS - RIGHT_MARGIN visible chars
COLS=$((TERM_COLS - RIGHT_MARGIN - 2))
(( COLS < 28 )) && COLS=28
SEP_W=$(vis_len "$SEP_PLAIN")
PCT_W=${#PCT_LABEL}

SHOW_AGENT=1
SHOW_BRANCH=1
SHOW_DIRTY=1
DISPLAY_DIR="$DIR"
BAR_W=$MIN_BAR

# Keep components; leftover goes to the bar. Always reserve " NN%" AFTER the bar.
# Drop order when tight: agent → dirty → branch → shorten path → shrink bar
fit() {
  # $1 show_agent $2 show_branch $3 show_dirty $4 path $5 min_bar
  local ia=$1 ib=$2 id=$3 path="$4" minb=$5
  local parts=(
    "$SEG_VIM"
    "$SEG_MODEL"
    "$SEG_EFFORT"
    "$SEG_LIMITS"
    "$SEG_COST"
    "$SEG_DUR"
    "$SEG_CACHE"
  )
  (( ia )) && [[ -n "$SEG_AGENT" ]] && parts+=("$SEG_AGENT")
  [[ -n "$path" ]] && parts+=("${PATH_C}${path}${RESET}")
  (( ib )) && [[ -n "$SEG_BRANCH" ]] && parts+=("$SEG_BRANCH")
  (( id )) && [[ -n "$SEG_DIRTY" ]] && parts+=("$SEG_DIRTY")

  local fixed_w bar_w
  fixed_w=$(render_w "${parts[@]}")
  # PREFIX ▶ BAR SPACE PCT
  bar_w=$((COLS - fixed_w - SEP_W - 1 - PCT_W))
  if (( bar_w >= minb )); then
    SHOW_AGENT=$ia
    SHOW_BRANCH=$ib
    SHOW_DIRTY=$id
    DISPLAY_DIR="$path"
    BAR_W=$bar_w
    return 0
  fi
  return 1
}

try_path_budgets() {
  # $1 ia $2 ib $3 id
  local ia=$1 ib=$2 id=$3 budget p
  for budget in ${#DIR} 40 30 24 20 16 12 10 8 6 4; do
    (( budget > ${#DIR} )) && continue
    p=$(shorten_path "$budget")
    [[ -z "$p" && "$budget" -lt ${#DIR} ]] && continue
    if fit "$ia" "$ib" "$id" "$p" 1; then
      return 0
    fi
  done
  return 1
}

if fit 1 1 1 "$DIR" 1; then
  :
elif [[ -n "$DIR" ]]; then
  fitted=0
  # Full-ish layouts, shortening path first
  if try_path_budgets 1 1 1; then fitted=1
  elif try_path_budgets 0 1 1; then fitted=1          # drop agent
  elif try_path_budgets 0 1 0; then fitted=1          # drop dirty
  elif try_path_budgets 0 0 0; then fitted=1          # drop branch
  fi
  if (( ! fitted )); then
    fit 0 0 0 "" 1 || {
      SHOW_AGENT=0
      SHOW_BRANCH=0
      SHOW_DIRTY=0
      DISPLAY_DIR=""
      fixed_w=$(render_w \
        "$SEG_VIM" "$SEG_MODEL" "$SEG_EFFORT" "$SEG_LIMITS" \
        "$SEG_COST" "$SEG_DUR" "$SEG_CACHE")
      BAR_W=$((COLS - fixed_w - SEP_W - 1 - PCT_W))
      (( BAR_W < 1 )) && BAR_W=1
    }
  fi
else
  if ! fit 1 1 1 "" 1; then
    if ! fit 0 1 1 "" 1; then
      if ! fit 0 1 0 "" 1; then
        if ! fit 0 0 0 "" 1; then
          SHOW_AGENT=0
          SHOW_BRANCH=0
          SHOW_DIRTY=0
          DISPLAY_DIR=""
          fixed_w=$(render_w \
            "$SEG_VIM" "$SEG_MODEL" "$SEG_EFFORT" "$SEG_LIMITS" \
            "$SEG_COST" "$SEG_DUR" "$SEG_CACHE")
          BAR_W=$((COLS - fixed_w - SEP_W - 1 - PCT_W))
          (( BAR_W < 1 )) && BAR_W=1
        fi
      fi
    fi
  fi
fi

(( BAR_W < 1 )) && BAR_W=1

OUT_AGENT=""
OUT_PATH=""
OUT_BRANCH=""
OUT_DIRTY=""
(( SHOW_AGENT )) && [[ -n "$SEG_AGENT" ]] && OUT_AGENT="$SEG_AGENT"
[[ -n "$DISPLAY_DIR" ]] && OUT_PATH="${PATH_C}${DISPLAY_DIR}${RESET}"
(( SHOW_BRANCH )) && [[ -n "$SEG_BRANCH" ]] && OUT_BRANCH="$SEG_BRANCH"
(( SHOW_DIRTY )) && [[ -n "$SEG_DIRTY" ]] && OUT_DIRTY="$SEG_DIRTY"

# Final safety: rebuild bar so full visible line never exceeds TERM_COLS - RIGHT_MARGIN
MAX_VISIBLE=$((TERM_COLS - RIGHT_MARGIN))
(( MAX_VISIBLE < 30 )) && MAX_VISIBLE=30

while true; do
  BAR=$(make_bar "$BAR_W")
  MID="${BAR} ${SEG_PCT}"
  LINE=$(render \
    "$SEG_VIM" \
    "$SEG_MODEL" \
    "$SEG_EFFORT" \
    "$SEG_LIMITS" \
    "$SEG_COST" \
    "$SEG_DUR" \
    "$SEG_CACHE" \
    "$OUT_AGENT" \
    "$OUT_PATH" \
    "$OUT_BRANCH" \
    "$OUT_DIRTY" \
    "$MID")
  VIS=$(vis_len "$LINE")
  if (( VIS <= MAX_VISIBLE || BAR_W <= 1 )); then
    break
  fi
  # Shrink bar until we fit (protects trailing %)
  BAR_W=$((BAR_W - (VIS - MAX_VISIBLE)))
  (( BAR_W < 1 )) && BAR_W=1
done

printf '%b\n' "${LINE}${RESET}"
