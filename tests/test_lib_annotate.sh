#!/usr/bin/env bash
#
# test_lib_annotate.sh — Annotazione interattiva e diagnostica
#
# L'annotazione è l'unico step richiesto esplicitamente dall'utente: la sua
# assenza è un errore, non una degradazione, perché ignorare un flag appena
# scritto è il peggior esito possibile. Chiudere l'annotatore senza salvare è
# invece una decisione, e va trattata come tale.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

_LIB="$(cd "$SCRIPT_DIR/.." && pwd)/lib"
# shellcheck source=../lib/40_transform.sh
source "$_LIB/40_transform.sh"
# shellcheck source=../lib/45_resize.sh
source "$_LIB/45_resize.sh"

notify() { echo "notify: $1"; }
log() { :; }

# --- Selezione dello strumento ---

test_satty_preferred() {
    setup_restricted_path
    create_mock "satty" ""
    create_mock "swappy" ""
    assert_equals "satty" "$(annotate_tool)" "satty preferito"
}

test_swappy_fallback() {
    setup_restricted_path
    create_mock "swappy" ""
    assert_equals "swappy" "$(annotate_tool)" "swappy usato senza satty"
}

test_no_tool_available() {
    setup_restricted_path
    if annotate_tool >/dev/null 2>&1; then
        _test_fail "strumento riportato presente senza che ce ne sia uno"
    fi
}

test_missing_message_names_a_package() {
    assert_contains "$(annotate_missing_message)" "swappy" "il messaggio nomina cosa installare"
}

# --- Esecuzione ---

test_annotate_writes_output() {
    setup_restricted_path
    # shellcheck disable=SC2016 # Apici singoli intenzionali: corpo del mock
    create_mock "swappy" 'printf ANNOTATA > "${@: -1}"'

    local status=0
    annotate_run swappy "$TEST_TMPDIR/in.png" "$TEST_TMPDIR/out.png" || status=$?

    assert_exit_code "0" "$status" "annotazione riuscita"
    assert_file_content_equals "$TEST_TMPDIR/out.png" "ANNOTATA" "output scritto"
}

# Entrambi gli strumenti possono uscire con successo senza aver salvato:
# l'unico segnale affidabile è se il file di destinazione ha contenuto.
test_closed_without_saving_reports_two() {
    setup_restricted_path
    create_mock "swappy" "exit 0"

    local status=0
    annotate_run swappy "$TEST_TMPDIR/in.png" "$TEST_TMPDIR/out.png" || status=$?

    assert_exit_code "2" "$status" "chiusura senza salvare ha un codice proprio"
    assert_file_not_exists "$TEST_TMPDIR/out.png" "nessun file vuoto lasciato"
}

test_unknown_tool_fails() {
    local status=0
    annotate_run telepatia "$TEST_TMPDIR/in.png" "$TEST_TMPDIR/out.png" || status=$?
    assert_exit_code "1" "$status" "strumento inesistente"
}

# --- Integrazione nella pipeline ---

test_pipeline_returns_annotated_file() {
    setup_restricted_path
    # shellcheck disable=SC2016 # Apici singoli intenzionali: corpo del mock
    create_mock "swappy" 'printf ANNOTATA > "${@: -1}"'
    TRANSFORM_TEMP_DIR="$TEST_TMPDIR"

    local src="$TEST_TMPDIR/originale.png" result
    printf 'ORIGINALE' > "$src"

    result=$(transform_apply_annotate "$src" "$TEST_TMPDIR")

    if [ "$result" = "$src" ]; then
        _test_fail "restituito l'originale invece del file annotato"
        return
    fi
    assert_file_content_equals "$result" "ANNOTATA" "contenuto annotato"
}

# Chiudere senza salvare non deve far fallire l'operazione: si consegna
# l'immagine originale, che è quello che l'utente si aspetta.
test_pipeline_falls_back_to_original() {
    setup_restricted_path
    create_mock "swappy" "exit 0"
    TRANSFORM_TEMP_DIR="$TEST_TMPDIR"

    local src="$TEST_TMPDIR/originale.png" result status=0
    printf 'ORIGINALE' > "$src"

    result=$(transform_apply_annotate "$src" "$TEST_TMPDIR") || status=$?

    assert_exit_code "0" "$status" "nessun errore per una chiusura volontaria"
    assert_equals "$src" "$result" "consegnato l'originale"
}

# Un flag scritto dall'utente non va ignorato: senza strumento è un errore.
test_pipeline_fails_without_tool() {
    setup_restricted_path
    TRANSFORM_TEMP_DIR="$TEST_TMPDIR"

    local src="$TEST_TMPDIR/originale.png" output status=0
    printf 'ORIGINALE' > "$src"

    output=$(transform_apply_annotate "$src" "$TEST_TMPDIR") || status=$?

    assert_exit_code "1" "$status" "assenza dello strumento è un errore"
    assert_contains "$output" "swappy" "la notifica dice cosa installare"
}

run_test "satty preferito a swappy" test_satty_preferred
run_test "swappy come ripiego" test_swappy_fallback
run_test "Nessuno strumento disponibile" test_no_tool_available
run_test "Il messaggio nomina il pacchetto" test_missing_message_names_a_package
run_test "Annotazione scrive l'output" test_annotate_writes_output
run_test "Chiusura senza salvare" test_closed_without_saving_reports_two
run_test "Strumento sconosciuto" test_unknown_tool_fails
run_test "Pipeline restituisce il file annotato" test_pipeline_returns_annotated_file
run_test "Pipeline ripiega sull'originale" test_pipeline_falls_back_to_original
run_test "Pipeline fallisce senza strumento" test_pipeline_fails_without_tool

print_summary "test_lib_annotate.sh"
