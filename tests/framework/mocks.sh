# shellcheck shell=bash
#
# mocks.sh — Mock dei binari di sistema e PATH ristretto
#
# Sorgiato da test_framework.sh, non direttamente dalle suite.
#

# --- Mock helpers ---

# --- PATH ristretto ---

# Crea un PATH contenente solo i comandi di sistema essenziali + eventuali extra.
# I mock in $MOCK_BIN hanno sempre precedenza.
# Uso: setup_restricted_path                  → solo comandi base
#      setup_restricted_path pgrep diff python3 → base + extra
# shellcheck disable=SC2120  # Argomenti opzionali: $@ aggiunge comandi extra
setup_restricted_path() {
    local sys_bin="$TEST_TMPDIR/sys_bin"
    mkdir -p "$sys_bin"
    local base_cmds=(bash grep sed echo cat rm mkdir chmod cp touch sleep tr head printf mktemp wc)
    local cmd real_path
    for cmd in "${base_cmds[@]}" "$@"; do
        real_path=$(which "$cmd" 2>/dev/null || true)
        if [ -n "$real_path" ] && [ -f "$real_path" ]; then
            ln -sf "$real_path" "$sys_bin/$cmd"
        fi
    done
    export PATH="$MOCK_BIN:$sys_bin"
}

# --- Mock helpers ---

create_mock() {
    local name="$1"
    local body="${2:-}"
    cat > "$MOCK_BIN/$name" <<MOCK_EOF
#!/usr/bin/env bash
echo "$name \$*" >> "\$MOCK_CALL_LOG"
$body
MOCK_EOF
    chmod +x "$MOCK_BIN/$name"
}

create_gsettings_mock() {
    local initial_value="${1:-@as []}"

    # Imposta valore iniziale per custom-keybindings
    echo "$initial_value" > "$GSETTINGS_STATE/custom-keybindings"

    cat > "$MOCK_BIN/gsettings" <<'GSETTINGS_EOF'
#!/usr/bin/env bash

echo "gsettings $*" >> "$MOCK_CALL_LOG"

ACTION="$1"
shift

case "$ACTION" in
    get)
        SCHEMA="$1"
        KEY="$2"
        if [[ "$SCHEMA" == *"custom-keybinding:"* ]]; then
            BINDING_PATH=$(echo "$SCHEMA" | sed 's/.*custom-keybinding://')
            STATE_FILE="$GSETTINGS_STATE/binding_${KEY}_$(echo "$BINDING_PATH" | tr '/' '_')"
        else
            STATE_FILE="$GSETTINGS_STATE/$KEY"
        fi
        if [ -f "$STATE_FILE" ]; then
            cat "$STATE_FILE"
        else
            echo "@as []"
        fi
        ;;
    set)
        SCHEMA="$1"
        KEY="$2"
        VALUE="$3"
        if [[ "$SCHEMA" == *"custom-keybinding:"* ]]; then
            BINDING_PATH=$(echo "$SCHEMA" | sed 's/.*custom-keybinding://')
            STATE_FILE="$GSETTINGS_STATE/binding_${KEY}_$(echo "$BINDING_PATH" | tr '/' '_')"
        else
            STATE_FILE="$GSETTINGS_STATE/$KEY"
        fi
        echo "$VALUE" > "$STATE_FILE"
        ;;
    reset)
        SCHEMA="$1"
        KEY="$2"
        if [[ "$SCHEMA" == *"custom-keybinding:"* ]]; then
            BINDING_PATH=$(echo "$SCHEMA" | sed 's/.*custom-keybinding://')
            STATE_FILE="$GSETTINGS_STATE/binding_${KEY}_$(echo "$BINDING_PATH" | tr '/' '_')"
        else
            STATE_FILE="$GSETTINGS_STATE/$KEY"
        fi
        rm -f "$STATE_FILE"
        ;;
esac
GSETTINGS_EOF
    chmod +x "$MOCK_BIN/gsettings"
}

create_date_mock() {
    local fixed_timestamp="$1"

    # Salva il path del date reale
    local real_date
    real_date=$(which date 2>/dev/null || echo "/usr/bin/date")

    cat > "$MOCK_BIN/date" <<DATE_EOF
#!/usr/bin/env bash
echo "date \$*" >> "\$MOCK_CALL_LOG"
if [ "\$1" = "+%Y%m%d_%H%M%S" ]; then
    echo "$fixed_timestamp"
else
    "$real_date" "\$@"
fi
DATE_EOF
    chmod +x "$MOCK_BIN/date"
}

