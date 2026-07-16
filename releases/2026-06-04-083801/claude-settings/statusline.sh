#!/bin/bash
# Claude Code Native Statusline
# Receives JSON context from Claude Code via stdin.
# No external API calls - uses native cost/token fields provided by Claude Code.

CACHE_DIR="${TMPDIR:-/tmp}/claude-statusline"
GIT_CACHE_FILE="$CACHE_DIR/git_branch_cache"
GIT_CACHE_TTL=300  # 5 minutes

mkdir -p "$CACHE_DIR" 2>/dev/null

INPUT=$(cat)

# ---------------------------------------------------------------------------
# Parse JSON fields (portable grep/sed, no jq required)
# ---------------------------------------------------------------------------
parse_context() {
    local json="$1"

    # Workspace / git
    CWD=$(echo "$json" | grep -o '"current_dir"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)
    [ -z "$CWD" ] && CWD=$(echo "$json" | grep -o '"cwd"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)
    GIT_NUM_FILES=$(echo "$json" | grep -o '"gitNumStagedOrUnstagedFilesChanged"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)

    # Model
    MODEL=$(echo "$json" | grep -o '"display_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)
    MODEL_ID=$(echo "$json" | grep -o '"model_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)
    [ -z "$MODEL_ID" ] && MODEL_ID=$(echo "$json" | grep -o '"id"[[:space:]]*:[[:space:]]*"claude[^"]*"' | sed 's/.*:.*"\([^"]*\)"/\1/' | head -1)

    # Context window
    CTX_PCT=$(echo "$json" | grep -o '"used_percentage"[[:space:]]*:[[:space:]]*[0-9.]*' | sed 's/.*:[[:space:]]*//' | head -1 | cut -d. -f1)
    CTX_PCT="${CTX_PCT:-0}"

    MAX_TOKENS=$(echo "$json" | grep -o '"context_window_size"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    if [ -z "$MAX_TOKENS" ]; then
        if echo "$MODEL $MODEL_ID" | grep -qiE '1m|1000k'; then
            MAX_TOKENS=1000000
        else
            MAX_TOKENS=200000
        fi
    fi
    CONVERSATION_TOKENS=$((MAX_TOKENS * CTX_PCT / 100))

    # Duration
    DURATION_MS=$(echo "$json" | grep -o '"total_duration_ms"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    DURATION_MS="${DURATION_MS:-0}"

    # Lines changed
    LINES_ADDED=$(echo "$json" | grep -o '"total_lines_added"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    LINES_REMOVED=$(echo "$json" | grep -o '"total_lines_removed"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//' | head -1)
    LINES_ADDED="${LINES_ADDED:-0}"
    LINES_REMOVED="${LINES_REMOVED:-0}"

    # Defaults
    CWD="${CWD:-$(pwd)}"
    GIT_NUM_FILES="${GIT_NUM_FILES:-0}"
    MODEL="${MODEL:-unknown}"
    MODEL_ID="${MODEL_ID:-}"

    # Git branch (not in JSON - fetched locally with caching)
    GIT_BRANCH=""
    if [ -n "$CWD" ] && [ -d "$CWD" ] && command -v git >/dev/null 2>&1; then
        if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            local cache_key="$GIT_CACHE_FILE.$(printf '%s' "$CWD" | md5 -q 2>/dev/null || printf '%s' "$CWD" | md5sum 2>/dev/null | cut -d' ' -f1 || echo "x")"
            local now
            now=$(date +%s)

            if [ -f "$cache_key" ]; then
                local cache_time
                cache_time=$(stat -f %m "$cache_key" 2>/dev/null || stat -c %Y "$cache_key" 2>/dev/null || echo 0)
                [ $((now - cache_time)) -lt "$GIT_CACHE_TTL" ] && GIT_BRANCH=$(cat "$cache_key" 2>/dev/null)
            fi

            if [ -z "$GIT_BRANCH" ]; then
                GIT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
                [ -n "$GIT_BRANCH" ] && echo "$GIT_BRANCH" > "$cache_key" 2>/dev/null
            fi
        fi
    fi
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
format_model() {
    local model="$1"
    local tier version

    if echo "$model" | grep -qiE '(opus|sonnet|haiku)[[:space:]]*[0-9]'; then
        tier=$(echo "$model" | grep -oiE '(opus|sonnet|haiku)' | head -1)
        version=$(echo "$model" | grep -oE '[0-9]+\.[0-9]+' | head -1)
        tier="$(echo "${tier:0:1}" | tr '[:lower:]' '[:upper:]')${tier:1}"
        [ -n "$version" ] && echo "${tier}-${version}" || echo "$tier"
        return
    fi

    if echo "$model" | grep -qiE 'claude.*(opus|sonnet|haiku)'; then
        tier=$(echo "$model" | grep -oiE '(opus|sonnet|haiku)' | head -1)
        tier="$(echo "${tier:0:1}" | tr '[:lower:]' '[:upper:]')${tier:1}"
        version=$(echo "$model" | grep -oE '[0-9]+[\.\-][0-9]+' | tail -1 | tr '-' '.')
        [ -n "$version" ] && echo "${tier}-${version}" || echo "$tier"
        return
    fi

    echo "$model" | sed 's/^claude-//' | cut -c1-14
}

shorten_path() {
    local path="$1"
    path="${path/#$HOME/~}"
    [ ${#path} -gt 40 ] && path=$(echo "$path" | awk -F'/' '{print $(NF-1)"/"$NF}')
    echo "$path"
}

progress_bar() {
    local pct="$1"
    local width=10
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    local bar=""

    local color
    if [ "$pct" -ge 90 ]; then color="\033[31m"
    elif [ "$pct" -ge 70 ]; then color="\033[33m"
    else color="\033[32m"; fi

    for ((i=0; i<filled; i++)); do bar+="${color}█\033[0m"; done
    for ((i=0; i<empty; i++)); do bar+="\033[90m░\033[0m"; done

    echo "$bar"
}

format_tokens() {
    local num="$1"
    [ "$num" -ge 1000000000 ] && { echo "$((num / 1000000000))B"; return; }
    [ "$num" -ge 1000000 ] && { echo "$((num / 1000000))M"; return; }
    [ "$num" -ge 1000 ] && echo "$((num / 1000))k" || echo "$num"
}

format_duration() {
    local ms="$1"
    local secs=$((ms / 1000))
    local mins=$((secs / 60))
    secs=$((secs % 60))
    [ "$mins" -gt 0 ] && echo "${mins}m ${secs}s" || echo "${secs}s"
}


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_context "$INPUT"

    local W="\033[97m"
    local G="\033[32m"
    local R="\033[31m"
    local Y="\033[33m"
    local C="\033[36m"
    local DM="\033[90m"
    local D="\033[0m"

    # Line 1: path  git branch  lines diff
    local line1=""
    local short_cwd
    short_cwd=$(shorten_path "$CWD")
    line1+="📂 ${W}${short_cwd}${D}"

    if [ -n "$GIT_BRANCH" ]; then
        line1+="   ${G}${GIT_BRANCH}${D}"
        [ "$GIT_NUM_FILES" -gt 0 ] && line1+=" ${DM}(${GIT_NUM_FILES})${D}"
    fi

    if [ "$LINES_ADDED" -gt 0 ] || [ "$LINES_REMOVED" -gt 0 ]; then
        line1+="  ${G}+${LINES_ADDED}${D} ${R}-${LINES_REMOVED}${D}"
    fi

    # Line 2: context bar  model  cache hit  cost  duration
    local line2=""

    local ctx_bar
    ctx_bar=$(progress_bar "$CTX_PCT")
    local ctx_used
    ctx_used=$(format_tokens "$CONVERSATION_TOKENS")
    local ctx_max
    ctx_max=$(format_tokens "$MAX_TOKENS")
    line2+="📊 ${W}${ctx_used}/${ctx_max}${D} $ctx_bar ${W}${CTX_PCT}%${D}"

    local model_display
    model_display=$(format_model "$MODEL")
    line2+=" ${DM}|${D} 🤖 ${W}${model_display}${D}"

    if [ "$DURATION_MS" -gt 0 ]; then
        local dur_fmt
        dur_fmt=$(format_duration "$DURATION_MS")
        line2+=" ${DM}|${D} ⏱ ${DM}${dur_fmt}${D}"
    fi

    # Quota usage (daily + monthly) from credential-process cache
    local quota_cache=""
    local active_profile=""
    local install_config="$HOME/claude-code-with-bedrock/config.json"
    if [ -f "$install_config" ]; then
        active_profile=$(grep -o '"[^"]*"[[:space:]]*:[[:space:]]*{' "$install_config" | sed 's/"//g;s/[[:space:]]*:.*$//' | head -1)
    fi
    if [ -n "$active_profile" ]; then
        quota_cache="$HOME/.claude-code-session/${active_profile}-quota-cache.json"
    fi

    # Refresh quota cache in background if stale (>5 min) and poller binary exists
    local poller="$HOME/claude-code-with-bedrock/quota-poller"
    if [ -x "$poller" ] && [ -n "$quota_cache" ]; then
        local cache_age=999999
        if [ -f "$quota_cache" ]; then
            local cache_time
            cache_time=$(stat -f %m "$quota_cache" 2>/dev/null || stat -c %Y "$quota_cache" 2>/dev/null || echo 0)
            cache_age=$(( $(date +%s) - cache_time ))
        fi
        if [ "$cache_age" -gt 300 ]; then
            "$poller" --profile "$active_profile" --interval 0 > /dev/null 2>&1 &
        fi
    fi

    if [ -n "$quota_cache" ] && [ -f "$quota_cache" ]; then
        local daily_pct monthly_pct daily_tok daily_lim monthly_tok monthly_lim
        daily_pct=$(grep -o '"daily_percent"[[:space:]]*:[[:space:]]*[0-9.]*' "$quota_cache" | sed 's/.*:[[:space:]]*//' | head -1)
        monthly_pct=$(grep -o '"monthly_percent"[[:space:]]*:[[:space:]]*[0-9.]*' "$quota_cache" | sed 's/.*:[[:space:]]*//' | head -1)
        daily_tok=$(grep -o '"daily_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$quota_cache" | sed 's/.*:[[:space:]]*//' | head -1)
        daily_lim=$(grep -o '"daily_limit"[[:space:]]*:[[:space:]]*[0-9]*' "$quota_cache" | sed 's/.*:[[:space:]]*//' | head -1)
        monthly_tok=$(grep -o '"monthly_tokens"[[:space:]]*:[[:space:]]*[0-9]*' "$quota_cache" | sed 's/.*:[[:space:]]*//' | head -1)
        monthly_lim=$(grep -o '"monthly_limit"[[:space:]]*:[[:space:]]*[0-9]*' "$quota_cache" | sed 's/.*:[[:space:]]*//' | head -1)

        daily_pct="${daily_pct:-0}"
        monthly_pct="${monthly_pct:-0}"

        local d_int m_int
        d_int=$(printf '%.0f' "$daily_pct" 2>/dev/null || echo "${daily_pct%.*}")
        m_int=$(printf '%.0f' "$monthly_pct" 2>/dev/null || echo "${monthly_pct%.*}")

        local d_color m_color
        if [ "$d_int" -ge 90 ]; then d_color="$R"; elif [ "$d_int" -ge 80 ]; then d_color="$Y"; else d_color="$G"; fi
        if [ "$m_int" -ge 90 ]; then m_color="$R"; elif [ "$m_int" -ge 80 ]; then m_color="$Y"; else m_color="$G"; fi

        local d_bar m_bar
        d_bar=$(progress_bar "$d_int")
        m_bar=$(progress_bar "$m_int")

        local d_tok_fmt d_lim_fmt m_tok_fmt m_lim_fmt
        d_tok_fmt=$(format_tokens "${daily_tok:-0}")
        d_lim_fmt=$(format_tokens "${daily_lim:-0}")
        m_tok_fmt=$(format_tokens "${monthly_tok:-0}")
        m_lim_fmt=$(format_tokens "${monthly_lim:-0}")

        line2+=" ${DM}|${D} 📈 D: ${d_color}${daily_pct}%${D} $d_bar ${DM}${d_tok_fmt}/${d_lim_fmt}${D}"
        line2+="  ${DM}|${D}  M: ${m_color}${monthly_pct}%${D} $m_bar ${DM}${m_tok_fmt}/${m_lim_fmt}${D}"
    fi

    echo -e "$line1"
    echo -e "$line2"
}

main
