#!/usr/bin/env bash
#
# test_migrate_config.sh — Migrazione della configurazione dalla v1
#
# Il bug di prodotto che la v2 corregge: nella v1 le costanti si editavano
# dentro lo script installato, quindi ogni reinstallazione cancellava le
# personalizzazioni. Questi test verificano che l'aggiornamento non le perda.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

MIGRATE="$PROJECT_DIR/scripts/migrate-config.sh"

# Helper: crea un finto script v1 installato, con i valori indicati
make_v1_script() {
    local path="$1" log_lines="${2:-500}" cleanup="${3:-7}" delay="${4:-0.1}"
    cat > "$path" <<V1
#!/usr/bin/env bash
set -euo pipefail
VERSION="1.0.0"
MAX_LOG_LINES=$log_lines
NOTIFY_TIMEOUT=3000
CLEANUP_DAYS=$cleanup
TYPING_DELAY=$delay
V1
    chmod +x "$path"
}

config_path() {
    echo "$FAKE_HOME/.config/paste-image/config"
}

# --- Test: valori personalizzati vengono proposti e migrati ---
test_customized_values_migrated() {
    local script="$FAKE_HOME/.local/bin/paste-image"
    make_v1_script "$script" 999 30 0.5

    echo "s" | bash "$MIGRATE" "$script" >/dev/null 2>&1

    local config
    config=$(config_path)
    assert_file_exists "$config" "config creato"
    assert_file_contains "$config" "MAX_LOG_LINES=999" "valore personalizzato migrato"
    assert_file_contains "$config" "CLEANUP_DAYS=30" "secondo valore migrato"
    assert_file_contains "$config" "TYPING_DELAY=0.5" "terzo valore migrato"
}

# --- Test: i valori di fabbrica non finiscono nel config ---
test_default_values_not_migrated() {
    local script="$FAKE_HOME/.local/bin/paste-image"
    make_v1_script "$script" 500 7 0.1

    echo "s" | bash "$MIGRATE" "$script" >/dev/null 2>&1

    assert_file_not_exists "$(config_path)" "nessun config per soli default"
}

# --- Test: rifiutando la migrazione non viene scritto nulla ---
test_declined_migration_writes_nothing() {
    local script="$FAKE_HOME/.local/bin/paste-image"
    make_v1_script "$script" 999 30 0.5

    echo "n" | bash "$MIGRATE" "$script" >/dev/null 2>&1

    assert_file_not_exists "$(config_path)" "nessun config se l'utente rifiuta"
}

# --- Test: uno script v2 non viene scambiato per v1 ---
test_v2_script_not_migrated() {
    local script="$FAKE_HOME/.local/bin/paste-image"
    # Nella v2 le costanti stanno indentate dentro config_defaults()
    cat > "$script" <<'V2'
#!/usr/bin/env bash
set -euo pipefail
VERSION="2.0.0"
config_defaults() {
    MAX_LOG_LINES=999
    CLEANUP_DAYS=30
}
V2

    echo "s" | bash "$MIGRATE" "$script" >/dev/null 2>&1

    assert_file_not_exists "$(config_path)" "script v2 non trattato come v1"
}

# --- Test: script assente, nessun errore ---
test_missing_script_is_noop() {
    local exit_code=0
    bash "$MIGRATE" "$FAKE_HOME/.local/bin/non-esiste" >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code" "nessun errore su script assente"
    assert_file_not_exists "$(config_path)" "nessun config creato"
}

# --- Test: un valore già presente nel config non viene sovrascritto ---
test_existing_config_value_preserved() {
    local script="$FAKE_HOME/.local/bin/paste-image"
    make_v1_script "$script" 999 30 0.5

    local config
    config=$(config_path)
    mkdir -p "$(dirname "$config")"
    printf '# config esistente\nMAX_LOG_LINES=123\n' > "$config"

    echo "s" | bash "$MIGRATE" "$script" >/dev/null 2>&1

    assert_file_contains "$config" "MAX_LOG_LINES=123" "valore preesistente conservato"
    assert_file_not_contains "$config" "MAX_LOG_LINES=999" "valore v1 non sovrascrive"
    assert_file_contains "$config" "CLEANUP_DAYS=30" "le altre chiavi vengono comunque aggiunte"
}

run_test "Valori personalizzati migrati" test_customized_values_migrated
run_test "Valori di fabbrica non migrati" test_default_values_not_migrated
run_test "Migrazione rifiutata: nulla scritto" test_declined_migration_writes_nothing
run_test "Script v2 non scambiato per v1" test_v2_script_not_migrated
run_test "Script assente: nessun errore" test_missing_script_is_noop
run_test "Config esistente non sovrascritto" test_existing_config_value_preserved

print_summary "test_migrate_config.sh"
