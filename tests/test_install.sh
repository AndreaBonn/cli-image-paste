#!/usr/bin/env bash
#
# test_install.sh — Test per install.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

INSTALL_SCRIPT="$PROJECT_DIR/install.sh"

# Helper: setup minimo per install
setup_install_env() {
    setup_restricted_path pgrep diff python3
    create_mock "apt" ""
    create_mock "xclip" ""
    create_mock "xdotool" ""
    create_mock "notify-send" ""
    create_mock "sudo" ""
    # shellcheck disable=SC2016 # Single quotes intenzionali: corpo dello script mock
    create_mock "pgrep" 'if [ "$2" = "gsd-media-keys" ]; then exit 0; fi'
    create_mock "systemctl" ""
}

# Helper: esegui install con stdin fornito
run_install() {
    local stdin_data="$1"
    echo -e "$stdin_data" | bash "$INSTALL_SCRIPT" 2>&1
}

# --- Test 1: Installazione completa ---
test_complete_install() {
    setup_install_env
    create_gsettings_mock "@as []"

    local output
    output=$(run_install "\n") || true

    # Script copiato e identico all'originale
    assert_file_exists "$FAKE_HOME/.local/bin/paste-image" "script copiato"
    if [ ! -x "$FAKE_HOME/.local/bin/paste-image" ]; then
        _test_fail "script non eseguibile"
    fi
    # Verifica integrità: file copiato identico all'originale
    if ! diff -q "$PROJECT_DIR/paste-image" "$FAKE_HOME/.local/bin/paste-image" >/dev/null 2>&1; then
        _test_fail "file copiato non identico all'originale"
    fi
    # gsettings: array contiene paste-image
    local bindings
    bindings=$(cat "$GSETTINGS_STATE/custom-keybindings")
    assert_contains "$bindings" "paste-image" "binding aggiunto all'array"
    assert_gsettings_array_valid "$bindings" "array risultante valido"
    assert_contains "$output" "Installazione completata" "messaggio completamento"
}

# --- Test 2: Dipendenze mancanti, utente accetta ---
test_missing_deps_accept() {
    setup_install_env
    create_gsettings_mock "@as []"
    rm -f "$MOCK_BIN/xclip" "$MOCK_BIN/xdotool" "$MOCK_BIN/notify-send"

    local output
    output=$(run_install "S\n\n") || true

    # Verifica che apt install sia chiamato con i pacchetti SPECIFICI
    assert_mock_called_with "sudo" "apt.*install" "apt install chiamato"
    assert_mock_called_with "sudo" "xclip" "pacchetto xclip richiesto"
    assert_mock_called_with "sudo" "xdotool" "pacchetto xdotool richiesto"
    assert_mock_called_with "sudo" "libnotify-bin" "pacchetto libnotify-bin richiesto"
}

# --- Test 3: Dipendenze mancanti, utente rifiuta ---
test_missing_deps_reject() {
    setup_install_env
    create_gsettings_mock "@as []"
    rm -f "$MOCK_BIN/xclip" "$MOCK_BIN/xdotool" "$MOCK_BIN/notify-send"

    local exit_code=0
    run_install "n\n" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "1" "$exit_code" "exit code"
    assert_file_not_exists "$FAKE_HOME/.local/bin/paste-image" "script non installato"
}

# --- Test 4: PATH aggiunto a .bashrc ---
test_path_added_bashrc() {
    setup_install_env
    create_gsettings_mock "@as []"
    echo "# empty bashrc" > "$FAKE_HOME/.bashrc"
    # Rimuovi .local/bin dal PATH
    local clean_path
    clean_path=$(echo "$PATH" | tr ':' '\n' | grep -v '.local/bin' | tr '\n' ':' | sed 's/:$//')
    export PATH="$MOCK_BIN:$TEST_TMPDIR/sys_bin:$clean_path"

    run_install "\n" >/dev/null 2>&1 || true

    # Verifica la riga export completa, non solo la sottostringa
    # shellcheck disable=SC2016 # Single quotes intenzionali: cerchiamo il letterale $HOME/$PATH nel file
    assert_file_contains "$FAKE_HOME/.bashrc" 'export PATH="$HOME/.local/bin:$PATH"' "linea export completa in .bashrc"
}

# --- Test 5: PATH non duplicato in .bashrc ---
test_path_not_duplicated() {
    setup_install_env
    create_gsettings_mock "@as []"
    # shellcheck disable=SC2016 # Single quotes intenzionali: scriviamo il letterale $HOME/$PATH
    echo 'export PATH="$HOME/.local/bin:$PATH"' > "$FAKE_HOME/.bashrc"

    run_install "\n" >/dev/null 2>&1 || true

    local count
    count=$(grep -c '.local/bin' "$FAKE_HOME/.bashrc")
    assert_equals "1" "$count" "PATH non duplicato (idempotente)"
}

# --- Test 6: PATH aggiunto a .zshrc ---
test_path_added_zshrc() {
    setup_install_env
    create_gsettings_mock "@as []"
    echo "# empty zshrc" > "$FAKE_HOME/.zshrc"
    # Rimuovi .local/bin dal PATH
    local clean_path
    clean_path=$(echo "$PATH" | tr ':' '\n' | grep -v '.local/bin' | tr '\n' ':' | sed 's/:$//')
    export PATH="$MOCK_BIN:$TEST_TMPDIR/sys_bin:$clean_path"

    run_install "\n" >/dev/null 2>&1 || true

    # shellcheck disable=SC2016 # Single quotes intenzionali: cerchiamo il letterale $HOME/$PATH nel file
    assert_file_contains "$FAKE_HOME/.zshrc" 'export PATH="$HOME/.local/bin:$PATH"' "linea export in .zshrc"
}

# --- Test 7: Array gsettings: 0 binding → aggiunge ---
test_gsettings_empty_array() {
    setup_install_env
    create_gsettings_mock "@as []"

    run_install "\n" >/dev/null 2>&1 || true

    local bindings
    bindings=$(cat "$GSETTINGS_STATE/custom-keybindings")
    assert_contains "$bindings" "paste-image" "paste-image aggiunto"
    assert_gsettings_array_valid "$bindings" "sintassi array valida"
}

# --- Test 8: Array gsettings: 1 binding → appende ---
test_gsettings_one_existing() {
    setup_install_env
    local other="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/other/"
    create_gsettings_mock "['${other}']"

    run_install "\n" >/dev/null 2>&1 || true

    local bindings
    bindings=$(cat "$GSETTINGS_STATE/custom-keybindings")
    assert_contains "$bindings" "$other" "binding esistente preservato"
    assert_contains "$bindings" "paste-image" "paste-image appeso"
    assert_gsettings_array_valid "$bindings" "sintassi array valida"
}

# --- Test 9: Array gsettings: N binding → appende ---
test_gsettings_multiple_existing() {
    setup_install_env
    local a="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/a/"
    local b="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/b/"
    local c="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/c/"
    create_gsettings_mock "['${a}', '${b}', '${c}']"

    run_install "\n" >/dev/null 2>&1 || true

    local bindings
    bindings=$(cat "$GSETTINGS_STATE/custom-keybindings")
    assert_contains "$bindings" "$a" "binding a preservato"
    assert_contains "$bindings" "$b" "binding b preservato"
    assert_contains "$bindings" "$c" "binding c preservato"
    assert_contains "$bindings" "paste-image" "paste-image appeso"
    assert_gsettings_array_valid "$bindings" "sintassi array valida con N+1 elementi"
}

# --- Test 10: Reinstallazione idempotente ---
test_reinstall_idempotent() {
    setup_install_env
    local bp="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/paste-image/"
    local other="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/other/"
    create_gsettings_mock "['${other}', '${bp}']"

    run_install "\n" >/dev/null 2>&1 || true

    local bindings
    bindings=$(cat "$GSETTINGS_STATE/custom-keybindings")
    local count
    count=$(echo "$bindings" | grep -o "paste-image" | wc -l)
    assert_equals "1" "$count" "paste-image presente una sola volta"
    assert_contains "$bindings" "$other" "other binding preservato"
    assert_gsettings_array_valid "$bindings" "array ancora valido"
}

# --- Test 11: Shortcut custom ---
test_custom_shortcut() {
    setup_install_env
    create_gsettings_mock "@as []"

    run_install "<Control><Alt>v\n" >/dev/null 2>&1 || true

    # Verifica tutti e tre i campi del binding (name, command, binding)
    assert_mock_called_with "gsettings" "set.*name.*Paste Image" "name impostato"
    assert_mock_called_with "gsettings" "set.*command.*paste-image" "command impostato"
    assert_mock_called_with "gsettings" "set.*binding.*<Control><Alt>v" "binding custom impostato"
}

# --- Test 12: Conflitto shortcut rilevato ---
test_shortcut_conflict_detected() {
    setup_install_env
    local other_path="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/other/"
    create_gsettings_mock "['${other_path}']"

    # Pre-imposta le proprietà del binding esistente con lo stesso shortcut del default
    local binding_state
    binding_state="$GSETTINGS_STATE/binding_binding_$(echo "$other_path" | tr '/' '_')"
    local name_state
    name_state="$GSETTINGS_STATE/binding_name_$(echo "$other_path" | tr '/' '_')"
    echo "'<Control><Shift>v'" > "$binding_state"
    echo "'Other Tool'" > "$name_state"

    # Input: enter (accetta default <Control><Shift>v che confligge), poi "s" (usa comunque)
    local output
    output=$(run_install "\ns\n") || true

    # Deve mostrare avviso conflitto con nome del binding esistente
    assert_contains "$output" "ATTENZIONE" "avviso conflitto mostrato"
    assert_contains "$output" "Other Tool" "nome binding conflittuale mostrato"
    assert_contains "$output" "<Control><Shift>v" "shortcut conflittuale mostrato"
}

# --- Esecuzione ---

echo "=== test_install.sh ==="

run_test "Installazione completa" test_complete_install
run_test "Dipendenze mancanti, accetta" test_missing_deps_accept
run_test "Dipendenze mancanti, rifiuta" test_missing_deps_reject
run_test "PATH aggiunto a .bashrc" test_path_added_bashrc
run_test "PATH non duplicato in .bashrc" test_path_not_duplicated
run_test "PATH aggiunto a .zshrc" test_path_added_zshrc
run_test "gsettings: 0 binding → aggiunge" test_gsettings_empty_array
run_test "gsettings: 1 binding → appende" test_gsettings_one_existing
run_test "gsettings: N binding → appende" test_gsettings_multiple_existing
run_test "Reinstallazione idempotente" test_reinstall_idempotent
run_test "Shortcut custom" test_custom_shortcut
run_test "Conflitto shortcut rilevato" test_shortcut_conflict_detected

print_summary "test_install.sh"
