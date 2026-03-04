# Confronto Statusline: Versione Utente vs Versione Claude

**Data**: 2026-03-04
**Scopo**: Analisi comparativa tra due approcci diversi per configurare la status line in Claude Code

---

## Executive Summary

| Aspect | Versione Utente | Versione Claude |
|--------|----------------|-----------------|
| **Stile** | Script "all-in-one" pronto all'uso | Documentazione procedurale educativa |
| **Complessità** | Alta (~400 righe di codice) | Bassa-Media (~100 righe per script) |
| **Integrazione** | Hook `UserPromptSubmit` | Campo `statusLine` in settings.json |
| **Input** | JSON via stdin | Lettura file settings.json e sessioni |
| **Output** | Multilinea con barre colorate | Single line semplice |
| **Features** | Molto avanzate (Git, Python, MCP health) | Base (Modello, Token, MCP, Plugins) |
| **Target** | Utenti che vogliono copia-incolla | Utenti che vogliono capire e personalizzare |

---

## Tabella Comparativa Dettagliata

### 1. ARCHITETTURA

| Aspect | Versione Utente | Versione Claude |
|--------|----------------|-----------------|
| **File richiesti** | 1 script principale + opzionali | 2 script separati (wrapper + statusline) |
| **Modularità** | Monolitico (tutto in un file) | Modulare (funzioni separate) |
| **Dipendenze esterne** | jq (per settings.json) | jq (per tutto) + find/awk |
| **Percorsi hardcoded** | Solo HOME | Configurabili via variabili |

#### Diff Codice - Architettura

```diff
@@ VERSIONE CLAUDE - 2 file separati @@
├── ~/.claude/scripts/token-wrapper.sh      # Calcola token reali
└── ~/.claude/scripts/statusline-command.sh # Genera output

@@ VERSIONE UTENTE - 1 file all-in-one @@
└── ~/.claude/statusline-command.sh          # Tutto in un file
```

---

### 2. METODO DI INTEGRAZIONE

#### Versione Claude (Vecchio Metodo)
```json
{
  "statusLine": "~/.claude/scripts/statusline-command.sh"
}
```

**Caratteristiche**:
- Campo dedicato `statusLine` in settings.json
- Lo script viene eseguito periodicamente
- Riceve input limitato/nessuno
- Metodo documentato nella vecchia documentazione Claude Code

#### Versione Utente (Nuovo Metodo)
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

**Caratteristiche**:
- Usa sistema hooks generale
- Scatto su ogni `UserPromptSubmit`
- Riceve JSON completo via stdin
- Più flessibile e potente

#### Diff Codice - Integrazione

```diff
@@ settings.json - VERSIONE CLAUDE @@
 {
   "statusLine": "~/.claude/scripts/statusline-command.sh",
   "lastModel": "claude-sonnet-4-6"
 }

@@ settings.json - VERSIONE UTENTE @@
 {
   "hooks": {
     "UserPromptSubmit": [
       {
         "command": "bash",
-        "args": ["$HOME/.claude/scripts/statusline-command.sh"]
+        "args": ["~/.claude/statusline-command.sh"]
       }
     ]
   }
 }
```

---

### 3. GESTIONE TOKEN

#### Versione Claude - Wrapper da File JSONL

```bash
# Cerca l'ultima sessione
find_latest_session() {
    find "$SESSIONS_DIR" -name "*.jsonl" -type f -printf '%T@ %p\n' | \
        sort -rn | head -1 | cut -d' ' -f2-
}

# Estrae token dal file
calculate_tokens() {
    jq -s '
        map(
            select(.context_window.usage != null) |
            .context_window.usage |
            (.input_tokens // 0) + (.output_tokens // 0) + (.cache_read_tokens // 0)
        ) | add // 0
    ' "$session_file"
}
```

**Pro**:
- Funziona anche senza Claude Code attivo
- Può analizzare sessioni storiche
- Indipendente dallo stato corrente

**Contro**:
- Richiede find/awk (non portabile al 100%)
- I/O su disco (più lento)
- Complesso da configurare

#### Versione Utente - Input via Stdin

```bash
INPUT=$(cat)

# Estrae direttamente dal JSON passato via stdin
MODEL=$(echo "$INPUT" | jq -r '.model.display_name // .model.id // "claude"')
CTX_SIZE=$(echo "$INPUT" | jq -r '.context_window.context_window_size // 1000000')
INPUT_TOKENS=$(echo "$INPUT" | jq -r '.context_window.current_usage.input_tokens // 0')
OUTPUT_TOKENS=$(echo "$INPUT" | jq -r '.context_window.current_usage.output_tokens // 0')
```

**Pro**:
- Molto veloce (nessun I/O disco)
- Dati sempre aggiornati
- Semplice e diretto
- Portabile (solo jq)

**Contro**:
- Dipende dall'hook che funzioni
- Non può analizzare sessioni storiche

#### Diff Codice - Token

```diff
@@ VERSIONE CLAUDE - Lettura da file @@
-SESSIONS_DIR="$CLAUDE_BASE/projects"
-SESSION_FILE=$(find "$SESSIONS_DIR" -name "*.jsonl" -type f | sort -rn | head -1)
-TOKENS_USED=$(jq -s 'map(.context_window.usage) | add' "$SESSION_FILE")

@@ VERSIONE UTENTE - Lettura da stdin @@
+INPUT=$(cat)
+INPUT_TOKENS=$(echo "$INPUT" | jq -r '.context_window.current_usage.input_tokens // 0')
+OUTPUT_TOKENS=$(echo "$INPUT" | jq -r '.context_window.current_usage.output_tokens // 0')
```

---

### 4. VISUALIZZAZIONE

#### Versione Claude - Single Line Semplice

```
🤖 S4.6 | 📊 45k/200k (22%) | ⚡3M:12R | 🔧5
```

**Codice**:
```bash
main() {
    MODEL=$(get_model_info)
    TOKENS=$(get_token_usage)
    MCP=$(get_mcp_info)
    SKILLS=$(get_skills_info)

    echo "${MODEL} | ${TOKENS} | ${MCP} | ${SKILLS}"
}
```

#### Versione Utente - Multilinea con Barre

```
claude-sonnet-4-6   │  ● MCP 3/3 [+]
my-project · main ±2 ↑1 │
IN  ████████████████░░░░░░░░░░░░░░░░░░░░░░░░  45k/1M  4%
OUT ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  2k/16K 12%
TOT ████████████████░░░░░░░░░░░░░░░░░░░░░░░░  47k/1M  4%
│  ● filesystem [npx]  │  ● memory [npx]  │  ● sql [uvx]
│  ⚙ local: model, mcpServers differ
```

**Codice**:
```bash
# Costruisce barre colorate
build_bar() {
    local pct=$1 width=${2:-44}
    local filled=$((pct * width / 100))
    # ... codice per generare barre █ e ░
}

# Output multilinea
printf "\033[1;97m%-18s\033[0m   \033[90m│\033[0m  \033[32m%s\033[0m\n" "$MODEL" "$MCP_TEXT"
printf "\033[36mIN\033[0m  %s \033[90m%5s/%s\033[0m..." "$(echo -e "$IN_BAR")" "$IN_FMT" "$CTX_FMT"
```

#### Diff Output - Visualizzazione

```diff
@@ VERSIONE CLAUDE @@
-🤖 S4.6 | 📊 45k/200k (22%) | ⚡3M:12R | 🔧5

@@ VERSIONE UTENTE @@
+claude-sonnet-4-6   │  ● MCP 3/3 [+]
+my-project · main ±2 ↑1 │
+IN  ████████████████░░░░░░░░░░░░░░░░░░░░░░░░  45k/1M  4%
+OUT ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  2k/16K 12%
+TOT ████████████████░░░░░░░░░░░░░░░░░░░░░░░░  47k/1M  4%
+│  ● filesystem [npx]  │  ● memory [npx]  │  ● sql [uvx]
+│  ⚙ local: model, mcpServers differ
```

---

### 5. FEATURES ESCLUSIVE

#### Versione Claude

✅ **Documentazione completa** (10 sezioni)
✅ **Troubleshooting dettagliato**
✅ **Guida personalizzazione**
✅ **Modulare e riutilizzabile**
✅ **Educativo** (spiega COME funziona)

#### Versione Utente

✅ **Git integration** (branch, changes, ahead/behind)
✅ **Python environment detection** (venv, conda, poetry, pyenv)
✅ **MCP health check** (● ok, ○ missing, ◐ no-cmd)
✅ **Visual bars** con colori dinamici
✅ **Global vs Local settings** comparison
✅ **Toggle expanded/compact mode** (Ctrl+])
✅ **Grid layout** per MCP servers

---

### 6. CODICE - GIT INFO

#### Solo Versione Utente

```bash
GIT_INFO=""
if [ -n "$CWD" ] && [ -d "$CWD/.git" ] 2>/dev/null; then
    BRANCH=$(cd "$CWD" 2>/dev/null && git symbolic-ref --short HEAD 2>/dev/null)
    CHANGES=$(cd "$CWD" 2>/dev/null && git status --porcelain 2>/dev/null | wc -l)
    AHEAD=$(cd "$CWD" 2>/dev/null && git rev-list --count @{upstream}..HEAD 2>/dev/null)
    BEHIND=$(cd "$CWD" 2>/dev/null && git rev-list --count HEAD..@{upstream} 2>/dev/null)

    GIT_INFO="${BRANCH}"
    [ "$CHANGES" -gt 0 ] && GIT_INFO="${GIT_INFO} ±${CHANGES}"
    [ "$AHEAD" -gt 0 ] && GIT_INFO="${GIT_INFO} ↑${AHEAD}"
    [ "$BEHIND" -gt 0 ] && GIT_INFO="${GIT_INFO} ↓${BEHIND}"
fi
```

**Output esempio**: `main ±2 ↑1` (branch main, 2 modifiche, 1 commit ahead)

---

### 7. CODICE - PYTHON ENV

#### Solo Versione Utente

```bash
PYTHON_ENV=""
if [ -n "$VIRTUAL_ENV" ]; then
    VENV_NAME=$(basename "$VIRTUAL_ENV")
    case "$VENV_NAME" in
        "venv"|"env"|".venv"|".env")
            [ -n "$CWD" ] && PYTHON_ENV="$(basename "$CWD")" || PYTHON_ENV="venv"
            ;;
        *) PYTHON_ENV="${VENV_NAME}" ;;
    esac
elif [ -n "$CONDA_DEFAULT_ENV" ] && [ "$CONDA_DEFAULT_ENV" != "base" ]; then
    PYTHON_ENV="${CONDA_DEFAULT_ENV}"
elif [ -n "$POETRY_ACTIVE" ]; then
    PYTHON_ENV="poetry"
elif [ -n "$PYENV_VERSION" ]; then
    PYTHON_ENV="${PYENV_VERSION}"
fi
```

**Rileva**: venv, conda, poetry, pyenv

---

### 8. CODICE - MCP HEALTH CHECK

#### Solo Versione Utente

```bash
declare -a MCP_SERVERS MCP_STATUS MCP_COMMANDS
idx=0
while IFS= read -r name; do
    cmd=$(jq -r ".mcpServers[\"$name\"].command // \"\"" "$SETTINGS_FILE")

    status="unknown"
    if [ -n "$cmd" ]; then
        if [[ "$cmd" == /* ]] && [ -x "$cmd" ]; then
            status="ok"
        elif command -v "$cmd" &>/dev/null; then
            status="ok"
        elif [ "$cmd" = "node" ] && [ -n "$args" ]; then
            # Verifica esistenza script node...
            status="ok"  # o "missing"
        fi
    fi

    MCP_STATUS[$idx]="$status"
    [ "$status" = "ok" ] && MCP_HEALTHY=$((MCP_HEALTHY + 1))
    idx=$((idx + 1))
done <<< "$(jq -r '.mcpServers | keys[]' "$SETTINGS_FILE")"
```

**Icone**:
- ● verde: comando disponibile
- ○ rosso: comando mancante
- ◐ giallo: nessun comando definito

---

### 9. CODICE - GLOBAL VS LOCAL SETTINGS

#### Solo Versione Utente

```bash
# Trova settings locale camminando l'albero delle directory
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

# Confronta e mostra differenze
if [ "$LOCAL_MODEL" != "$GLOBAL_MODEL" ]; then
    echo -e "  ├─ \033[33mmodel\033[0m: ${G_SHORT} → \033[1;33m${L_SHORT}\033[0m"
fi
```

**Output esempio**: `⚙ local: model, mcpServers differ`

---

### 10. FILE OPZIONALI

#### Toggle Script (Solo Versione Utente)

```bash
#!/bin/bash
# ~/.claude/toggle-statusline.sh
TOGGLE_FILE="$HOME/.claude/statusline-mcp-expanded"

if [ -f "$TOGGLE_FILE" ]; then
    rm "$TOGGLE_FILE"
    echo "Statusline: compact mode"
else
    touch "$TOGGLE_FILE"
    echo "Statusline: expanded mode"
fi
```

#### Keybinding Zsh (Solo Versione Utente)

```bash
# ~/.zshrc
_toggle_statusline() {
    if [ -f "$HOME/.claude/statusline-mcp-expanded" ]; then
        rm "$HOME/.claude/statusline-mcp-expanded"
    else
        touch "$HOME/.claude/statusline-mcp-expanded"
    fi
    zle reset-prompt
}
zle -N _toggle_statusline
bindkey '^]' _toggle_statusline  # Ctrl+]
```

---

## 11. CONFIGURAZIONE SETTINGS.JSON

### Versione Claude

```json
{
  "statusLine": "~/.claude/scripts/statusline-command.sh",
  "lastModel": "claude-sonnet-4-6",
  "contextWindow": 200000,
  "enabledPlugins": ["superpowers:code-reviewer"],
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path"],
      "enabled": true
    }
  }
}
```

### Versione Utente

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "command": "bash",
        "args": ["$HOME/.claude/statusline-command.sh"]
      }
    ]
  },
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path"]
    }
  }
}
```

**Nota**: La versione utente NON richiede `lastModel` o `contextWindow` perché legge questi dati dal JSON passato via stdin.

---

## 12. DIFF FILE COMPLESSIVO

```
diff --git a/claude-version/ b/user-version/
index 111111..222222 100644
--- a/claude-version/
+++ b/user-version/
@@ -1,50 +1,400 @@
-# Claude Code Status Line - Setup Completo
-## Documentazione Generica per Configurazione Status Line
+#!/bin/bash
+# ═══════════════════════════════════════════════════════════════════════════
+# Claude Code Status Line - Masterpiece v6
+# ═══════════════════════════════════════════════════════════════════════════

-## 1. Prerequisiti e Verifiche
+INPUT=$(cat)
+- jq (Processore JSON)
+- find, xargs, grep, sed, awk
++ jq (solo)

-## 2. Wrapper per Token Reali
-function find_latest_session() {
-    find "$SESSIONS_DIR" -name "*.jsonl" | sort -rn | head -1
-}
-function calculate_tokens() {
-    jq -s 'map(.context_window.usage) | add' "$session_file"
-}
++# Estrae direttamente da stdin
++MODEL=$(echo "$INPUT" | jq -r '.model.display_name // .model.id')
++CTX_SIZE=$(echo "$INPUT" | jq -r '.context_window.context_window_size')
++INPUT_TOKENS=$(echo "$INPUT" | jq -r '.context_window.current_usage.input_tokens')

-## 3. Script Status Line
-main() {
-    MODEL=$(get_model_info)
-    TOKENS=$(get_token_usage)
-    MCP=$(get_mcp_info)
-    SKILLS=$(get_skills_info)
-    echo "${MODEL} | ${TOKENS} | ${MCP} | ${SKILLS}"
-}
++# Git integration
++if [ -d "$CWD/.git" ]; then
++    BRANCH=$(git symbolic-ref --short HEAD)
++    CHANGES=$(git status --porcelain | wc -l)
++    AHEAD=$(git rev-list --count @{upstream}..HEAD)
++    GIT_INFO="${BRANCH} ±${CHANGES} ↑${AHEAD}"
++fi

-## 4. Configurazione settings.json
-{
-  "statusLine": "~/.claude/scripts/statusline-command.sh"
-}
++# Python env detection
++if [ -n "$VIRTUAL_ENV" ]; then
++    PYTHON_ENV=$(basename "$VIRTUAL_ENV")
++elif [ -n "$CONDA_DEFAULT_ENV" ]; then
++    PYTHON_ENV="${CONDA_DEFAULT_ENV}"
++fi

-## 5. Procedura di Installazione
-(7 sezioni dettagliate)
++# MCP health check
++for name in $(jq -r '.mcpServers | keys[]' "$SETTINGS_FILE"); do
++    cmd=$(jq -r ".mcpServers[\"$name\"].command" "$SETTINGS_FILE")
++    command -v "$cmd" &>/dev/null && status="ok" || status="missing"
++done

-## 6. Verifica e Test
-(4 sottosezioni)
++# Visual bars
++build_bar() {
++    local pct=$1 width=44
++    local filled=$((pct * width / 100))
++    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
++    for ((i=0; i<empty; i++)); do bar="${bar}░"; done
++    echo "${bar}"
++}

-## 7. Troubleshooting
-(5 problemi + soluzioni)
++# Output multilinea
++printf "%-18s  │  %s\n" "$MODEL" "$MCP_TEXT"
++printf "IN  %s %5s/%s %2d%%  │\n" "$IN_BAR" "$IN_FMT" "$CTX_FMT" "$USED_PCT"
++printf "OUT %s %5s/%s %2d%%  │\n" "$OUT_BAR" "$OUT_FMT" "$OUT_LIMIT_FMT" "$OUTPUT_PCT"
++printf "TOT %s %5s/%s %2d%%  │\n" "$TOT_BAR" "$TOT_FMT" "$CTX_FMT" "$TOTAL_PCT"

-## 8. Personalizzazione
-(5 sottosezioni)
++# MCP grid layout
++for ((row=0; row < (MCP_TOTAL + 2) / 3; row++)); do
++    for ((col=0; col < 3; col++)); do
++        idx=$((row * 3 + col))
++        [ $idx -lt $MCP_TOTAL ] && printf "│ %s %s" "$icon" "${MCP_SERVERS[$idx]}"
++    done
++    echo
++done

-## 9. Comandi Utili
-(3 sezioni jq)
++# Global vs Local settings
++if [ -f "$LOCAL_SETTINGS" ]; then
++    echo "⚙ local: $(IFS=", "; echo "${SETTINGS_DIFFS[*]}") differ"
++fi

-## 10. Note Aggiuntive
-(Performance, Sicurezza, Compatibilità)
++## Hook Configuration
++{
++  "hooks": {
++    "UserPromptSubmit": [
++      {
++        "command": "bash",
++        "args": ["$HOME/.claude/statusline-command.sh"]
++      }
++    ]
++  }
++}
```

---

## 13. PRO E CONTRO

### Versione Claude

| Pro | Contro |
|-----|--------|
| ✅ Facile da capire | ❌ Output minimale |
| ✅ Modulare e riutilizzabile | ❌ Richiede 2 file |
| ✅ Documentazione completa | ❌ Nessuna feature avanzata |
| ✅ buona per imparare | ❌ Token tracking lento (I/O) |
| ✅ Completamente generico | ❌ Usa `statusLine` (vecchio metodo) |

### Versione Utente

| Pro | Contro |
|-----|--------|
| ✅ Ricco di features | ❌ Complesso da modificare |
| ✅ Veloce (stdin vs I/O) | ❌ Monolitico |
| ✅ Output bellissimo | ❌ Richiede hook system |
| ✅ Git + Python integration | ❌ Meno documentato |
| ✅ MCP health check | ❌ Più difficile da personalizzare |
| ✅ Usa nuovo metodo hooks | ❌ ~400 righe di codice |

---

## 14. QUALE USARE?

### Scegli Versione Claude se:

- 🎓 **Vuoi imparare** come funziona la status line
- 🔧 **Vuoi personalizzare** facilmente
- 📝 **Ti serve documentazione** completa
- 🐛 **Vuoi troubleshooting** dettagliato
- 🔄 **Vuoi un approccio modulare**

### Scegli Versione Utente se:

- ⚡ **Vuoi copia-incolare** e funzionare subito
- 🎨 **Vuoi output bello** con barre e colori
- 🌿 **Vuoi Git integration** nel terminale
- 🐍 **Vuoi Python env detection**
- 🔍 **Vuoi MCP health check**
- ⚙️ **Usi settings locali** per progetto

---

## 15. MIGRAZIONE

### Da Versione Claude a Versione Utente

```bash
# 1. Rimuovi vecchia configurazione
jq 'del(.statusLine)' ~/.claude/settings.json > /tmp/settings.tmp
mv /tmp/settings.tmp ~/.claude/settings.json

# 2. Aggiungi hook
jq '.hooks.UserPromptSubmit = [{"command": "bash", "args": ["~/.claude/statusline-command.sh"]}]' \
   ~/.claude/settings.json > /tmp/settings.tmp
mv /tmp/settings.tmp ~/.claude/settings.json

# 3. Sostituisci script
rm ~/.claude/scripts/statusline-command.sh
rm ~/.claude/scripts/token-wrapper.sh
# (incolla il nuovo script in ~/.claude/statusline-command.sh)
```

### Da Versione Utente a Versione Claude

```bash
# 1. Rimuovi hook
jq 'del(.hooks.UserPromptSubmit)' ~/.claude/settings.json > /tmp/settings.tmp
mv /tmp/settings.tmp ~/.claude/settings.json

# 2. Aggiungi statusLine
jq '.statusLine = "~/.claude/scripts/statusline-command.sh"' \
   ~/.claude/settings.json > /tmp/settings.tmp
mv /tmp/settings.tmp ~/.claude/settings.json

# 3. Sostituisci script
rm ~/.claude/statusline-command.sh
mkdir -p ~/.claude/scripts
# (crea wrapper e statusline separati)
```

---

## 16. CONCLUSIONI

Entrambe le versioni sono valide e servono scopi diversi:

- **Versione Claude**: È una **guida completa** per capire e costruire una status line personalizzata. Ideale per chi vuole imparare e adattare alle proprie esigenze.

- **Versione Utente**: È una **soluzione completa e pronta** con features avanzate. Ideale per chi vuole un risultato professionale subito.

La versione utente è significativamente più avanzata in termini di features e visualizzazione, ma anche più complessa da manutenere e personalizzare. La versione Claude sacrificaa features per chiarezza e flessibilità.

---

**Documento creato**: 2026-03-04
**Versioni confrontate**:
- Versione Claude: `~/Downloads/statusline-setup.md`
- Versione Utente: Script inline nel prompt

---

## Appendice: Comandi Rapidi

### Test Versione Claude
```bash
~/.claude/scripts/statusline-command.sh
# Output: 🤖 S4.6 | 📊 45k/200k (22%) | ⚡3M:12R | 🔧5
```

### Test Versione Utente
```bash
echo '{"model":{"display_name":"claude-sonnet-4-6"},"context_window":{"current_usage":{"input_tokens":45000}}}' | \
~/.claude/statusline-command.sh
# Output: multilinea con barre
```

### Toggle Mode (Utente only)
```bash
~/.claude/toggle-statusline.sh
# o Ctrl+] se keybinding configurato
```
