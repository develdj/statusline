#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Claude Code Status Line - Masterpiece v10
# Layout: Model | Python | MCP/Skills/Plugins (no session prefix)
# Bars: IN | OUT | Skills | MCP | Total (pastel colors, mono labels)
# ═══════════════════════════════════════════════════════════════════════════════

INPUT=$(cat)

# ═══════════════════════════════════════════════════════════════════════════════
# EXTRACT JSON DATA
# ═══════════════════════════════════════════════════════════════════════════════

MODEL=$(echo "$INPUT" | jq -r '.model.display_name // .model.id // "claude"' 2>/dev/null)
CTX_SIZE=$(echo "$INPUT" | jq -r '.context_window.context_window_size // 1000000' 2>/dev/null)
INPUT_TOKENS=$(echo "$INPUT" | jq -r '.context_window.current_usage.input_tokens // .context_window.total_input_tokens // 0' 2>/dev/null)
OUTPUT_TOKENS=$(echo "$INPUT" | jq -r '.context_window.current_usage.output_tokens // .context_window.total_output_tokens // 0' 2>/dev/null)
USED_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0' 2>/dev/null)
SESSION=$(echo "$INPUT" | jq -r '.session_name // ""' 2>/dev/null)
PROJECT_DIR=$(echo "$INPUT" | jq -r '.workspace.project_dir // .workspace.current_dir // ""' 2>/dev/null)
CWD=$(echo "$INPUT" | jq -r '.workspace.current_dir // ""' 2>/dev/null)

# Sanitize
sanitize_number() { echo "$1" | sed 's/[^0-9.]//g' | cut -d'.' -f1; }
CTX_SIZE=$(sanitize_number "$CTX_SIZE"); CTX_SIZE=${CTX_SIZE:-1000000}
INPUT_TOKENS=$(sanitize_number "$INPUT_TOKENS"); INPUT_TOKENS=${INPUT_TOKENS:-0}
OUTPUT_TOKENS=$(sanitize_number "$OUTPUT_TOKENS"); OUTPUT_TOKENS=${OUTPUT_TOKENS:-0}
USED_PCT=$(sanitize_number "$USED_PCT"); USED_PCT=${USED_PCT:-0}

# Calculate percentages
[ "$USED_PCT" -eq 0 ] && [ "$INPUT_TOKENS" -gt 0 ] && USED_PCT=$((INPUT_TOKENS * 100 / CTX_SIZE))
OUTPUT_LIMIT=${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-128000}
[ "$OUTPUT_TOKENS" -gt 0 ] && OUTPUT_PCT=$((OUTPUT_TOKENS * 100 / OUTPUT_LIMIT)) || OUTPUT_PCT=0
[ "$USED_PCT" -gt 100 ] && USED_PCT=100
[ "$OUTPUT_PCT" -gt 100 ] && OUTPUT_PCT=100

FREE_TOKENS=$((CTX_SIZE - INPUT_TOKENS))

# Format helpers
format_tokens() {
    local n=$1
    [ "$n" -ge 1000000 ] && { echo "$((n / 1000000))M"; return; }
    [ "$n" -ge 1000 ] && { echo "$((n / 1000))K"; return; }
    echo "$n"
}

# ═══════════════════════════════════════════════════════════════════════════════
# PYTHON ENV (with type detection)
# ═══════════════════════════════════════════════════════════════════════════════

PYTHON_ENV=""
PYTHON_TYPE=""
if [ -n "$VIRTUAL_ENV" ]; then
    VENV_NAME=$(basename "$VIRTUAL_ENV")
    PYTHON_TYPE="venv"
    case "$VENV_NAME" in "venv"|"env"|".venv"|".env")
        [ -n "$CWD" ] && PYTHON_ENV="$(basename "$CWD")" || PYTHON_ENV="venv"
    ;; *) PYTHON_ENV="${VENV_NAME}"; esac
elif [ -n "$CONDA_DEFAULT_ENV" ]; then
    PYTHON_TYPE="conda"
    PYTHON_ENV="${CONDA_DEFAULT_ENV}"
elif [ -n "$POETRY_ACTIVE" ]; then
    PYTHON_TYPE="poetry"
    PYTHON_ENV="poetry"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# CURRENT PROFILE
# ═══════════════════════════════════════════════════════════════════════════════

CURRENT_PROFILE=""
PROFILE_FILE="$HOME/.claude/.current_profile"
[ -f "$PROFILE_FILE" ] && CURRENT_PROFILE=$(sed -n '1p' "$PROFILE_FILE" 2>/dev/null)

PROFILE_COLOR=""
case "$CURRENT_PROFILE" in
    base)   PROFILE_COLOR="\033[90m" ;;
    ios)    PROFILE_COLOR="\033[1;36m" ;;
    web)    PROFILE_COLOR="\033[1;35m" ;;
    python) PROFILE_COLOR="\033[1;33m" ;;
    full)   PROFILE_COLOR="\033[1;31m" ;;
    *)      PROFILE_COLOR="\033[37m" ;;
esac

# ═══════════════════════════════════════════════════════════════════════════════
# MCP SERVERS
# ═══════════════════════════════════════════════════════════════════════════════

declare -a MCP_SERVERS MCP_STATUS MCP_COMMANDS
MCP_TOTAL=0
MCP_HEALTHY=0
SETTINGS_FILE="$HOME/.claude/settings.json"

if [ -f "$SETTINGS_FILE" ]; then
    MCP_TOTAL=$(jq -r '.mcpServers | keys | length' "$SETTINGS_FILE" 2>/dev/null || echo "0")
    if [ "$MCP_TOTAL" -gt 0 ]; then
        idx=0
        while IFS= read -r name; do
            [ -z "$name" ] && continue
            cmd=$(jq -r ".mcpServers[\"$name\"].command // \"\"" "$SETTINGS_FILE" 2>/dev/null)
            MCP_SERVERS[$idx]="$name"
            MCP_COMMANDS[$idx]="$cmd"
            status="unknown"
            if [ -n "$cmd" ]; then
                [[ "$cmd" == /* ]] && [ -x "$cmd" ] && status="ok"
                command -v "$cmd" &>/dev/null && status="ok"
            fi
            MCP_STATUS[$idx]="$status"
            [ "$status" = "ok" ] && MCP_HEALTHY=$((MCP_HEALTHY + 1))
            idx=$((idx + 1))
        done <<< "$(jq -r '.mcpServers | keys[]' "$SETTINGS_FILE" 2>/dev/null)"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# SKILLS & PLUGINS COUNT
# ═══════════════════════════════════════════════════════════════════════════════

SKILL_COUNT=0
[ -d "$HOME/.claude/skills" ] && SKILL_COUNT=$(find "$HOME/.claude/skills" -maxdepth 1 -type d ! -name ".*" ! -name "skills" | wc -l | tr -d '[:space:]')
SKILL_COUNT=$((SKILL_COUNT - 1)); [ "$SKILL_COUNT" -lt 0 ] && SKILL_COUNT=0

# Skills limit estimation (based on typical skill token usage ~2-5k per skill)
SKILL_TOKENS_EST=$((SKILL_COUNT * 3000))
SKILL_LIMIT=500000  # Approximate limit for skills before context issues
[ "$SKILL_TOKENS_EST" -gt "$SKILL_LIMIT" ] && SKILL_TOKENS_EST="$SKILL_LIMIT"
SKILL_PCT=$((SKILL_TOKENS_EST * 100 / SKILL_LIMIT))
[ "$SKILL_PCT" -gt 100 ] && SKILL_PCT=100

PLUGINS_ACTIVE=0; PLUGINS_TOTAL=0
[ -f "$SETTINGS_FILE" ] && PLUGINS_TOTAL=$(jq -r '.enabledPlugins | length' "$SETTINGS_FILE" 2>/dev/null || echo "0")
[ -f "$SETTINGS_FILE" ] && PLUGINS_ACTIVE=$(jq -r '[.enabledPlugins | to_entries[] | select(.value == true)] | length' "$SETTINGS_FILE" 2>/dev/null || echo "0")

# MCP as percentage (10 servers = 100%)
MCP_PCT=$((MCP_TOTAL * 10))
[ "$MCP_PCT" -gt 100 ] && MCP_PCT=100

# ═══════════════════════════════════════════════════════════════════════════════
# COLOR-CODED BARS
# ═══════════════════════════════════════════════════════════════════════════════

# Build multi-color bar showing danger zones (PASTEL COLORS)
build_danger_bar() {
    local pct=$1 width=$2
    local bar=""
    local green_end=$((width * 50 / 100))
    local yellow_end=$((width * 70 / 100))
    local orange_end=$((width * 85 / 100))
    local filled=$((pct * width / 100))

    for ((i=1; i<=width; i++)); do
        local char="░"
        [ $i -le $filled ] && char="█"

        # Pastel colors for filled, dark for empty
        if [ $i -le $green_end ]; then
            [ $i -le $filled ] && bar="${bar}\033[38;5;114m${char}" || bar="${bar}\033[38;5;238m${char}"
        elif [ $i -le $yellow_end ]; then
            [ $i -le $filled ] && bar="${bar}\033[38;5;180m${char}" || bar="${bar}\033[38;5;238m${char}"
        elif [ $i -le $orange_end ]; then
            [ $i -le $filled ] && bar="${bar}\033[38;5;173m${char}" || bar="${bar}\033[38;5;238m${char}"
        else
            [ $i -le $filled ] && bar="${bar}\033[38;5;167m${char}" || bar="${bar}\033[38;5;238m${char}"
        fi
    done
    echo -e "${bar}\033[0m"
}

# Simple single-color bar (PASTEL COLORS)
build_bar() {
    local pct=$1 width=$2
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    local bar="" color

    # Pastel color palette
    if [ "$pct" -lt 50 ]; then color="\033[38;5;114m"      # Soft green
    elif [ "$pct" -lt 70 ]; then color="\033[38;5;180m"    # Soft yellow
    elif [ "$pct" -lt 85 ]; then color="\033[38;5;173m"    # Soft orange
    else color="\033[38;5;167m"; fi                        # Soft red

    # Filled portion in pastel color
    for ((i=0; i<filled; i++)); do bar="${bar}${color}█"; done
    # Empty portion in dark gray
    for ((i=0; i<empty; i++)); do bar="${bar}\033[38;5;238m░"; done
    echo -e "${bar}\033[0m"
}

IN_BAR=$(build_danger_bar "$USED_PCT" 36)
OUT_BAR=$(build_bar "$OUTPUT_PCT" 36)
SKILL_BAR=$(build_bar "$SKILL_PCT" 36)
MCP_BAR=$(build_bar "$MCP_PCT" 36)
TOT_PCT=$(( (USED_PCT + OUTPUT_PCT) / 2 ))
[ "$TOT_PCT" -lt "$USED_PCT" ] && TOT_PCT="$USED_PCT"
TOT_BAR=$(build_bar "$TOT_PCT" 36)

IN_FMT=$(format_tokens "$INPUT_TOKENS")
OUT_FMT=$(format_tokens "$OUTPUT_TOKENS")
CTX_FMT=$(format_tokens "$CTX_SIZE")
FREE_FMT=$(format_tokens "$FREE_TOKENS")
OUT_LIMIT_FMT=$(format_tokens "$OUTPUT_LIMIT")

# ═══════════════════════════════════════════════════════════════════════════════
# RENDER
# ═══════════════════════════════════════════════════════════════════════════════

PROFILE_DISPLAY=""
[ -n "$CURRENT_PROFILE" ] && PROFILE_DISPLAY=" ${PROFILE_COLOR}[${CURRENT_PROFILE}]\033[0m"

# Python env display
PYTHON_DISPLAY=""
if [ -n "$PYTHON_ENV" ]; then
    if [ "$PYTHON_TYPE" = "conda" ]; then
        PYTHON_DISPLAY="\033[32m${PYTHON_ENV}\033[0m\033[90m[conda]\033[0m"
    elif [ "$PYTHON_TYPE" = "venv" ]; then
        PYTHON_DISPLAY="\033[33m${PYTHON_ENV}\033[0m\033[90m[venv]\033[0m"
    else
        PYTHON_DISPLAY="\033[33m${PYTHON_ENV}\033[0m\033[90m[${PYTHON_TYPE}]\033[0m"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# LINE 1: Model | Python | MCP | Skills | Plugins (LEFT ALIGNED, no session)
# ═══════════════════════════════════════════════════════════════════════════════

# Model with optional profile
printf "\033[1;97m%s\033[0m%b " "$MODEL" "$PROFILE_DISPLAY"

if [ -n "$PYTHON_DISPLAY" ]; then
    printf "\033[90m│\033[0m %b " "$PYTHON_DISPLAY"
fi

# MCP with health indicator
[ "$MCP_HEALTHY" -eq "$MCP_TOTAL" ] && [ "$MCP_TOTAL" -gt 0 ] && MCP_ICON="\033[32m●\033[0m" || MCP_ICON="\033[33m●\033[0m"
printf "\033[90m│\033[0m %b\033[37m%d\033[0m MCP " "$MCP_ICON" "$MCP_TOTAL"

printf "\033[90m│\033[0m \033[35m%d\033[0m skills " "$SKILL_COUNT"
printf "\033[90m│\033[0m \033[34m%d\033[0m plugins\n" "$PLUGINS_ACTIVE"

# ═══════════════════════════════════════════════════════════════════════════════
# LINES 2-6: Token Bars (IN, OUT, Skills, MCP, Total) - MONOCHROME LABELS
# ═══════════════════════════════════════════════════════════════════════════════

# IN bar (input tokens) - gray label
printf "\033[90mIN\033[0m   %s \033[90m%s/%s\033[0m \033[37m%3d%%\033[0m \033[90m│\033[0m \033[32m%s free\033[0m\n" \
    "$IN_BAR" "$IN_FMT" "$CTX_FMT" "$USED_PCT" "$FREE_FMT"

# OUT bar (output tokens) - gray label
printf "\033[90mOUT\033[0m  %s \033[90m%s/%s\033[0m \033[37m%3d%%\033[0m\n" \
    "$OUT_BAR" "$OUT_FMT" "$OUT_LIMIT_FMT" "$OUTPUT_PCT"

# Skills bar (estimated) - gray label
SKILL_FREE=$((SKILL_LIMIT - SKILL_TOKENS_EST))
SKILL_FREE_FMT=$(format_tokens "$SKILL_FREE")
SKILL_TOKENS_FMT=$(format_tokens "$SKILL_TOKENS_EST")
SKILL_LIMIT_FMT=$(format_tokens "$SKILL_LIMIT")
printf "\033[90mSKL\033[0m  %s \033[90m~%s/%s\033[0m \033[37m%3d%%\033[0m \033[90m│\033[0m \033[32m%s free\033[0m\n" \
    "$SKILL_BAR" "$SKILL_TOKENS_FMT" "$SKILL_LIMIT_FMT" "$SKILL_PCT" "$SKILL_FREE_FMT"

# MCP bar (tools from MCP servers) - gray label, show server count not percentage
printf "\033[90mMCP\033[0m  %s \033[90m%d/%d servers\033[0m\n" \
    "$MCP_BAR" "$MCP_HEALTHY" "$MCP_TOTAL"

# Total bar (combined view) - gray label
TOTAL_TOKENS=$((INPUT_TOKENS + OUTPUT_TOKENS))
TOTAL_FMT=$(format_tokens "$TOTAL_TOKENS")
printf "\033[90mTOT\033[0m  %s \033[90m%s total\033[0m \033[37m%3d%%\033[0m" \
    "$TOT_BAR" "$TOTAL_FMT" "$TOT_PCT"

# Warning if needed
if [ "$USED_PCT" -ge 85 ]; then
    printf " \033[90m│\033[0m \033[1;31m🔴 CRITICAL\033[0m \033[33m/compact\033[0m"
elif [ "$USED_PCT" -ge 70 ]; then
    printf " \033[90m│\033[0m \033[33m🟡 Warning\033[0m"
fi
printf "\n"

# ═══════════════════════════════════════════════════════════════════════════════
# LINE 7: MCP Servers list (compact)
# ═══════════════════════════════════════════════════════════════════════════════

if [ "$MCP_TOTAL" -gt 0 ]; then
    MCP_LINE="  \033[90m│\033[0m "
    for ((i=0; i<MCP_TOTAL; i++)); do
        name="${MCP_SERVERS[$i]}"
        cmd=$(basename "${MCP_COMMANDS[$i]}" 2>/dev/null || echo "?")
        [ "$cmd" = "node" ] && cmd="js"
        icon=$([ "${MCP_STATUS[$i]}" = "ok" ] && echo "\033[32m●\033[0m" || echo "\033[31m○\033[0m")
        display="${name:0:10}"; [ ${#name} -gt 10 ] && display="${display}…"
        MCP_LINE="${MCP_LINE}${icon}${display}\033[90m[${cmd}]\033[0m "
    done
    echo -e "$MCP_LINE"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# LINE 8: Settings
# ═══════════════════════════════════════════════════════════════════════════════

LOCAL_SETTINGS=""
if [ -n "$CWD" ] && [ "$CWD" != "$HOME" ]; then
    dir="$CWD"
    while [ "$dir" != "/" ] && [ "$dir" != "$HOME" ]; do
        [ -f "$dir/.claude/settings.json" ] && { LOCAL_SETTINGS="$dir/.claude/settings.json"; break; }
        dir=$(dirname "$dir")
    done
fi

[ -z "$LOCAL_SETTINGS" ] && printf "  \033[90m│\033[0m \033[90m⚙ global\033[0m\n" || printf "  \033[90m│\033[0m \033[32m⚙ global+local\033[0m\n"

exit 0
