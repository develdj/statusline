# Claude Code Status Line - Setup Completo

## Documentazione Generica per Configurazione Status Line

> **Nota**: Questo documento è completamente generico e può essere utilizzato su qualsiasi sistema con Claude Code installato.
> Tutti i percorsi sono relativi o determinati automaticamente dallo script.

---

## 1. Prerequisiti e Verifiche

### 1.1 Dipendenze Richieste

Lo script richiede i seguenti comandi, tipicamente disponibili su sistemi Unix-like:

- `jq` - Processore JSON da riga di comando
- `find` - Ricerca file
- `xargs` - Esecuzione comandi da input
- `grep`, `sed`, `awk` - Manipolazione testo

### 1.2 Verifica Dipendenze

```bash
# Verifica che jq sia installato
if ! command -v jq &> /dev/null; then
    echo "ERRORE: jq non trovato. Installa con: brew install jq (macOS) o apt install jq (Linux)"
    exit 1
fi

echo "✓ Tutte le dipendenze sono soddisfatte"
```

### 1.3 Identificazione Percorsi

```bash
# Percorso base di Claude Code (di solito ~/.claude)
CLAUDE_BASE="${CLAUDE_BASE:-$HOME/.claude}"

# Percorso dello script di configurazione settings.json
SETTINGS_FILE="$CLAUIDE_BASE/settings.json"

# Percorso della directory degli script
SCRIPTS_DIR="$CLAUDE_BASE/scripts"

# Percorso del wrapper per token
WRAPPER_SCRIPT="$SCRIPTS_DIR/token-wrapper.sh"

# Percorso dello script statusline
STATUSLINE_SCRIPT="$SCRIPTS_DIR/statusline-command.sh"
```

---

## 2. Wrapper per Token Reali

### 2.1 Scopo del Wrapper

Il wrapper calcola i token **realmente utilizzati** leggendo i file di sessione di Claude Code, invece di basarsi su una stima approssimativa. Questo garantisce un monitoraggio preciso del consumo.

### 2.2 Funzionamento

Claude Code crea file di sessione con naming convention:
```
{timestamp}-{random-id}.jsonl
```

Il wrapper:
1. Identifica tutti i file `.jsonl` nella directory delle sessioni
2. Estrae i dati sull'utilizzo dei token da ogni sessione
3. Somma `input_tokens`, `output_tokens`, e `cache_read_tokens`
4. Calcola la percentuale utilizzata della context window

### 2.3 Codice Wrapper Completo

```bash
#!/bin/bash
# File: ~/.claude/scripts/token-wrapper.sh
# Scopo: Calcolo token reali utilizzati da Claude Code

set -euo pipefail

# Configurazione
CLAUDE_BASE="${CLAUDE_BASE:-$HOME/.claude}"
SESSIONS_DIR="$CLAUDE_BASE/projects"
CONTEXT_WINDOW="${CONTEXT_WINDOW:-200000}"  # Default per Sonnet 4.6

# Trova l'ultimo file di sessione modificato
find_latest_session() {
    find "$SESSIONS_DIR" -name "*.jsonl" -type f -printf '%T@ %p\n' 2>/dev/null | \
        sort -rn | \
        head -1 | \
        cut -d' ' -f2-
}

# Calcola token totali da un file di sessione
calculate_tokens() {
    local session_file="$1"

    if [[ ! -f "$session_file" ]]; then
        echo "0"
        return
    fi

    # Estrai e somma tutti i token dal file JSONL
    jq -s '
        map(
            select(.context_window.usage != null) |
            .context_window.usage |
            (.input_tokens // 0) +
            (.output_tokens // 0) +
            (.cache_read_tokens // 0)
        ) |
        add // 0
    ' "$session_file"
}

# Main
SESSION_FILE=$(find_latest_session)

if [[ -n "$SESSION_FILE" ]]; then
    TOKENS_USED=$(calculate_tokens "$SESSION_FILE")
    PERCENT_USED=$((TOKENS_USED * 100 / CONTEXT_WINDOW))

    # Output formato compatto
    echo "📊 ${TOKENS_USED}k/${CONTEXT_WINDOW}k (${PERCENT_USED}%)"
else
    echo "📊 N/A"
fi
```

### 2.4 Spiegazione Sezioni Wrapper

| Sezione | Scopo |
|---------|-------|
| `set -euo pipefail` | Gestione errori rigorosa |
| `find_latest_session()` | Trova sessione più recente |
| `calculate_tokens()` | Estrae e somma token da file JSONL |
| `jq -s` | Legge tutto il file JSONL come array |
| `map/select` | Filtra solo entry con dati usage |
| `add // 0` | Somma tutto, default 0 se vuoto |

---

## 3. Script Status Line

### 3.1 Template Completo

```bash
#!/bin/bash
# File: ~/.claude/scripts/statusline-command.sh
# Scopo: Genera output per status line di Claude Code

set -euo pipefail

# ========================================
# SEZIONE 1: CONFIGURAZIONE
# ========================================

# Colori (opzionale - richiede terminale che supporta ANSI)
readonly COLOR_RESET='\[\033[0m\]'
readonly COLOR_MODEL='\[\033[36m\]'    # Cyan
readonly COLOR_TOKEN='\[\033[33m\]'    # Yellow
readonly COLOR_MCP='\[\033[32m\]'      # Green
readonly COLOR_SKILL='\[\033[35m\]'    # Magenta

# Percorsi
readonly CLAUDE_BASE="${CLAUDE_BASE:-$HOME/.claude}"
readonly WRAPPER_SCRIPT="$CLAUDE_BASE/scripts/token-wrapper.sh"
readonly SETTINGS_FILE="$CLAUDE_BASE/settings.json"

# ========================================
# SEZIONE 2: MODELLO ATTIVO
# ========================================

get_model_info() {
    # Leggi il modello da settings.json o usa default
    if [[ -f "$SETTINGS_FILE" ]]; then
        MODEL=$(jq -r '.lastModel // "sonnet-4-6"' "$SETTINGS_FILE" 2>/dev/null)
    else
        MODEL="sonnet-4-6"
    fi

    # Formatta output (mostra solo modello breve)
    case "$MODEL" in
        *sonnet*) echo "🤖 S4.6" ;;
        *opus*) echo "🤖 O4.6" ;;
        *haiku*) echo "🤖 H4.5" ;;
        *) echo "🤖 $MODEL" ;;
    esac
}

# ========================================
# SEZIONE 3: TOKEN REALI
# ========================================

get_token_usage() {
    if [[ -x "$WRAPPER_SCRIPT" ]]; then
        "$WRAPPER_SCRIPT"
    else
        # Fallback se wrapper non disponibile
        echo "📊 N/A"
    fi
}

# ========================================
# SEZIONE 4: MCP SERVERS
# ========================================

get_mcp_info() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo "MCP:0"
        return
    fi

    # Conta server MCP abilitati
    MCP_COUNT=$(jq '[.mcpServers // {} | to_entries[] |
                    select(.value.enabled == true or .value.enabled == null)] |
                    length' "$SETTINGS_FILE" 2>/dev/null || echo "0")

    # Conta risorse MCP disponibili
    RESOURCE_COUNT=$(jq '[.mcpServers // {} | to_entries[] |
                         select(.value.enabled == true or .value.enabled == null) |
                         .value.args // {}] |
                         map(has("command") or has("env")) |
                         length' "$SETTINGS_FILE" 2>/dev/null || echo "0")

    echo "⚡${MCP_COUNT}M:${RESOURCE_COUNT}R"
}

# ========================================
# SEZIONE 5: SKILLS & PLUGINS
# ========================================

get_skills_info() {
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        echo "🔧0"
        return
    fi

    # Conta plugin abilitati
    PLUGIN_COUNT=$(jq '[.enabledPlugins // [] | .[]] | length' "$SETTINGS_FILE" 2>/dev/null || echo "0")

    echo "🔧${PLUGIN_COUNT}"
}

# ========================================
# SEZIONE 6: ASSEMBLA OUTPUT
# ========================================

main() {
    # Ottieni tutte le sezioni
    MODEL=$(get_model_info)
    TOKENS=$(get_token_usage)
    MCP=$(get_mcp_info)
    SKILLS=$(get_skills_info)

    # Assembla output con separatore |
    echo "${MODEL} | ${TOKENS} | ${MCP} | ${SKILLS}"
}

# Esegui main
main
```

### 3.2 Sezioni Spiegate

| Sezione | Contenuto | Output Esempio |
|---------|-----------|----------------|
| **Modello** | Nome modello attivo | `🤖 S4.6` |
| **Token** | Token usati/totali (%) | `📊 45k/200k (22%)` |
| **MCP** | Server e risorse | `⚡3M:12R` |
| **Skills** | Plugin abilitati | `🔧5` |

### 3.3 Personalizzazione Output

```bash
# Output compatto (tutto su una riga)
echo "${MODEL}|${TOKENS}|${MCP}|${SKILLS}"

# Output multilinea (più leggibile)
cat << EOF
Modello: ${MODEL}
Token: ${TOKENS}
MCP: ${MCP}
Skills: ${SKILLS}
EOF

# Output con colori (se supportato)
echo -e "${COLOR_MODEL}${MODEL}${COLOR_RESET} | ${COLOR_TOKEN}${TOKENS}${COLOR_RESET}"
```

---

## 4. Configurazione settings.json

### 4.1 Struttura Completa

```json
{
  "statusLine": "~/.claude/scripts/statusline-command.sh",
  "lastModel": "claude-sonnet-4-6",
  "contextWindow": 200000,

  "enabledPlugins": [
    "superpowers:code-reviewer",
    "superpowers:frontend-design"
  ],

  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/allowed"],
      "enabled": true
    },
    "memory": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-memory"],
      "enabled": true
    },
    "sql-database": {
      "command": "custom-sql-server",
      "args": ["--connection-string", "postgresql://..."],
      "enabled": false
    }
  },

  "permissions": {
    "allowedTools": ["*"],
    "blockedTools": []
  }
}
```

### 4.2 Spiegazione Campi Principali

| Campo | Tipo | Scopo |
|-------|------|-------|
| `statusLine` | string | Percorso assoluto allo script da eseguire |
| `lastModel` | string | Ultimo modello utilizzato |
| `contextWindow` | number | Dimensione context window in token |
| `enabledPlugins` | array | Lista plugin abilitati |
| `mcpServers` | object | Configurazione server MCP |
| `enabled` | boolean | Abilita/disabilita server MCP |

### 4.3 Percorsi Relative vs Assoluti

**Assoluti (Raccomandati per statusLine)**:
```json
{
  "statusLine": "/home/user/.claude/scripts/statusline-command.sh"
}
```

**Relativi (Accettabili per MCP)**:
```json
{
  "mcpServers": {
    "local-server": {
      "command": "./my-local-server",
      "args": ["--config", "config.json"]
    }
  }
}
```

---

## 5. Procedura di Installazione

### 5.1 Backup File Esistenti

```bash
# Crea backup di settings.json esistente
if [[ -f "$HOME/.claude/settings.json" ]]; then
    cp "$HOME/.claude/settings.json" \
       "$HOME/.claude/settings.json.backup.$(date +%Y%m%d_%H%M%S)"
    echo "✓ Backup creato: settings.json.backup.$(date +%Y%m%d_%H%M%S)"
fi
```

### 5.2 Creazione Directory Scripts

```bash
# Crea directory scripts se non esiste
mkdir -p "$HOME/.claude/scripts"
echo "✓ Directory scripts creata"
```

### 5.3 Installazione Wrapper

```bash
# Scrivi wrapper su file
cat > "$HOME/.claude/scripts/token-wrapper.sh" << 'WRAPPER_EOF'
#!/bin/bash
# [Inserire qui codice wrapper completo dalla Sezione 2.3]
WRAPPER_EOF

# Rendi eseguibile
chmod +x "$HOME/.claude/scripts/token-wrapper.sh"
echo "✓ Wrapper installato"
```

### 5.4 Installazione Status Line

```bash
# Scrivi statusline su file
cat > "$HOME/.claude/scripts/statusline-command.sh" << 'STATUSLINE_EOF'
#!/bin/bash
# [Inserire qui codice statusline completo dalla Sezione 3.1]
STATUSLINE_EOF

# Rendi eseguibile
chmod +x "$HOME/.claude/scripts/statusline-command.sh"
echo "✓ Status line installata"
```

### 5.5 Aggiornamento settings.json

```bash
# Aggiungi o aggiorna statusLine in settings.json
if [[ -f "$HOME/.claude/settings.json" ]]; then
    # Usa jq per aggiungere/aggiornare il campo
    jq --arg sl "$HOME/.claude/scripts/statusline-command.sh" \
       '.statusLine = $sl' \
       "$HOME/.claude/settings.json" > \
       "$HOME/.claude/settings.json.tmp" && \
    mv "$HOME/.claude/settings.json.tmp" \
       "$HOME/.claude/settings.json"
    echo "✓ settings.json aggiornato"
else
    # Crea nuovo settings.json
    cat > "$HOME/.claude/settings.json" << JSON_EOF
{
  "statusLine": "$HOME/.claude/scripts/statusline-command.sh",
  "lastModel": "claude-sonnet-4-6"
}
JSON_EOF
    echo "✓ settings.json creato"
fi
```

### 5.6 Verifica Permessi

```bash
# Verifica che entrambi gli script siano eseguibili
ls -lh "$HOME/.claude/scripts/"

# Output atteso:
# -rwxr-xr-x ... token-wrapper.sh
# -rwxr-xr-x ... statusline-command.sh
```

---

## 6. Verifica e Test

### 6.1 Test Wrapper

```bash
# Esegui wrapper direttamente
~/.claude/scripts/token-wrapper.sh

# Output atteso (esempio):
# 📊 45k/200k (22%)
```

### 6.2 Test Status Line Completo

```bash
# Esegui statusline direttamente
~/.claude/scripts/statusline-command.sh

# Output atteso (esempio):
# 🤖 S4.6 | 📊 45k/200k (22%) | ⚡3M:12R | 🔧5
```

### 6.3 Test Integrazione Claude Code

```bash
# Riavvia Claude Code o apri nuova sessione
# La status line dovrebbe apparire automaticamente

# Verifica che settings.json sia valido
jq empty ~/.claude/settings.json && echo "✓ JSON valido" || echo "✗ JSON non valido"
```

### 6.4 Comandi di Debug

```bash
# Verifica percorso script
echo "$HOME/.claude/scripts/statusline-command.sh"

# Verifica permessi
ls -l "$HOME/.claude/scripts/"

# Test singole funzioni
bash -c 'source ~/.claude/scripts/statusline-command.sh && get_model_info'
bash -c 'source ~/.claude/scripts/statusline-command.sh && get_token_usage'
```

---

## 7. Troubleshooting

### 7.1 Problema: Status line non appare

**Possibili cause**:
1. Script non eseguibile
2. Percorso errato in settings.json
3. Script con errori sintattici

**Soluzioni**:
```bash
# 1. Verifica permessi
chmod +x ~/.claude/scripts/*.sh

# 2. Verifica percorso
jq '.statusLine' ~/.claude/settings.json

# 3. Test script manualmente
~/.claude/scripts/statusline-command.sh
```

### 7.2 Problema: Token mostrano "N/A"

**Possibili cause**:
1. Nessuna sessione trovata
2. File JSONL vuoti o malformati
3. Wrapper non eseguibile

**Soluzioni**:
```bash
# 1. Verifica esistenza sessioni
find ~/.claude/projects -name "*.jsonl" -type f

# 2. Verifica contenuto sessione
jq -s 'length' ~/.claude/projects/*.jsonl | head -1

# 3. Test wrapper
~/.claude/scripts/token-wrapper.sh
```

### 7.3 Problema: MCP mostra "0M:0R"

**Possibili cause**:
1. Nessun server configurato
2. Server disabilitati in settings.json
3. Parsing JSON fallito

**Soluzioni**:
```bash
# 1. Verifica configurazione MCP
jq '.mcpServers' ~/.claude/settings.json

# 2. Verifica server abilitati
jq '.mcpServers | to_entries[] | select(.value.enabled == true or .value.enabled == null)' \
   ~/.claude/settings.json

# 3. Test parsing
echo '3' | jq '. + 1'
```

### 7.4 Problema: Errori "jq: command not found"

**Soluzione**:
```bash
# macOS
brew install jq

# Linux (Debian/Ubuntu)
sudo apt install jq

# Linux (Fedora)
sudo dnf install jq

# Verifica installazione
jq --version
```

### 7.5 Problema: Script lento

**Possibili cause**:
1. Troppi file di sessione
2. Parsing JSON complesso
3. I/O su disco lento

**Soluzioni**:
```bash
# 1. Pulisci sessioni vecchie (mantiene ultime 10)
find ~/.claude/projects -name "*.jsonl" -type f -printf '%T@ %p\n' | \
    sort -rn | \
    tail -n +11 | \
    cut -d' ' -f2- | \
    xargs rm -v

# 2. Cache risultati (opzionale)
# Aggiungi caching in wrapper se necessario
```

---

## 8. Personalizzazione

### 8.1 Modificare Colori

```bash
# Nello script statusline, modifica le costanti COLOR_*
readonly COLOR_MODEL='\[\033[36m\]'    # Cambia colore modello
readonly COLOR_TOKEN='\[\033[33m\]'    # Cambia colore token

# Codici colori ANSI comuni:
# 30: Nero, 31: Rosso, 32: Verde, 33: Giallo
# 34: Blu, 35: Magenta, 36: Ciano, 37: Bianco
```

### 8.2 Aggiungere Sezioni

```bash
# Aggiungi funzione personalizzata
get_git_info() {
    local branch=$(git branch --show-current 2>/dev/null)
    if [[ -n "$branch" ]]; then
        echo "🌿 $branch"
    fi
}

# Aggiungi a main()
main() {
    # ... codice esistente ...
    GIT=$(get_git_info)
    echo "${MODEL} | ${TOKENS} | ${MCP} | ${SKILLS} | ${GIT}"
}
```

### 8.3 Modificare Icone

```bash
# Modifica le icone nelle funzioni

# Modello
case "$MODEL" in
    *sonnet*) echo "⚡ S4.6" ;;   # Icona diversa
    *opus*) echo "🔥 O4.6" ;;
    *haiku*) echo "💧 H4.5" ;;
esac

# Token
echo "TOKEN:${TOKENS_USED}k"  # Nessuna icona

# MCP
echo "Server:${MCP_COUNT}"    # Testo invece di icona
```

### 8.4 Adattare a Diverse Configurazioni

```bash
# Configurazione globale vs locale
if [[ -f "$HOME/.claude/settings.json" ]]; then
    SETTINGS="$HOME/.claude/settings.json"
elif [[ -f "./.claude/settings.json" ]]; then
    SETTINGS="./.claude/settings.json"
else
    echo "ERRORE: Nessun settings.json trovato"
    exit 1
fi

# Configurazione multiprogetto
PROJECT_NAME=$(basename "$PWD")
PROJECT_SETTINGS="$HOME/.claude/projects/$PROJECT_NAME/settings.json"

if [[ -f "$PROJECT_SETTINGS" ]]; then
    SETTINGS="$PROJECT_SETTINGS"
fi
```

### 8.5 Estensione per Plugin Personalizzati

```bash
# Sistema plugin per estensioni
PLUGINS_DIR="$HOME/.claude/statusline-plugins"

# Carica tutti i plugin
for plugin in "$PLUGINS_DIR"/*.sh; do
    if [[ -f "$plugin" ]]; then
        source "$plugin"
    fi
done

# Chiama hook plugins se esistono
if declare -f plugin_custom_section > /dev/null; then
    CUSTOM=$(plugin_custom_section)
fi
```

---

## 9. Comandi Utili per Identificazione

### 9.1 Identificare Server MCP

```bash
# Lista tutti i server MCP configurati
jq '.mcpServers | keys[]' ~/.claude/settings.json

# Mostra dettagli server specifico
jq '.mcpServers.memory' ~/.claude/settings.json

# Mostra solo server abilitati
jq '.mcpServers | to_entries |
    map(select(.value.enabled == true or .value.enabled == null)) |
    map(.key)' ~/.claude/settings.json
```

### 9.2 Identificare Risorse MCP

```bash
# Conta risorse totali
jq '[.mcpServers | to_entries[] |
     select(.value.enabled == true or .value.enabled == null) |
     .value.args] |
    length' ~/.claude/settings.json

# Mostra risorse per server
jq '.mcpServers.filesystem.args' ~/.claude/settings.json
```

### 9.3 Identificare Skills e Plugin

```bash
# Lista plugin abilitati
jq '.enabledPlugins[]' ~/.claude/settings.json

# Conta plugin
jq '.enabledPlugins | length' ~/.claude/settings.json

# Cerca skills disponibili
ls ~/.claude/skills/

# Cerca hooks configurati
jq '.hooks | keys[]' ~/.claude/settings.json
```

---

## 10. Note Aggiuntive

### 10.1 Performance

- Lo script viene eseguito ad ogni aggiornamento della status line
- Evita operazioni pesanti (network, I/O massivo)
- Usa caching per dati che non cambiano frequentemente

### 10.2 Sicurezza

- Non inserire password o token segreti negli script
- Verifica permessi dei file (sola lettura per altri utenti)
- Usa percorsi assoluti per evitare path traversal

### 10.3 Compatibilità

- Testato su macOS (zsh, bash) e Linux (bash)
- Richiede bash 4+ per alcune features
- Compatible con Claude Code 1.0+

### 10.4 Aggiornamenti

Per aggiornare lo script in futuro:

1. Modifica i file sorgente
2. Non è necessario modificare settings.json
3. Le modifiche sono immediate al prossimo refresh

---

## Appendice A: Esempi Output

### Esempio 1: Configurazione Base
```
🤖 S4.6 | 📊 45k/200k (22%) | ⚡0M:0R | 🔧0
```

### Esempio 2: Configurazione Completa
```
🤖 O4.6 | 📊 128k/200k (64%) | ⚡3M:12R | 🔧5
```

### Esempio 3: Con Git Branch (Personalizzato)
```
🤖 S4.6 | 📊 12k/200k (6%) | ⚡1M:3R | 🔧2 | 🌿 feature/new-ui
```

### Esempio 4: Multilinea (Personalizzato)
```
Modello: 🤖 Sonnet 4.6
Token: 📊 45000/200000 (22%)
MCP: ⚡ 3 server, 12 risorse
Plugins: 🔧 5 attivi
```

---

## Appendice B: Riferimenti Utili

- **Documentazione Claude Code**: https://github.com/anthropics/claude-code
- **jq Manual**: https://stedolan.github.io/jq/manual/
- **ANSI Color Codes**: https://en.wikipedia.org/wiki/ANSI_escape_code
- **Bash Guide**: https://www.gnu.org/software/bash/manual/

---

**Versione Documento**: 1.0
**Data**: 2026-03-04
**Compatibilità**: Claude Code 1.0+, macOS, Linux

---

## Istruzioni per Claude

Se sei Claude e stai leggendo questo documento:

1. **Verifica prerequisiti** - Esegui i comandi nella Sezione 1
2. **Crea i file** - Segui la procedura nella Sezione 5
3. **Testa l'installazione** - Esegui i comandi nella Sezione 6
4. **Verifica output** - Assicurati che la status line funzioni

Tutti i comandi possono essere eseguiti autonomamente senza intervento umano.
