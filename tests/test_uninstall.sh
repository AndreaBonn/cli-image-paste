#!/usr/bin/env bash
#
# test_uninstall.sh — Test per uninstall.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

UNINSTALL_SCRIPT="$PROJECT_DIR/uninstall.sh"

# Helper: esegui uninstall in ambiente isolato
run_uninstall() {
    bash "$UNINSTALL_SCRIPT" 2>&1
}

# --- Test 1: Script rimosso ---
test_script_removed() {
    create_gsettings_mock "@as []"
    cp "$UNINSTALL_SCRIPT" "$FAKE_HOME/.local/bin/paste-image"
    chmod +x "$FAKE_HOME/.local/bin/paste-image"

    local output
    output=$(run_uninstall) || true

    assert_file_not_exists "$FAKE_HOME/.local/bin/paste-image" "script rimosso"
    assert_contains "$output" "Script rimosso" "messaggio rimozione"
}

# --- Test 2: Script già assente ---
test_script_already_absent() {
    create_gsettings_mock "@as []"

    local output
    output=$(run_uninstall) || true

    assert_contains "$output" "già rimosso" "messaggio già rimosso"
}

# --- Test 3: Unico binding → array vuoto ---
test_single_binding_removed() {
    local bp="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/paste-image/"
    create_gsettings_mock "['${bp}']"
    touch "$FAKE_HOME/.local/bin/paste-image"

    run_uninstall >/dev/null 2>&1 || true

    local result
    result=$(cat "$GSETTINGS_STATE/custom-keybindings")
    assert_equals "@as []" "$result" "array vuoto dopo rimozione unico binding"

    # Verifica che reset sia stato chiamato per name, command, binding
    assert_mock_called_with "gsettings" "reset.*name" "reset name"
    assert_mock_called_with "gsettings" "reset.*command" "reset command"
    assert_mock_called_with "gsettings" "reset.*binding" "reset binding"
}

# --- Test 4: Binding alla fine ---
test_binding_at_end() {
    local other="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/other/"
    local bp="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/paste-image/"
    create_gsettings_mock "['${other}', '${bp}']"
    touch "$FAKE_HOME/.local/bin/paste-image"

    run_uninstall >/dev/null 2>&1 || true

    local result
    result=$(cat "$GSETTINGS_STATE/custom-keybindings")
    assert_contains "$result" "$other" "other binding preservato"
    assert_not_contains "$result" "paste-image" "paste-image rimosso"
    assert_gsettings_array_valid "$result" "array risultante valido"
}

# --- Test 5: Binding all'inizio ---
test_binding_at_start() {
    local bp="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/paste-image/"
    local other="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/other/"
    create_gsettings_mock "['${bp}', '${other}']"
    touch "$FAKE_HOME/.local/bin/paste-image"

    run_uninstall >/dev/null 2>&1 || true

    local result
    result=$(cat "$GSETTINGS_STATE/custom-keybindings")
    assert_contains "$result" "$other" "other binding preservato"
    assert_not_contains "$result" "paste-image" "paste-image rimosso"
    assert_gsettings_array_valid "$result" "array risultante valido"
}

# --- Test 6: Binding in mezzo ---
test_binding_in_middle() {
    local a="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/a/"
    local bp="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/paste-image/"
    local c="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/c/"
    create_gsettings_mock "['${a}', '${bp}', '${c}']"
    touch "$FAKE_HOME/.local/bin/paste-image"

    run_uninstall >/dev/null 2>&1 || true

    local result
    result=$(cat "$GSETTINGS_STATE/custom-keybindings")
    assert_contains "$result" "$a" "binding a preservato"
    assert_contains "$result" "$c" "binding c preservato"
    assert_not_contains "$result" "paste-image" "paste-image rimosso"
    assert_gsettings_array_valid "$result" "array risultante valido"
}

# --- Test 7: Binding non trovato ---
test_binding_not_found() {
    local a="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/a/"
    local b="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/b/"
    create_gsettings_mock "['${a}', '${b}']"
    touch "$FAKE_HOME/.local/bin/paste-image"

    local output
    output=$(run_uninstall) || true

    assert_contains "$output" "Nessuno shortcut" "messaggio nessuno shortcut"
    # gsettings set NON deve essere chiamato per l'array custom-keybindings
    if grep -q "gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings" "$MOCK_CALL_LOG" 2>/dev/null; then
        _test_fail "gsettings set non doveva essere chiamato per custom-keybindings"
    fi
}

# --- Esecuzione ---

echo "=== test_uninstall.sh ==="

run_test "Script rimosso" test_script_removed
run_test "Script già assente" test_script_already_absent
run_test "Unico binding → array vuoto" test_single_binding_removed
run_test "Binding alla fine" test_binding_at_end
run_test "Binding all'inizio" test_binding_at_start
run_test "Binding in mezzo" test_binding_in_middle
run_test "Binding non trovato" test_binding_not_found

print_summary "test_uninstall.sh"
