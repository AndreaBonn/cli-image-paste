#!/usr/bin/env bash
#
# test_lib_screenshot.sh — Cattura di un'area come sorgente alternativa
#
# La selezione degli strumenti è pura, quindi si verifica per tabella senza
# possedere quei desktop. L'annullamento della selezione va distinto da un
# errore: è una decisione dell'utente, e trattarla come fallimento
# produrrebbe una notifica di errore per un gesto normale.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

_LIB="$(cd "$SCRIPT_DIR/.." && pwd)/lib"
# shellcheck source=../lib/05_text.sh
source "$_LIB/05_text.sh"
# shellcheck source=../lib/10_env_detect.sh
source "$_LIB/10_env_detect.sh"
# shellcheck source=../lib/20_clipboard.sh
source "$_LIB/20_clipboard.sh"
# shellcheck source=../lib/25_source.sh
source "$_LIB/25_source.sh"

VERSION="test"
notify() { echo "notify: $1"; }
log() { :; }

# --- Selezione dello strumento ---

test_native_tool_preferred_per_desktop() {
    setup_restricted_path
    create_mock "gnome-screenshot" ""
    create_mock "spectacle" ""
    create_mock "grim" ""
    create_mock "slurp" ""

    assert_equals "gnome-screenshot" "$(screenshot_tool_for wayland gnome)" \
        "su GNOME vince lo strumento nativo"
    assert_equals "spectacle" "$(screenshot_tool_for wayland kde)" \
        "su KDE vince spectacle"
    assert_equals "grim" "$(screenshot_tool_for wayland sway)" \
        "su sway vince grim"
}

test_falls_back_when_native_missing() {
    setup_restricted_path
    create_mock "grim" ""
    create_mock "slurp" ""

    assert_equals "grim" "$(screenshot_tool_for wayland gnome)" \
        "senza gnome-screenshot si scende a grim"
}

# grim da solo cattura tutto lo schermo: senza slurp non è la stessa
# funzione, quindi non va proposto per una cattura ad area.
test_grim_requires_slurp() {
    setup_restricted_path
    create_mock "grim" ""

    if [ "$(screenshot_tool_for wayland sway)" = "grim" ]; then
        _test_fail "grim proposto senza slurp"
    fi
}

test_grim_accepted_with_slurp() {
    setup_restricted_path
    create_mock "grim" ""
    create_mock "slurp" ""
    assert_equals "grim" "$(screenshot_tool_for wayland sway)" "grim con slurp va bene"
}

test_x11_tools() {
    setup_restricted_path
    create_mock "maim" ""
    assert_equals "maim" "$(screenshot_tool_for x11 altro)" "maim su X11 generico"

    create_mock "flameshot" ""
    assert_equals "flameshot" "$(screenshot_tool_for x11 altro)" "flameshot preferito a maim"
}

test_no_tool_available() {
    setup_restricted_path
    if screenshot_tool_for x11 gnome >/dev/null 2>&1; then
        _test_fail "proposto uno strumento senza che nessuno sia installato"
    fi
}

# --- Cattura ---

test_capture_writes_file() {
    setup_restricted_path
    # shellcheck disable=SC2016 # Apici singoli intenzionali: corpo del mock
    create_mock "maim" 'printf CONTENUTO > "${@: -1}"'

    local dest="$TEST_TMPDIR/out.png"
    local status=0
    screenshot_capture maim "$dest" || status=$?

    assert_exit_code "0" "$status" "cattura riuscita"
    assert_file_exists "$dest" "file scritto"
}

# Alcuni strumenti escono con successo lasciando un file vuoto quando
# l'utente annulla: l'unico segnale affidabile è il contenuto.
test_cancelled_selection_reports_two() {
    setup_restricted_path
    create_mock "maim" "exit 0"

    local dest="$TEST_TMPDIR/vuoto.png"
    local status=0
    screenshot_capture maim "$dest" || status=$?

    assert_exit_code "2" "$status" "annullamento segnalato con codice dedicato"
    assert_file_not_exists "$dest" "nessun file vuoto lasciato in giro"
}

test_failing_tool_reports_error() {
    setup_restricted_path
    create_mock "maim" "exit 1"

    local status=0
    screenshot_capture maim "$TEST_TMPDIR/x.png" || status=$?
    if [ "$status" -eq 0 ]; then
        _test_fail "fallimento della cattura riportato come successo"
    fi
}

test_unknown_tool_fails() {
    local status=0
    screenshot_capture telepatia "$TEST_TMPDIR/x.png" || status=$?
    assert_exit_code "1" "$status" "strumento inesistente"
}

# Ogni strumento ha la propria sintassi per la selezione d'area: sbagliarla
# cattura tutto lo schermo invece della porzione scelta.
test_area_flags_per_tool() {
    setup_restricted_path
    # shellcheck disable=SC2016 # Apici singoli intenzionali: corpo del mock
    create_mock "gnome-screenshot" 'printf X > "${@: -1}"'
    screenshot_capture gnome-screenshot "$TEST_TMPDIR/a.png" >/dev/null 2>&1
    assert_mock_called_with "gnome-screenshot" "-a" "gnome-screenshot con selezione area"

    # shellcheck disable=SC2016
    create_mock "maim" 'printf X > "${@: -1}"'
    screenshot_capture maim "$TEST_TMPDIR/b.png" >/dev/null 2>&1
    assert_mock_called_with "maim" "-s" "maim con selezione"
}

# --- Sorgente completa ---

test_source_from_screenshot_returns_path() {
    setup_restricted_path date
    # shellcheck disable=SC2016 # Apici singoli intenzionali: corpo del mock
    create_mock "maim" 'printf IMMAGINE > "${@: -1}"'
    export PASTE_IMAGE_SESSION_TYPE=x11 PASTE_IMAGE_DESKTOP=altro

    local result
    result=$(source_from_screenshot "$TEST_TMPDIR")

    assert_file_exists "$result" "file catturato esiste"
    assert_file_content_equals "$result" "IMMAGINE" "contenuto della cattura"
    unset PASTE_IMAGE_SESSION_TYPE PASTE_IMAGE_DESKTOP
}

test_source_reports_cancellation_distinctly() {
    setup_restricted_path date
    create_mock "maim" "exit 0"
    export PASTE_IMAGE_SESSION_TYPE=x11 PASTE_IMAGE_DESKTOP=altro

    local status=0 output
    output=$(source_from_screenshot "$TEST_TMPDIR") || status=$?

    assert_exit_code "2" "$status" "annullamento distinto dall'errore"
    assert_not_contains "$output" "notify" "nessuna notifica di errore per un annullamento"
    unset PASTE_IMAGE_SESSION_TYPE PASTE_IMAGE_DESKTOP
}

test_source_without_tool_names_the_alternatives() {
    setup_restricted_path date
    export PASTE_IMAGE_SESSION_TYPE=x11 PASTE_IMAGE_DESKTOP=altro

    local output status=0
    output=$(source_from_screenshot "$TEST_TMPDIR") || status=$?

    assert_exit_code "1" "$status" "errore senza strumenti"
    assert_contains "$output" "grim" "il messaggio nomina le alternative"
    unset PASTE_IMAGE_SESSION_TYPE PASTE_IMAGE_DESKTOP
}

run_test "Strumento nativo preferito per desktop" test_native_tool_preferred_per_desktop
run_test "Ripiego quando il nativo manca" test_falls_back_when_native_missing
run_test "grim richiede slurp" test_grim_requires_slurp
run_test "grim accettato con slurp" test_grim_accepted_with_slurp
run_test "Strumenti X11" test_x11_tools
run_test "Nessuno strumento disponibile" test_no_tool_available
run_test "Cattura scrive il file" test_capture_writes_file
run_test "Annullamento segnalato a parte" test_cancelled_selection_reports_two
run_test "Errore della cattura riportato" test_failing_tool_reports_error
run_test "Strumento sconosciuto" test_unknown_tool_fails
run_test "Flag di selezione per strumento" test_area_flags_per_tool
run_test "Sorgente screenshot restituisce il path" test_source_from_screenshot_returns_path
run_test "Annullamento senza notifica di errore" test_source_reports_cancellation_distinctly
run_test "Senza strumenti nomina le alternative" test_source_without_tool_names_the_alternatives

print_summary "test_lib_screenshot.sh"
