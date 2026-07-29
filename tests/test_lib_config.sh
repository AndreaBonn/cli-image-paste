#!/usr/bin/env bash
#
# test_lib_config.sh — Parser di configurazione (livello L1, modulo sorgiato)
#
# Il template di formato ha una suite dedicata di input ostili: quel valore
# finisce digitato nel terminale a ogni invocazione, quindi un valore
# malevolo accettato qui persiste, a differenza di un path che arriva una
# volta sola dagli appunti.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

# shellcheck source=../lib/15_config.sh
source "$(cd "$SCRIPT_DIR/.." && pwd)/lib/15_config.sh"

# Caratteri di controllo costruiti fuori dalle stringhe letterali,
# così restano leggibili nel sorgente del test.
CR=$'\r'
ESC=$'\033'

# Helper: scrive un file di configurazione temporaneo e lo carica
load_config_text() {
    local text="$1"
    local file="$TEST_TMPDIR/config"
    printf '%s\n' "$text" > "$file"
    config_defaults
    config_load_file "$file"
}

warnings_count() {
    echo "${#CONFIG_WARNINGS[@]}"
}

warnings_text() {
    printf '%s\n' ${CONFIG_WARNINGS+"${CONFIG_WARNINGS[@]}"}
}

# --- Default ---

test_defaults_applied() {
    config_defaults
    assert_equals "500" "$MAX_LOG_LINES" "MAX_LOG_LINES"
    assert_equals "7" "$CLEANUP_DAYS" "CLEANUP_DAYS"
    assert_equals "/tmp" "$OUTPUT_DIR" "OUTPUT_DIR"
    assert_equals "1568" "$MAX_LONG_SIDE" "MAX_LONG_SIDE"
    assert_equals "1" "$PREFER_EXISTING_FILE" "PREFER_EXISTING_FILE"
}

test_missing_file_keeps_defaults() {
    config_defaults
    config_load_file "$TEST_TMPDIR/non-esiste"
    assert_equals "500" "$MAX_LOG_LINES" "default preservato"
    assert_equals "0" "$(warnings_count)" "nessun warning per file assente"
}

# --- Precedenza ---

test_file_overrides_default() {
    load_config_text "MAX_LONG_SIDE=800"
    assert_equals "800" "$MAX_LONG_SIDE" "file vince sul default"
}

test_env_overrides_file() {
    load_config_text "MAX_LONG_SIDE=800"
    export PASTE_IMAGE_MAX_LONG_SIDE=1024
    config_apply_env
    unset PASTE_IMAGE_MAX_LONG_SIDE
    assert_equals "1024" "$MAX_LONG_SIDE" "ambiente vince sul file"
}

test_env_invalid_keeps_previous() {
    load_config_text "MAX_LONG_SIDE=800"
    export PASTE_IMAGE_MAX_LONG_SIDE="molto grande"
    config_apply_env
    unset PASTE_IMAGE_MAX_LONG_SIDE
    assert_equals "800" "$MAX_LONG_SIDE" "valore precedente mantenuto"
    assert_contains "$(warnings_text)" "PASTE_IMAGE_MAX_LONG_SIDE" "warning emesso"
}

# --- Parsing ---

test_comments_and_blank_lines_ignored() {
    load_config_text "# commento

   # commento indentato
MAX_LONG_SIDE=640"
    assert_equals "640" "$MAX_LONG_SIDE" "valore letto"
    assert_equals "0" "$(warnings_count)" "commenti non generano warning"
}

test_quoted_values_unquoted() {
    load_config_text 'OUTPUT_DIR="/var/tmp"'
    assert_equals "/var/tmp" "$OUTPUT_DIR" "virgolette rimosse"
}

test_whitespace_trimmed() {
    load_config_text "  MAX_LONG_SIDE  =  512  "
    assert_equals "512" "$MAX_LONG_SIDE" "spazi rimossi da chiave e valore"
}

test_unknown_key_rejected() {
    load_config_text "COMANDO_ARBITRARIO=rm -rf /"
    assert_equals "1" "$(warnings_count)" "una anomalia registrata"
    assert_contains "$(warnings_text)" "sconosciuta" "warning di chiave sconosciuta"
}

test_line_without_equals_rejected() {
    load_config_text "questa non e' una assegnazione"
    assert_contains "$(warnings_text)" "senza '='" "warning di riga malformata"
}

# --- Validazione per tipo ---

test_invalid_int_keeps_default() {
    load_config_text "CLEANUP_DAYS=sette"
    assert_equals "7" "$CLEANUP_DAYS" "default mantenuto"
    assert_contains "$(warnings_text)" "CLEANUP_DAYS" "warning nomina la chiave"
}

test_relative_path_rejected() {
    load_config_text "OUTPUT_DIR=tmp/immagini"
    assert_equals "/tmp" "$OUTPUT_DIR" "path relativo rifiutato"
}

test_invalid_backend_rejected() {
    load_config_text "TYPING_BACKEND=telepatia"
    assert_equals "" "$TYPING_BACKEND" "backend fuori enum rifiutato"
}

test_valid_backend_accepted() {
    load_config_text "TYPING_BACKEND=wtype"
    assert_equals "wtype" "$TYPING_BACKEND" "backend valido accettato"
}

test_invalid_bool_rejected() {
    load_config_text "PREFER_EXISTING_FILE=yes"
    assert_equals "1" "$PREFER_EXISTING_FILE" "bool non numerico rifiutato"
}

test_decimal_accepted() {
    load_config_text "TYPING_DELAY=0.25"
    assert_equals "0.25" "$TYPING_DELAY" "decimale accettato"
}

# --- Template di formato: tabella di input ostili ---

test_template_valid_forms_accepted() {
    local template
    for template in "/add %s" "@%s" "%s" "read_file %s"; do
        config_defaults
        if ! _config_valid_template "$template"; then
            _test_fail "template legittimo rifiutato: '$template'"
        fi
    done
}

test_template_hostile_forms_rejected() {
    local template desc
    # Ogni voce: descrizione|template
    local casi=(
        "newline che esegue il comando|/add %s
rm -rf ~"
        "carriage return|/add %s${CR}id"
        "escape ANSI|/add %s${ESC}[31m"
        "nessun segnaposto|/add file.png"
        "due segnaposti|/add %s %s"
        "sostituzione shell|/add \$(id) %s"
        "backtick|/add \`id\` %s"
        "punto e virgola|/add %s; id"
        "pipe|/add %s | sh"
    )

    for caso in "${casi[@]}"; do
        desc="${caso%%|*}"
        template="${caso#*|}"
        if _config_valid_template "$template"; then
            _test_fail "template ostile accettato ($desc)"
        fi
    done
}

test_template_too_long_rejected() {
    local long
    long="/add %s$(printf 'a%.0s' $(seq 1 250))"
    if _config_valid_template "$long"; then
        _test_fail "template oltre 200 caratteri accettato"
    fi
}

test_template_hostile_from_file_not_applied() {
    load_config_text "FORMAT_TEMPLATE=/add %s; rm -rf ~"
    assert_equals "" "$FORMAT_TEMPLATE" "template ostile non applicato"
    assert_contains "$(warnings_text)" "FORMAT_TEMPLATE" "warning nomina la chiave"
}

test_template_valid_from_file_applied() {
    load_config_text "FORMAT_TEMPLATE=/add %s"
    assert_equals "/add %s" "$FORMAT_TEMPLATE" "template legittimo applicato"
}

run_test "Default applicati" test_defaults_applied
run_test "File assente: default preservati" test_missing_file_keeps_defaults
run_test "File vince sul default" test_file_overrides_default
run_test "Ambiente vince sul file" test_env_overrides_file
run_test "Ambiente non valido: valore precedente" test_env_invalid_keeps_previous
run_test "Commenti e righe vuote ignorati" test_comments_and_blank_lines_ignored
run_test "Virgolette rimosse dal valore" test_quoted_values_unquoted
run_test "Spazi rimossi da chiave e valore" test_whitespace_trimmed
run_test "Chiave sconosciuta rifiutata" test_unknown_key_rejected
run_test "Riga senza '=' rifiutata" test_line_without_equals_rejected
run_test "Intero non valido: default" test_invalid_int_keeps_default
run_test "Path relativo rifiutato" test_relative_path_rejected
run_test "Backend fuori enum rifiutato" test_invalid_backend_rejected
run_test "Backend valido accettato" test_valid_backend_accepted
run_test "Bool non numerico rifiutato" test_invalid_bool_rejected
run_test "Decimale accettato" test_decimal_accepted
run_test "Template: forme legittime accettate" test_template_valid_forms_accepted
run_test "Template: forme ostili rifiutate" test_template_hostile_forms_rejected
run_test "Template: oltre 200 caratteri rifiutato" test_template_too_long_rejected
run_test "Template ostile da file non applicato" test_template_hostile_from_file_not_applied
run_test "Template legittimo da file applicato" test_template_valid_from_file_applied

print_summary "test_lib_config.sh"
