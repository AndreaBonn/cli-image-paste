#!/usr/bin/env bash
#
# test_install_shortcut.sh — Registrazione della scorciatoia e dispatcher
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"
# shellcheck source=framework/install_helpers.sh
source "$SCRIPT_DIR/framework/install_helpers.sh"

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

# --- Dispatcher multi-desktop ---

# Su un window manager non esiste un registro da scrivere: l'installer deve
# stampare la riga di configurazione e non toccare gsettings, che su quei
# sistemi non esiste nemmeno.
test_window_manager_prints_config_line() {
    setup_install_env
    create_gsettings_mock "@as []"
    export PASTE_IMAGE_DESKTOP=sway

    local output
    output=$(run_install "\n") || true
    unset PASTE_IMAGE_DESKTOP

    assert_contains "$output" "bindsym" "stampata la riga per sway"
    assert_contains "$output" "config" "nominato il file di configurazione"
    assert_contains "$output" "Installazione completata" "installazione conclusa"
    assert_file_exists "$FAKE_HOME/.local/bin/paste-image" "eseguibile installato comunque"
    assert_mock_not_called_with_arg "gsettings" "set" "gsettings non viene toccato"
}

test_hyprland_prints_its_own_syntax() {
    setup_install_env
    create_gsettings_mock "@as []"
    export PASTE_IMAGE_DESKTOP=hyprland

    local output
    output=$(run_install "\n") || true
    unset PASTE_IMAGE_DESKTOP

    assert_contains "$output" "bind =" "sintassi di Hyprland, non quella di sway"
    assert_contains "$output" "hyprland.conf" "nominato il file corretto"
}

# Un desktop che non conosciamo non deve far fallire l'installazione: il
# tool resta usabile a mano, e la scorciatoia si registra dalle impostazioni.
test_unknown_desktop_still_installs() {
    setup_install_env
    create_gsettings_mock "@as []"
    export PASTE_IMAGE_DESKTOP=QualcosaDiIgnoto

    local output exit_code=0
    output=$(run_install "\n") || exit_code=$?
    unset PASTE_IMAGE_DESKTOP

    assert_exit_code "0" "$exit_code" "installazione riuscita comunque"
    assert_file_exists "$FAKE_HOME/.local/bin/paste-image" "eseguibile installato"
    assert_contains "$output" "non gestito automaticamente" "lo dichiara apertamente"
    assert_contains "$output" "paste-image" "indica il comando da associare"
}

run_test "gsettings: 0 binding → aggiunge" test_gsettings_empty_array
run_test "gsettings: 1 binding → appende" test_gsettings_one_existing
run_test "gsettings: N binding → appende" test_gsettings_multiple_existing
run_test "Reinstallazione idempotente" test_reinstall_idempotent
run_test "Shortcut custom" test_custom_shortcut
run_test "Conflitto shortcut rilevato" test_shortcut_conflict_detected
run_test "Window manager: stampa la riga di config" test_window_manager_prints_config_line
run_test "Hyprland: sintassi propria" test_hyprland_prints_its_own_syntax
run_test "Desktop ignoto: installa comunque" test_unknown_desktop_still_installs

print_summary "test_install_shortcut.sh"
