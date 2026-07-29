#!/usr/bin/env bash
#
# test_lib_shortcut.sh — Conversione delle scorciatoie fra desktop (L1)
#
# Sbagliare il nome di un modificatore produce una scorciatoia registrata ma
# inerte, che è il caso più difficile da diagnosticare per chi installa. Le
# conversioni sono pure, quindi si verificano per tabella senza possedere
# quei desktop.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

# shellcheck source=../lib/60_shortcut.sh
source "$(cd "$SCRIPT_DIR/.." && pwd)/lib/60_shortcut.sh"

# --- Validazione del formato canonico ---

test_valid_gtk_forms() {
    local spec
    for spec in "<Control><Shift>v" "<Super>Print" "<Alt>F1" \
                "<Control>KP_Enter" "<Control><Alt><Shift>x"; do
        if ! shortcut_validate_gtk "$spec"; then
            _test_fail "formato GTK legittimo rifiutato: '$spec'"
        fi
    done
}

test_invalid_gtk_forms() {
    local spec
    for spec in "Control+v" "<Control>" "v" "" "<Control><Shift>" \
                "<Control>v; rm -rf /" "<Control>v v"; do
        if shortcut_validate_gtk "$spec"; then
            _test_fail "formato non valido accettato: '$spec'"
        fi
    done
}

# --- Scomposizione ---

test_key_extraction() {
    assert_equals "v" "$(shortcut_key_of "<Control><Shift>v")" "tasto singolo"
    assert_equals "Print" "$(shortcut_key_of "<Super>Print")" "tasto con nome"
    assert_equals "KP_Enter" "$(shortcut_key_of "<Control>KP_Enter")" "tasto con underscore"
}

test_modifier_extraction() {
    local mods
    mods=$(shortcut_modifiers_of "<Control><Shift>v")
    assert_contains "$mods" "control" "primo modificatore"
    assert_contains "$mods" "shift" "secondo modificatore"

    mods=$(shortcut_modifiers_of "<Super>Print")
    assert_equals "super" "$mods" "modificatore singolo"
}

# --- Conversioni per ambiente ---

test_kde_conversion() {
    local casi=(
        "<Control><Shift>v|Ctrl+Shift+V"
        "<Super>v|Meta+V"
        "<Control><Alt>v|Ctrl+Alt+V"
        "<Super>Print|Meta+Print"
    )
    local caso input atteso
    for caso in "${casi[@]}"; do
        input="${caso%%|*}"
        atteso="${caso##*|}"
        assert_equals "$atteso" "$(shortcut_gtk_to_kde "$input")" "KDE: $input"
    done
}

# sway e i3 chiamano Mod4 il tasto Super e Mod1 Alt: usare i nomi GTK
# produrrebbe una configurazione che il window manager rifiuta.
test_sway_conversion() {
    local casi=(
        "<Control><Shift>v|Control+Shift+v"
        "<Super>v|Mod4+v"
        "<Alt>v|Mod1+v"
        "<Super><Shift>Print|Mod4+Shift+print"
    )
    local caso input atteso
    for caso in "${casi[@]}"; do
        input="${caso%%|*}"
        atteso="${caso##*|}"
        assert_equals "$atteso" "$(shortcut_gtk_to_sway "$input")" "sway: $input"
    done
}

test_hyprland_conversion() {
    assert_equals "CTRL SHIFT, v" "$(shortcut_gtk_to_hyprland "<Control><Shift>v")" \
        "Hyprland separa i modificatori dal tasto con una virgola"
    assert_equals "SUPER, v" "$(shortcut_gtk_to_hyprland "<Super>v")" "Hyprland con Super"
}

test_i3_conversion() {
    assert_equals "Mod4+v" "$(shortcut_gtk_to_i3 "<Super>v")" "i3 usa Mod4 come sway"
}

test_unknown_modifier_rejected() {
    if shortcut_gtk_to_kde "<Iperspazio>v" >/dev/null 2>&1; then
        _test_fail "modificatore inesistente accettato"
    fi
}

test_invalid_input_rejected_by_converters() {
    local fn
    for fn in shortcut_gtk_to_kde shortcut_gtk_to_sway shortcut_gtk_to_i3 \
              shortcut_gtk_to_hyprland; do
        if "$fn" "Control+v" >/dev/null 2>&1; then
            _test_fail "$fn ha accettato un formato non canonico"
        fi
    done
}

# --- Righe di configurazione ---

test_sway_config_line() {
    local line
    line=$(shortcut_config_line sway "<Super>v" "/home/utente/.local/bin/paste-image")
    assert_equals "bindsym Mod4+v exec /home/utente/.local/bin/paste-image" "$line" \
        "riga per sway"
}

test_i3_config_line() {
    local line
    line=$(shortcut_config_line i3 "<Super>v" "/opt/paste-image")
    assert_contains "$line" "--no-startup-id" "i3 evita l'attesa di startup notification"
    assert_contains "$line" "Mod4+v" "scorciatoia convertita"
}

test_hyprland_config_line() {
    local line
    line=$(shortcut_config_line hyprland "<Control><Shift>v" "/opt/paste-image")
    assert_equals "bind = CTRL SHIFT, v, exec, /opt/paste-image" "$line" "riga per Hyprland"
}

test_unknown_wm_has_no_config_line() {
    if shortcut_config_line telepatia "<Super>v" "/opt/x" >/dev/null 2>&1; then
        _test_fail "generata una riga per un ambiente sconosciuto"
    fi
}

# shellcheck disable=SC2088 # La tilde è l'etichetta attesa, non un percorso
test_config_file_paths() {
    assert_equals "~/.config/sway/config" "$(shortcut_config_file_label sway)" "sway"
    assert_equals "~/.config/i3/config" "$(shortcut_config_file_label i3)" "i3"
    assert_equals "~/.config/hypr/hyprland.conf" "$(shortcut_config_file_label hyprland)" "hyprland"
    if shortcut_config_file_label gnome >/dev/null 2>&1; then
        _test_fail "GNOME non ha un file di configurazione da stampare"
    fi
}

run_test "Formati GTK legittimi" test_valid_gtk_forms
run_test "Formati GTK non validi" test_invalid_gtk_forms
run_test "Estrazione del tasto" test_key_extraction
run_test "Estrazione dei modificatori" test_modifier_extraction
run_test "Conversione per KDE" test_kde_conversion
run_test "Conversione per sway" test_sway_conversion
run_test "Conversione per Hyprland" test_hyprland_conversion
run_test "Conversione per i3" test_i3_conversion
run_test "Modificatore sconosciuto rifiutato" test_unknown_modifier_rejected
run_test "Input non canonico rifiutato" test_invalid_input_rejected_by_converters
run_test "Riga di configurazione sway" test_sway_config_line
run_test "Riga di configurazione i3" test_i3_config_line
run_test "Riga di configurazione Hyprland" test_hyprland_config_line
run_test "Nessuna riga per ambiente ignoto" test_unknown_wm_has_no_config_line
run_test "Percorsi dei file di configurazione" test_config_file_paths

print_summary "test_lib_shortcut.sh"
