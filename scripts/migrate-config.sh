#!/usr/bin/env bash
#
# migrate-config.sh — Migrazione della configurazione dalla v1
#
# Nella v1 le costanti si editavano dentro lo script installato, quindi
# ogni reinstallazione cancellava le personalizzazioni dell'utente. Dalla
# v2 vivono in ~/.config/paste-image/config. Questo script rileva i valori
# modificati nello script v1 ancora installato e propone di riportarli.
#
# Invocato da install.sh prima di sovrascrivere l'eseguibile.
#

set -euo pipefail

INSTALLED_SCRIPT="${1:-$HOME/.local/bin/paste-image}"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/paste-image/config"

# Chiavi migrabili e valore di fabbrica della v1
V1_KEYS=(MAX_LOG_LINES NOTIFY_TIMEOUT CLEANUP_DAYS TYPING_DELAY)
V1_DEFAULTS=(500 3000 7 0.1)

# La v1 assegnava le costanti al livello superiore dello script.
# Nella v2 stanno indentate dentro config_defaults(): l'ancoraggio a inizio
# riga è ciò che distingue le due versioni.
is_v1_script() {
    [ -f "$1" ] && grep -q '^MAX_LOG_LINES=' "$1"
}

read_v1_value() {
    sed -n "s/^$2=\([^ #]*\).*/\1/p" "$1" | head -1
}

collect_customizations() {
    local script="$1" i key value default
    CUSTOMIZED=()

    for i in "${!V1_KEYS[@]}"; do
        key="${V1_KEYS[$i]}"
        default="${V1_DEFAULTS[$i]}"
        value=$(read_v1_value "$script" "$key")
        [ -z "$value" ] && continue
        [ "$value" = "$default" ] && continue
        CUSTOMIZED+=("$key=$value")
    done
}

write_config() {
    local entry
    mkdir -p "$(dirname "$CONFIG_FILE")"

    if [ ! -f "$CONFIG_FILE" ]; then
        {
            echo "# Configurazione di paste-image"
            echo "# Migrata automaticamente dalla versione 1."
            echo "# Formato: CHIAVE=valore, una per riga."
            echo ""
        } > "$CONFIG_FILE"
    fi

    for entry in "${CUSTOMIZED[@]}"; do
        if grep -q "^${entry%%=*}=" "$CONFIG_FILE" 2>/dev/null; then
            echo "  ${entry%%=*}: già presente nel config, non sovrascritto"
            continue
        fi
        echo "$entry" >> "$CONFIG_FILE"
        echo "  $entry"
    done
}

main() {
    if ! is_v1_script "$INSTALLED_SCRIPT"; then
        exit 0
    fi

    collect_customizations "$INSTALLED_SCRIPT"

    if [ ${#CUSTOMIZED[@]} -eq 0 ]; then
        exit 0
    fi

    echo ""
    echo "--- Migrazione configurazione dalla v1 ---"
    echo ""
    echo "Nello script installato risultano valori personalizzati:"
    printf '  %s\n' "${CUSTOMIZED[@]}"
    echo ""
    echo "Dalla v2 la configurazione vive in $CONFIG_FILE"
    echo "e non viene più sovrascritta dagli aggiornamenti."
    echo ""

    read -rp "Vuoi riportarli nel file di configurazione? [S/n] " REPLY
    REPLY=${REPLY:-S}
    if [[ "$REPLY" =~ ^[SsYy]$ ]]; then
        write_config
        echo ""
        echo "Configurazione migrata in: $CONFIG_FILE"
    else
        echo "Migrazione saltata. I valori personalizzati andranno persi."
    fi
    echo ""
}

main
