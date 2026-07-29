#!/usr/bin/env bash
#
# test_install.sh — Dipendenze, PATH e copia dell'eseguibile
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"
# shellcheck source=framework/install_helpers.sh
source "$SCRIPT_DIR/framework/install_helpers.sh"

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
    # Verifica integrità: file copiato identico all'artefatto generato
    if ! diff -q "$PROJECT_DIR/dist/paste-image" "$FAKE_HOME/.local/bin/paste-image" >/dev/null 2>&1; then
        _test_fail "file copiato non identico all'artefatto"
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
    # xdotool non è più indispensabile: senza di esso la consegna ripiega
    # sugli appunti, quindi finisce fra le opzionali e non viene installato
    # insieme al resto.
    assert_mock_not_called_with_arg "sudo" "xdotool" "xdotool non è fra le indispensabili"
    assert_mock_not_called_with_arg "sudo" "libnotify-bin" "notify-send non è fra le indispensabili"
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

run_test "Installazione completa" test_complete_install
run_test "Dipendenze mancanti, accetta" test_missing_deps_accept
run_test "Dipendenze mancanti, rifiuta" test_missing_deps_reject
run_test "PATH aggiunto a .bashrc" test_path_added_bashrc
run_test "PATH non duplicato in .bashrc" test_path_not_duplicated
run_test "PATH aggiunto a .zshrc" test_path_added_zshrc

print_summary "test_install.sh"
