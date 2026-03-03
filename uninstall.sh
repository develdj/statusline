#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════
# Claude Code Statusline - Uninstall/Rollback Script
# Ripristina la configurazione allo stato precedente l'installazione
# ═══════════════════════════════════════════════════════════════════════════════

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}   Claude Code Statusline - Uninstall/Rollback Script${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════════${NC}"
echo ""

# Directory di backup
BACKUP_DIR="$HOME/.claude/backups"
CLAUDE_DIR="$HOME/.claude"

# Funzione per chiedere conferma
confirm() {
    local prompt="$1"
    local default="${2:-n}"

    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -r -p "$prompt" response
    response=${response:-$default}

    [[ "$response" =~ ^[Yy]$ ]]
}

# Funzione per backup prima di rimuovere
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        mkdir -p "$BACKUP_DIR"
        local backup_name="$(basename "$file").backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$BACKUP_DIR/$backup_name"
        echo -e "  ${YELLOW}→ Backup creato: $BACKUP_DIR/$backup_name${NC}"
    fi
}

echo -e "${YELLOW}Questo script rimuoverà:${NC}"
echo "  • statusline-command.sh"
echo "  • Configurazione statusLine da settings.json"
echo "  • File .current_profile (profilo)"
echo ""
echo -e "${GREEN}NON verranno rimossi:${NC}"
echo "  • MCP servers configurati"
echo "  • Skills installate"
echo "  • Plugins"
echo "  • Altre configurazioni in settings.json"
echo ""

if ! confirm "Vuoi procedere con l'uninstall?"; then
    echo -e "${YELLOW}Operazione annullata.${NC}"
    exit 0
fi

echo ""
echo -e "${BLUE}→ Rimozione componenti...${NC}"

# 1. Rimuovi statusline-command.sh
if [ -f "$CLAUDE_DIR/statusline-command.sh" ]; then
    backup_file "$CLAUDE_DIR/statusline-command.sh"
    rm -f "$CLAUDE_DIR/statusline-command.sh"
    echo -e "  ${GREEN}✓${NC} Rimosso statusline-command.sh"
else
    echo -e "  ${YELLOW}○${NC} statusline-command.sh non trovato"
fi

# 2. Rimuovi .current_profile
if [ -f "$CLAUDE_DIR/.current_profile" ]; then
    backup_file "$CLAUDE_DIR/.current_profile"
    rm -f "$CLAUDE_DIR/.current_profile"
    echo -e "  ${GREEN}✓${NC} Rimosso .current_profile"
else
    echo -e "  ${YELLOW}○${NC} .current_profile non trovato"
fi

# 3. Rimuovi configurazione statusLine da settings.json
SETTINGS_FILE="$CLAUDE_DIR/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
    if command -v jq &>/dev/null; then
        # Verifica se esiste la chiave statusLine
        if jq -e '.statusLine' "$SETTINGS_FILE" > /dev/null 2>&1; then
            backup_file "$SETTINGS_FILE"

            # Rimuovi solo la chiave statusLine, mantieni tutto il resto
            tmp_file=$(mktemp)
            jq 'del(.statusLine)' "$SETTINGS_FILE" > "$tmp_file" && mv "$tmp_file" "$SETTINGS_FILE"

            echo -e "  ${GREEN}✓${NC} Rimossa configurazione statusLine da settings.json"
        else
            echo -e "  ${YELLOW}○${NC} statusLine non presente in settings.json"
        fi
    else
        echo -e "  ${RED}✗${NC} jq non installato - rimozione manuale richiesta da settings.json"
        echo -e "    Rimuovi manualmente la sezione 'statusLine' da $SETTINGS_FILE"
    fi
else
    echo -e "  ${YELLOW}○${NC} settings.json non trovato"
fi

# 4. Opzionale: rimuovi backups vecchi (>30 giorni)
echo ""
if [ -d "$BACKUP_DIR" ]; then
    old_backups=$(find "$BACKUP_DIR" -name "*.backup.*" -mtime +30 2>/dev/null | wc -l)
    if [ "$old_backups" -gt 0 ]; then
        if confirm "Trovati $old_backups backup vecchi (>30gg). Rimuoverli?"; then
            find "$BACKUP_DIR" -name "*.backup.*" -mtime +30 -delete
            echo -e "  ${GREEN}✓${NC} Rimossi $old_backups backup vecchi"
        fi
    fi
fi

# 5. Verifica se la directory .claude è vuota e può essere rimossa
# (solo se non ci sono altri file importanti)
if [ -d "$CLAUDE_DIR" ]; then
    # Conta file non di backup
    other_files=$(find "$CLAUDE_DIR" -maxdepth 1 -type f ! -name ".*" 2>/dev/null | wc -l)
    other_dirs=$(find "$CLAUDE_DIR" -maxdepth 1 -type d ! -name ".claude" ! -name "backups" ! -name ".*" 2>/dev/null | wc -l)

    if [ "$other_files" -eq 0 ] && [ "$other_dirs" -eq 0 ]; then
        echo ""
        if confirm "La directory ~/.claude sembra vuota. Rimuoverla completamente?"; then
            rm -rf "$CLAUDE_DIR"
            echo -e "  ${GREEN}✓${NC} Rimossa directory ~/.claude"
        fi
    fi
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}   Uninstall completato!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "${BLUE}Per reinstallare:${NC}"
echo "  curl -o ~/.claude/statusline-command.sh https://raw.githubusercontent.com/develdj/statusline/main/statusline-command.sh"
echo "  chmod +x ~/.claude/statusline-command.sh"
echo ""
echo -e "${BLUE}Backup salvati in:${NC}"
echo "  $BACKUP_DIR"
echo ""

exit 0
