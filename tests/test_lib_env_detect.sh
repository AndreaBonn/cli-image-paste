#!/usr/bin/env bash
#
# test_lib_env_detect.sh — Rilevamento sessione e catene di consegna (L1)
#
# Le funzioni sotto test sono pure: ricevono i loro input come argomenti o
# da variabili d'ambiente e stampano una stringa. È ciò che rende
# verificabile il comportamento su desktop che non possediamo.
#

# Ogni caso gira in una subshell per isolare le variabili d'ambiente: la
# "modifica persa" che ShellCheck segnala è esattamente l'effetto voluto.
# shellcheck disable=SC2030,SC2031

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

VERSION="test"
# shellcheck source=../lib/10_env_detect.sh
source "$(cd "$SCRIPT_DIR/.." && pwd)/lib/10_env_detect.sh"

# --- Tipo di sessione ---

test_session_type_from_xdg() {
    ( export XDG_SESSION_TYPE=wayland
      unset PASTE_IMAGE_SESSION_TYPE
      assert_equals "wayland" "$(session_type)" "wayland da XDG_SESSION_TYPE" )
    ( export XDG_SESSION_TYPE=x11
      unset PASTE_IMAGE_SESSION_TYPE
      assert_equals "x11" "$(session_type)" "x11 da XDG_SESSION_TYPE" )
}

test_session_type_falls_back_to_sockets() {
    # XDG_SESSION_TYPE non è garantita fuori da un login manager
    ( unset XDG_SESSION_TYPE PASTE_IMAGE_SESSION_TYPE DISPLAY
      export WAYLAND_DISPLAY=wayland-0
      assert_equals "wayland" "$(session_type)" "wayland da WAYLAND_DISPLAY" )
    ( unset XDG_SESSION_TYPE PASTE_IMAGE_SESSION_TYPE WAYLAND_DISPLAY
      export DISPLAY=:0
      assert_equals "x11" "$(session_type)" "x11 da DISPLAY" )
}

test_session_type_none_without_display() {
    ( unset XDG_SESSION_TYPE PASTE_IMAGE_SESSION_TYPE WAYLAND_DISPLAY DISPLAY
      assert_equals "none" "$(session_type)" "nessuna sessione grafica" )
}

test_session_type_override_wins() {
    ( export XDG_SESSION_TYPE=x11 PASTE_IMAGE_SESSION_TYPE=wayland
      assert_equals "wayland" "$(session_type)" "override vince su XDG" )
}

# --- Desktop ---

test_desktop_normalization() {
    local casi=(
        "ubuntu:GNOME|gnome"
        "GNOME|gnome"
        "pop:GNOME|gnome"
        "KDE|kde"
        "plasma|kde"
        "sway|sway"
        "Hyprland|hyprland"
        "i3|i3"
        "X-Cinnamon|cinnamon"
        "XFCE|xfce"
        "river|wlroots"
        "QualcosaDiIgnoto|altro"
    )
    local caso input atteso
    for caso in "${casi[@]}"; do
        input="${caso%%|*}"
        atteso="${caso##*|}"
        ( export PASTE_IMAGE_DESKTOP="$input"
          assert_equals "$atteso" "$(session_desktop)" "desktop '$input'" )
    done
}

test_desktop_unknown_when_unset() {
    ( unset XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP PASTE_IMAGE_DESKTOP
      assert_equals "altro" "$(session_desktop)" "desktop non dichiarato" )
}

# --- Catene di consegna ---

test_delivery_chain_table() {
    local casi=(
        "x11|gnome|xdotool clipboard"
        "x11|kde|xdotool clipboard"
        "x11|altro|xdotool clipboard"
        "wayland|gnome|clipboard"
        "wayland|unity|clipboard"
        "wayland|cinnamon|clipboard"
        "wayland|sway|wtype clipboard"
        "wayland|hyprland|wtype clipboard"
        "wayland|wlroots|wtype clipboard"
        "wayland|kde|wtype clipboard"
        "none|altro|clipboard"
    )
    local caso session desktop atteso resto
    for caso in "${casi[@]}"; do
        session="${caso%%|*}"
        resto="${caso#*|}"
        desktop="${resto%%|*}"
        atteso="${resto#*|}"
        assert_equals "$atteso" "$(delivery_chain_for "$session" "$desktop")" \
            "catena per $session/$desktop"
    done
}

# Su GNOME Wayland il typing non è ottenibile: la consegna via appunti deve
# essere la prima voce, non un ripiego raggiunto dopo un fallimento.
test_gnome_wayland_never_attempts_typing() {
    local chain
    chain=$(delivery_chain_for wayland gnome)
    assert_equals "clipboard" "$chain" "nessun tentativo di digitazione"
    assert_not_contains "$chain" "wtype" "wtype assente dalla catena"
    assert_not_contains "$chain" "ydotool" "ydotool assente dalla catena"
}

# ydotool richiede un daemon con accesso a /dev/uinput, cioè la capacità di
# iniettare tasti in qualunque applicazione della sessione: non può entrare
# in catena da solo, va scelto esplicitamente.
test_ydotool_never_automatic() {
    local session desktop
    for session in x11 wayland none; do
        for desktop in gnome kde sway hyprland altro; do
            if [[ "$(delivery_chain_for "$session" "$desktop")" == *ydotool* ]]; then
                _test_fail "ydotool proposto automaticamente per $session/$desktop"
            fi
        done
    done
}

# --- Negativo appreso ---

test_capability_marked_and_read() {
    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    ( export PASTE_IMAGE_SESSION_TYPE=wayland PASTE_IMAGE_DESKTOP=sway
      capability_failed wtype && exit 1
      capability_mark_failed wtype
      capability_failed wtype || exit 1
      exit 0 ) || _test_fail "il fallimento non viene registrato o riletto"
    unset XDG_STATE_HOME
}

test_capability_key_isolates_sessions() {
    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    ( export PASTE_IMAGE_SESSION_TYPE=wayland PASTE_IMAGE_DESKTOP=sway
      capability_mark_failed wtype )
    # Un altro desktop non deve ereditare il negativo: cambia la chiave
    ( export PASTE_IMAGE_SESSION_TYPE=wayland PASTE_IMAGE_DESKTOP=hyprland
      if capability_failed wtype; then exit 1; fi
      exit 0 ) || _test_fail "il negativo appreso attraversa sessioni diverse"
    unset XDG_STATE_HOME
}

test_capability_mark_is_idempotent() {
    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    ( export PASTE_IMAGE_SESSION_TYPE=wayland PASTE_IMAGE_DESKTOP=sway
      capability_mark_failed wtype
      capability_mark_failed wtype
      capability_mark_failed wtype )
    local lines
    lines=$(wc -l < "$TEST_TMPDIR/state/paste-image/capabilities")
    assert_equals "1" "$lines" "una sola riga dopo marcature ripetute"
    unset XDG_STATE_HOME
}

test_capabilities_reset() {
    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    ( export PASTE_IMAGE_SESSION_TYPE=wayland PASTE_IMAGE_DESKTOP=sway
      capability_mark_failed wtype
      capabilities_reset
      if capability_failed wtype; then exit 1; fi
      exit 0 ) || _test_fail "reset non azzera il negativo appreso"
    unset XDG_STATE_HOME
}

run_test "Tipo di sessione da XDG_SESSION_TYPE" test_session_type_from_xdg
run_test "Tipo di sessione dai socket" test_session_type_falls_back_to_sockets
run_test "Nessuna sessione grafica" test_session_type_none_without_display
run_test "Override del tipo di sessione" test_session_type_override_wins
run_test "Normalizzazione del desktop" test_desktop_normalization
run_test "Desktop non dichiarato" test_desktop_unknown_when_unset
run_test "Tabella delle catene di consegna" test_delivery_chain_table
run_test "GNOME Wayland non tenta la digitazione" test_gnome_wayland_never_attempts_typing
run_test "ydotool mai automatico" test_ydotool_never_automatic
run_test "Negativo appreso registrato e riletto" test_capability_marked_and_read
run_test "Chiave isola sessioni diverse" test_capability_key_isolates_sessions
run_test "Marcatura idempotente" test_capability_mark_is_idempotent
run_test "Reset del negativo appreso" test_capabilities_reset

print_summary "test_lib_env_detect.sh"
