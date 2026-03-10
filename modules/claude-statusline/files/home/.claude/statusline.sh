#!/usr/bin/env bash
# Claude Code statusline - bash + jq

R=$'\e[0m'
DIM=$'\e[2m'
CYAN=$'\e[38;5;117m'
ACCENT=$'\e[38;5;222m'
SAFE=$'\e[38;5;151m'
WARN=$'\e[38;5;222m'
DANGER=$'\e[38;5;210m'
SEP=" ${DIM}│${R} "

input=$(cat)
[[ -z "$input" ]] && { printf '⚠️\n'; exit 0; }

# Parse context window fields in one jq call
read -r size input_tokens cost cwd_raw < <(printf '%s' "$input" | jq -r '
  (.context_window.context_window_size // 200000) as $size |
  ((.context_window.current_usage // {}) |
    ((.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0))
  ) as $tok |
  (.cost.total_cost_usd // 0) as $cost |
  (.cwd // "") as $cwd |
  "\($size) \($tok) \($cost) \($cwd)"
')
project=${cwd_raw:+$(basename "$cwd_raw")}
project=${project:-$(basename "$PWD")}

# Percentage (clamped 0-100)
pct=$(awk "BEGIN{p=$input_tokens/$size*100; if(p>100)p=100; printf \"%.0f\",p}")

color_pct() {
  local p=$1
  if   (( p <= 50 )); then printf '%s' "$SAFE"
  elif (( p <= 80 )); then printf '%s' "$WARN"
  else                     printf '%s' "$DANGER"
  fi
}

BAR_SIZE=5

build_bar() {
  local p=$1
  local filled empty c bar=""
  filled=$(awk "BEGIN{f=int($p/100*$BAR_SIZE+0.5); if(f>$BAR_SIZE)f=$BAR_SIZE; print f}")
  empty=$(( BAR_SIZE - filled ))
  c=$(color_pct "$p")
  printf -v bar '%0.s█' $(seq 1 $filled) 2>/dev/null
  local e; printf -v e '%0.s░' $(seq 1 $empty) 2>/dev/null
  printf '%s%s%s%s' "$c" "$bar" "$e" "$R"
}

fmt_time() {
  local reset_epoch now diff m d h mins
  reset_epoch=$(date -d "$1" +%s 2>/dev/null) || return
  now=$(date +%s)
  diff=$(( reset_epoch - now ))
  (( diff <= 0 )) && { printf '0m'; return; }
  m=$(( diff / 60 ))
  d=$(( m / 1440 )); h=$(( (m % 1440) / 60 )); mins=$(( m % 60 ))
  if   (( d > 0 )); then printf '%dd' "$d"
  elif (( h > 0 )); then printf '%dh%dm' "$h" "$mins"
  else                   printf '%dm' "$mins"
  fi
}

# Read OAuth token
CREDS="$HOME/.claude/.credentials.json"
token=""
[[ -f "$CREDS" ]] && token=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS" 2>/dev/null)

# Fetch/cache rate limits (TTL 5 min = 300s)
limits_json=""
if [[ -n "$token" ]]; then
  CACHE_DIR="$HOME/.cache/claude-statusline"
  hash=$(printf '%s' "$token" | sha256sum | cut -c1-16)
  cache_file="$CACHE_DIR/cache-${hash}.json"

  if [[ -f "$cache_file" ]]; then
    cache_ts=$(jq -r '.timestamp // 0' "$cache_file" 2>/dev/null)
    now_s=$(date +%s)
    if (( now_s - cache_ts < 300 )); then
      limits_json=$(jq '.data' "$cache_file" 2>/dev/null)
    fi
  fi

  if [[ -z "$limits_json" || "$limits_json" == "null" ]]; then
    response=$(curl -sf --max-time 5 \
      -H "Authorization: Bearer $token" \
      -H "anthropic-beta: oauth-2025-04-20" \
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
    if [[ -n "$response" ]]; then
      limits_json=$(printf '%s' "$response" | jq '{five_hour: .five_hour, seven_day: .seven_day}')
      mkdir -p "$CACHE_DIR"
      now_s=$(date +%s)
      printf '{"data":%s,"timestamp":%d}\n' "$limits_json" "$now_s" > "$cache_file"
      chmod 600 "$cache_file"
    fi
  fi
fi

# Assemble parts
bar=$(build_bar "$pct")
cost_fmt=$(printf '%.2f' "$cost")

parts=("${CYAN}${project}${R} $bar" "${ACCENT}\$${cost_fmt}${R}")

# Rate limit segments
if [[ -n "$limits_json" && "$limits_json" != "null" ]]; then
  for key in "five_hour" "seven_day"; do
    util=$(printf '%s' "$limits_json" | jq -r ".${key}.utilization // empty" 2>/dev/null)
    [[ -z "$util" ]] && continue
    u=$(printf '%.0f' "$util")
    resets_at=$(printf '%s' "$limits_json" | jq -r ".${key}.resets_at // empty" 2>/dev/null)
    lc=$(color_pct "$u")
    s="${lc}${u}%${R}"
    if [[ -n "$resets_at" ]]; then
      t=$(fmt_time "$resets_at")
      [[ -n "$t" ]] && s+=" ${DIM}(${t})${R}"
    fi
    parts+=("$s")
  done
fi

# Join with separator
out=""
for (( i=0; i<${#parts[@]}; i++ )); do
  (( i > 0 )) && out+="$SEP"
  out+="${parts[$i]}"
done
printf '%s\n' "$out"
