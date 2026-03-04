# Claude Code Statusline - Setup Guide

Questo file contiene la configurazione completa della statusline personalizzata per Claude Code.

## Come usare questo file

Su una nuova macchina, dì a Claude:
> "Leggi il file ~/.claude/statusline-setup.md e configura la statusline seguendo le istruzioni"

---

## 1. Statusline Script

Salva questo contenuto in `~/.claude/statusline-command.sh`:

```bash
#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════
# Claude Code Status Line - Masterpiece v6
# Clean aligned layout with proper grid
# ═══════════════════════════════════════════════════════════════════════════

INPUT=$(cat)

# Toggle expanded mode
MCP_EXPANDED=0
[ -f "$HOME/.claude/statusline-mcp-expanded" ] || [ "$CLAUDE_STATUSLINE_EXPANDED" = "1" ] && MCP_EXPANDED=1

# ═══════════════════════════════════════════════════════════════════════════
# EXTRACT JSON DATA
# ═══════════════════════════════════════════════════════════════════════════

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
OUTPUT_LIMIT=${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-16384}
[ "$OUTPUT_TOKENS" -gt 0 ] && OUTPUT_PCT=$((OUTPUT_TOKENS * 100 / OUTPUT_LIMIT)) || OUTPUT_PCT=0
TOTAL_TOKENS=$((INPUT_TOKENS + OUTPUT_TOKENS))
TOTAL_PCT=$((TOTAL_TOKENS * 100 / CTX_SIZE))
[ "$USED_PCT" -gt 100 ] && USED_PCT=100
[ "$OUTPUT_PCT" -gt 100 ] && OUTPUT_PCT=100
[ "$TOTAL_PCT" -gt 100 ] && TOTAL_PCT=100

# Format helpers
format_tokens() {
    local n=$1
    [ "$n" -ge 1000000 ] && { echo "$((n / 1000000))M"; return; }
    [ "$n" -ge 1000 ] && { echo "$((n / 1000))K"; return; }
    echo "$n"
}

PROJECT_NAME=""
[ -n "$PROJECT_DIR" ] && [ "$PROJECT_DIR" != "null" ] && PROJECT_NAME=$(basename "$PROJECT_DIR" 2>/dev/null)

# ═══════════════════════════════════════════════════════════════════════════
# GIT INFO
# ═══════════════════════════════════════════════════════════════════════════

GIT_INFO=""
if [ -n "$CWD" ] && [ -d "$CWD/.git" ] 2>/dev/null; then
    BRANCH=$(cd "$CWD" 2>/dev/null && git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    if [ -n "$BRANCH" ]; then
        CHANGES=$(cd "$CWD" 2>/dev/null && git status --porcelain 2>/dev/null | wc -l | tr -d '[:space:]')
        AHEAD=$(cd "$CWD" 2>/dev/null && git rev-list --count @{upstream}..HEAD 2>/dev/null || echo "0")
        BEHIND=$(cd "$CWD" 2>/dev/null && git rev-list --count HEAD..@{upstream} 2>/dev/null || echo "0")
        GIT_INFO="${BRANCH}"
        [ "$CHANGES" -gt 0 ] && GIT_INFO="${GIT_INFO} ±${CHANGES}"
        [ "$AHEAD" -gt 0 ] && GIT_INFO="${GIT_INFO} ↑${AHEAD}"
        [ "$BEHIND" -gt 0 ] && GIT_INFO="${GIT_INFO} ↓${BEHIND}"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# PYTHON ENV
# ═══════════════════════════════════════════════════════════════════════════

PYTHON_ENV=""
if [ -n "$VIRTUAL_ENV" ]; then
    VENV_NAME=$(basename "$VIRTUAL_ENV")
    case "$VENV_NAME" in "venv"|"env"|".venv"|".env")
        [ -n "$CWD" ] && PYTHON_ENV="$(basename "$CWD")" || PYTHON_ENV="venv"
    ;; *) PYTHON_ENV="${VENV_NAME}"; esac
elif [ -n "$CONDA_DEFAULT_ENV" ] && [ "$CONDA_DEFAULT_ENV" != "base" ]; then
    PYTHON_ENV="${CONDA_DEFAULT_ENV}"
elif [ -n "$CONDA_DEFAULT_ENV" ]; then
    PYTHON_ENV="base"
elif [ -n "$POETRY_ACTIVE" ]; then
    PYTHON_ENV="poetry"
elif [ -n "$PYENV_VERSION" ]; then
    PYTHON_ENV="${PYENV_VERSION}"
fi

# ═══════════════════════════════════════════════════════════════════════════
# MCP SERVERS
# ═══════════════════════════════════════════════════════════════════════════

declare -a MCP_SERVERS MCP_STATUS MCP_COMMANDS
MCP_TOTAL=0
MCP_HEALTHY=0
MCP_UNHEALTHY=0

SETTINGS_FILE="$HOME/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
    MCP_TOTAL=$(jq -r '.mcpServers | keys | length' "$SETTINGS_FILE" 2>/dev/null || echo "0")

    if [ "$MCP_TOTAL" -gt 0 ]; then
        idx=0
        while IFS= read -r name; do
            [ -z "$name" ] && continue
            cmd=$(jq -r ".mcpServers[\"$name\"].command // \"\"" "$SETTINGS_FILE" 2>/dev/null)
            args=$(jq -r ".mcpServers[\"$name\"].args // [] | join(\" \")" "$SETTINGS_FILE" 2>/dev/null)

            MCP_SERVERS[$idx]="$name"
            MCP_COMMANDS[$idx]="$cmd"

            status="unknown"
            if [ -n "$cmd" ]; then
                if [[ "$cmd" == /* ]] && [ -x "$cmd" ]; then
                    status="ok"
                elif command -v "$cmd" &>/dev/null; then
                    status="ok"
                elif [ "$cmd" = "node" ] && [ -n "$args" ]; then
                    script=$(echo "$args" | grep -o '/[^ ]*\.js' | head -1)
                    if [ -n "$script" ] && [ -f "$script" ]; then
                        status="ok"
                    elif [ -n "$script" ]; then
                        status="missing"
                    else
                        status="ok"
                    fi
                elif [ "$cmd" = "uv" ] || [ "$cmd" = "uvx" ]; then
                    command -v "$cmd" &>/dev/null && status="ok" || status="missing"
                else
                    status="missing"
                fi
            else
                status="no-cmd"
            fi

            MCP_STATUS[$idx]="$status"
            [ "$status" = "ok" ] && MCP_HEALTHY=$((MCP_HEALTHY + 1)) || MCP_UNHEALTHY=$((MCP_UNHEALTHY + 1))
            idx=$((idx + 1))
        done <<< "$(jq -r '.mcpServers | keys[]' "$SETTINGS_FILE" 2>/dev/null)"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# BUILD BARS (44 chars)
# ═══════════════════════════════════════════════════════════════════════════

build_bar() {
    local pct=$1 width=${2:-44}
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    local bar="" color

    if [ "$pct" -lt 50 ]; then color="\033[38;5;46m"
    elif [ "$pct" -lt 70 ]; then color="\033[38;5;148m"
    elif [ "$pct" -lt 85 ]; then color="\033[38;5;214m"
    else color="\033[38;5;196m"; fi

    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=0; i<empty; i++)); do bar="${bar}░"; done
    echo "${color}${bar}\033[0m"
}

IN_BAR=$(build_bar "$USED_PCT" 44)
OUT_BAR=$(build_bar "$OUTPUT_PCT" 44)
TOT_BAR=$(build_bar "$TOTAL_PCT" 44)
IN_FMT=$(format_tokens "$INPUT_TOKENS")
OUT_FMT=$(format_tokens "$OUTPUT_TOKENS")
TOT_FMT=$(format_tokens "$TOTAL_TOKENS")
CTX_FMT=$(format_tokens "$CTX_SIZE")

# ═══════════════════════════════════════════════════════════════════════════
# RENDER
# ═══════════════════════════════════════════════════════════════════════════

# Fixed width for alignment
LEFT_WIDTH=20
TOTAL_WIDTH=70

# Build info line
INFO_PARTS=()
[ -n "$SESSION" ] && [ "$SESSION" != "null" ] && INFO_PARTS+=("$SESSION")
[ -n "$PROJECT_NAME" ] && INFO_PARTS+=("$PROJECT_NAME")
[ -n "$GIT_INFO" ] && INFO_PARTS+=("$GIT_INFO")
[ -n "$PYTHON_ENV" ] && INFO_PARTS+=("$PYTHON_ENV")
INFO_LINE=$(IFS=" · "; echo "${INFO_PARTS[*]}")

# MCP header text
if [ "$MCP_UNHEALTHY" -gt 0 ]; then
    MCP_TEXT="⚠ MCP ${MCP_HEALTHY}/${MCP_TOTAL}"
else
    MCP_TEXT="● MCP ${MCP_HEALTHY}/${MCP_TOTAL}"
fi
[ "$MCP_EXPANDED" -eq 1 ] && MCP_TEXT="${MCP_TEXT} [+]"

# ═══════════════════════════════════════════════════════════════════════════
# OUTPUT
# ═══════════════════════════════════════════════════════════════════════════

# Line 1: Model (left) | MCP (right) - aligned
printf "\033[1;97m%-18s\033[0m   \033[90m│\033[0m  \033[32m%s\033[0m\n" "$MODEL" "$MCP_TEXT"

# Line 2: Info
[ -n "$INFO_LINE" ] && printf "%-22s  \033[90m│\033[0m\n" "$INFO_LINE"

# Line 3-5: Bars (fixed format for alignment)
printf "\033[36mIN\033[0m  %s \033[90m%5s/%s\033[0m \033[37m%2d%%\033[0m  \033[90m│\033[0m\n" "$(echo -e "$IN_BAR")" "$IN_FMT" "$CTX_FMT" "$USED_PCT"
OUT_LIMIT_FMT=$(format_tokens "$OUTPUT_LIMIT")
printf "\033[35mOUT\033[0m %s \033[90m%5s/%s\033[0m \033[37m%2d%%\033[0m  \033[90m│\033[0m\n" "$(echo -e "$OUT_BAR")" "$OUT_FMT" "$OUT_LIMIT_FMT" "$OUTPUT_PCT"
printf "\033[33mTOT\033[0m %s \033[90m%5s/%s\033[0m \033[37m%2d%%\033[0m  \033[90m│\033[0m\n" "$(echo -e "$TOT_BAR")" "$TOT_FMT" "$CTX_FMT" "$TOTAL_PCT"

# MCP Grid - 3 per line with fixed column widths
if [ "$MCP_TOTAL" -gt 0 ]; then
    COL_WIDTH=20
    MCP_PER_LINE=3

    # Build MCP items with status icon
    build_mcp_item() {
        local idx=$1
        local name="${MCP_SERVERS[$idx]}"
        local status="${MCP_STATUS[$idx]}"
        local cmd="${MCP_COMMANDS[$idx]}"

        # Icon based on status
        local icon
        case "$status" in
            ok)      icon="\033[32m●\033[0m" ;;
            missing) icon="\033[31m○\033[0m" ;;
            no-cmd)  icon="\033[33m◐\033[0m" ;;
            *)       icon="\033[90m○\033[0m" ;;
        esac

        # Truncate name to fit column
        local display="${name:0:14}"
        [ ${#name} -gt 14 ] && display="${display}…"

        # Command hint if expanded
        local cmd_hint=""
        if [ "$MCP_EXPANDED" -eq 1 ] && [ -n "$cmd" ]; then
            local short_cmd=$(basename "$cmd" 2>/dev/null || echo "$cmd")
            short_cmd="${short_cmd:0:5}"
            cmd_hint=" \033[90m[${short_cmd}]\033[0m"
        fi

        printf "%s %s%s" "$icon" "$display" "$cmd_hint"
    }

    # Output grid
    for ((row=0; row < (MCP_TOTAL + MCP_PER_LINE - 1) / MCP_PER_LINE; row++)); do
        LINE=""
        for ((col=0; col < MCP_PER_LINE; col++)); do
            idx=$((row * MCP_PER_LINE + col))
            if [ $idx -lt $MCP_TOTAL ]; then
                ITEM=$(build_mcp_item $idx)
                if [ -z "$LINE" ]; then
                    LINE="  \033[90m│\033[0m $(build_mcp_item $idx)"
                else
                    LINE="${LINE}  \033[90m│\033[0m $(build_mcp_item $idx)"
                fi
            fi
        done
        [ -n "$LINE" ] && echo -e "$LINE"
    done
fi

# ═══════════════════════════════════════════════════════════════════════════
# SETTINGS: Global vs Local
# ═══════════════════════════════════════════════════════════════════════════

GLOBAL_SETTINGS="$HOME/.claude/settings.json"
LOCAL_SETTINGS=""

# Find local settings by walking up directory tree
if [ -n "$CWD" ] && [ "$CWD" != "$HOME" ]; then
    dir="$CWD"
    while [ "$dir" != "/" ] && [ "$dir" != "$HOME" ]; do
        if [ -f "$dir/.claude/settings.json" ]; then
            LOCAL_SETTINGS="$dir/.claude/settings.json"
            break
        fi
        dir=$(dirname "$dir")
    done
fi

# Extract and compare settings
SETTINGS_DIFFS=()
GLOBAL_MODEL=""
LOCAL_MODEL=""
GLOBAL_MCP_COUNT=0
LOCAL_MCP_COUNT=0
GLOBAL_PLUGINS_COUNT=0
LOCAL_PLUGINS_COUNT=0
LOCAL_PLUGIN_NAMES=""

if [ -f "$GLOBAL_SETTINGS" ]; then
    GLOBAL_MODEL=$(jq -r '.model // ""' "$GLOBAL_SETTINGS" 2>/dev/null)
    GLOBAL_MCP_COUNT=$(jq -r '.mcpServers | keys | length' "$GLOBAL_SETTINGS" 2>/dev/null || echo "0")
    GLOBAL_PLUGINS_COUNT=$(jq -r '.enabledPlugins | length' "$GLOBAL_SETTINGS" 2>/dev/null || echo "0")
fi

if [ -n "$LOCAL_SETTINGS" ] && [ -f "$LOCAL_SETTINGS" ]; then
    LOCAL_MODEL=$(jq -r '.model // ""' "$LOCAL_SETTINGS" 2>/dev/null)
    LOCAL_MCP_COUNT=$(jq -r '.mcpServers | keys | length' "$LOCAL_SETTINGS" 2>/dev/null || echo "0")
    LOCAL_PLUGINS_COUNT=$(jq -r '.enabledPlugins | length' "$LOCAL_SETTINGS" 2>/dev/null || echo "0")

    # Get local plugin names if different count
    if [ "$LOCAL_PLUGINS_COUNT" -gt 0 ]; then
        LOCAL_PLUGIN_NAMES=$(jq -r '.enabledPlugins | join(", ")' "$LOCAL_SETTINGS" 2>/dev/null)
    fi

    # Check for differences
    if [ -n "$LOCAL_MODEL" ] && [ "$LOCAL_MODEL" != "$GLOBAL_MODEL" ]; then
        SETTINGS_DIFFS+=("model")
    fi
    if [ "$LOCAL_MCP_COUNT" != "$GLOBAL_MCP_COUNT" ]; then
        SETTINGS_DIFFS+=("mcpServers")
    fi
    if [ "$LOCAL_PLUGINS_COUNT" != "$GLOBAL_PLUGINS_COUNT" ]; then
        SETTINGS_DIFFS+=("plugins")
    fi
fi

# Build settings line
if [ "$MCP_EXPANDED" -eq 1 ]; then
    # Expanded mode - show detailed comparison
    echo -e "  \033[90m│\033[0m"
    echo -e "  \033[90m│\033[0m \033[1;97m⚙ Settings\033[0m"

    if [ -z "$LOCAL_SETTINGS" ]; then
        echo -e "  \033[90m│\033[0m   └─ \033[37mglobal only\033[0m"
    else
        # Show model comparison
        if [ -n "$LOCAL_MODEL" ] && [ "$LOCAL_MODEL" != "$GLOBAL_MODEL" ]; then
            # Shorten model names for display
            G_SHORT=$(echo "$GLOBAL_MODEL" | sed 's/claude-//' | sed 's/-4-6/[4.6]/' | sed 's/-opus-4-6/[opus]/' | sed 's/-haiku-4-5/[haiku]/')
            L_SHORT=$(echo "$LOCAL_MODEL" | sed 's/claude-//' | sed 's/-4-6/[4.6]/' | sed 's/-opus-4-6/[opus]/' | sed 's/-haiku-4-5/[haiku]/')
            echo -e "  \033[90m│\033[0m   ├─ \033[33mmodel\033[0m: ${G_SHORT} → \033[1;33m${L_SHORT}\033[0m"
        else
            echo -e "  \033[90m│\033[0m   ├─ \033[90mmodel\033[0m: ${GLOBAL_MODEL:-default}"
        fi

        # Show MCP servers comparison
        if [ "$LOCAL_MCP_COUNT" != "$GLOBAL_MCP_COUNT" ]; then
            echo -e "  \033[90m│\033[0m   ├─ \033[33mmcpServers\033[0m: ${GLOBAL_MCP_COUNT} global → \033[1;33m${LOCAL_MCP_COUNT} local\033[0m"
        else
            echo -e "  \033[90m│\033[0m   ├─ \033[90mmcpServers\033[0m: ${GLOBAL_MCP_COUNT}"
        fi

        # Show plugins comparison
        if [ "$LOCAL_PLUGINS_COUNT" != "$GLOBAL_PLUGINS_COUNT" ]; then
            echo -e "  \033[90m│\033[0m   └─ \033[33mplugins\033[0m: ${GLOBAL_PLUGINS_COUNT} global → \033[1;33m${LOCAL_PLUGINS_COUNT} local\033[0m"
        else
            echo -e "  \033[90m│\033[0m   └─ \033[90mplugins\033[0m: ${GLOBAL_PLUGINS_COUNT}"
        fi
    fi
else
    # Compact mode
    if [ -z "$LOCAL_SETTINGS" ]; then
        echo -e "  \033[90m│\033[0m \033[90m⚙ global only\033[0m"
    elif [ ${#SETTINGS_DIFFS[@]} -eq 0 ]; then
        echo -e "  \033[90m│\033[0m \033[32m⚙ local (same)\033[0m"
    else
        DIFF_STR=$(IFS=", "; echo "${SETTINGS_DIFFS[*]}")
        echo -e "  \033[90m│\033[0m \033[1;33m⚙ local\033[0m: \033[33m${DIFF_STR} differ\033[0m"
    fi
fi

exit 0
```

---

## 2. Hook Configuration

Aggiungi questo al file `~/.claude/settings.json` nella sezione `hooks`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "command": "bash",
        "args": ["$HOME/.claude/statusline-command.sh"]
      }
    ]
  }
}
```

---

## 3. Toggle Script (opzionale)

Salva in `~/.claude/toggle-statusline.sh`:

```bash
#!/bin/bash
# Toggle statusline expanded mode
TOGGLE_FILE="$HOME/.claude/statusline-mcp-expanded"

if [ -f "$TOGGLE_FILE" ]; then
    rm "$TOGGLE_FILE"
    echo "Statusline: compact mode"
else
    touch "$TOGGLE_FILE"
    echo "Statusline: expanded mode"
fi
```

Poi rendilo eseguibile:
```bash
chmod +x ~/.claude/toggle-statusline.sh
```

---

## 4. Keybinding Zsh (opzionale)

Aggiungi a `~/.zshrc`:

```bash
# Statusline toggle - Ctrl+]
_toggle_statusline() {
    local msg
    if [ -f "$HOME/.claude/statusline-mcp-expanded" ]; then
        rm "$HOME/.claude/statusline-mcp-expanded"
        msg="\033[1;32m✓ Statusline: compact mode\033[0m"
    else
        touch "$HOME/.claude/statusline-mcp-expanded"
        msg="\033[1;33m✓ Statusline: expanded mode\033[0m"
    fi
    print -P "\n$msg"
    zle reset-prompt
}
zle -N _toggle_statusline
bindkey '^]' _toggle_statusline
```

---

## 5. Prerequisiti

Assicurati che `jq` sia installato:
```bash
# macOS
brew install jq

# Linux
apt install jq  # o yum install jq
```

---

## Features

- **Modello corrente** in alto a sinistra
- **MCP servers** con stato (● ok, ○ missing, ◐ no-cmd)
- **Context bars** per input/output/total tokens
- **Git info** (branch, changes, ahead/behind)
- **Python env** (venv, conda, poetry, pyenv)
- **Settings comparison** global vs local (model, mcpServers, plugins)
- **Toggle Ctrl+]** per modalità compact/expanded

---

## Comando rapido per Claude

Per installare tutto su una nuova macchina:

> "Leggi il file ~/.claude/statusline-setup.md e:
> 1. Crea il file statusline-command.sh
> 2. Aggiungi l'hook in settings.json
> 3. Crea il toggle script
> 4. Aggiungi il keybinding zsh
> 5. Verifica che jq sia installato"
