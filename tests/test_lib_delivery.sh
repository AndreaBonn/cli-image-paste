#!/usr/bin/env bash
#
# test_lib_delivery.sh — Selezione del backend, validazione del path, invio
#
# La validazione del path è una mitigazione di sicurezza verificata
# empiricamente: xdotool sintetizza il keysym Return per un CR, quindi un
# path con caratteri di controllo esegue un comando nel prompt in attesa.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

VERSION="test"
TYPING_DELAY=0
_LIB="$(cd "$SCRIPT_DIR/.." && pwd)/lib"
# shellcheck source=../lib/05_text.sh
source "$_LIB/05_text.sh"
# shellcheck source=../lib/10_env_detect.sh
source "$_LIB/10_env_detect.sh"
# shellcheck source=../lib/30_delivery.sh
source "$_LIB/30_delivery.sh"

# --- Validazione del path ---

test_safe_paths_accepted() {
    local path
    for path in "/tmp/immagine.png" "/home/utente/con spazio.png" \
                "/tmp/accentata-è.png" "/tmp/paste_image_20260101_abc.jpg"; do
        if ! delivery_path_is_safe "$path"; then
            _test_fail "path legittimo rifiutato: '$path'"
        fi
    done
}

test_hostile_paths_rejected() {
    local casi=(
        "carriage return|/tmp/a${CR}id"
        "line feed|/tmp/a${LF}id"
        "escape ANSI|/tmp/a${ESC}[31m.png"
        "tab|/tmp/a${TAB}b.png"
        "null-adiacente BEL|/tmp/a${BEL}b.png"
        "override bidirezionale|/tmp/${RLO}gnp.exe"
        "isolate bidirezionale|/tmp/${LRI}x.png"
        "path relativo|tmp/immagine.png"
        "stringa vuota|"
    )
    local caso desc path
    for caso in "${casi[@]}"; do
        desc="${caso%%|*}"
        path="${caso#*|}"
        if delivery_path_is_safe "$path"; then
            _test_fail "path ostile accettato ($desc)"
        fi
    done
}

# --- Rendering del template ---

test_render_without_template_is_bare_path() {
    assert_equals "/tmp/x.png" "$(delivery_render "/tmp/x.png" "")" "path nudo"
}

test_render_substitutes_placeholder() {
    assert_equals "/add /tmp/x.png" "$(delivery_render "/tmp/x.png" "/add %s")" "template applicato"
    assert_equals "@/tmp/x.png" "$(delivery_render "/tmp/x.png" "@%s")" "template breve"
}

# Un path che contenga un segnaposto non deve innescare una seconda
# sostituzione: la sostituzione è letterale e avviene una volta sola.
test_render_does_not_reinterpret_path() {
    local out
    out=$(delivery_render '/tmp/%s.png' '/add %s')
    assert_equals "/add /tmp/%s.png" "$out" "il path non viene risostituito"
}

# Il template non deve mai essere trattato come format string di printf.
test_render_treats_template_as_data() {
    local out
    out=$(delivery_render "/tmp/x.png" "/add %s %d")
    assert_contains "$out" "%d" "specificatore lasciato intatto"
}

# --- Selezione del backend ---

test_forced_backend_wins() {
    assert_equals "ydotool" "$(delivery_select_backend wayland gnome ydotool)" \
        "scelta esplicita rispettata"
}

test_x11_prefers_xdotool_when_present() {
    create_mock "xdotool" ""
    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    assert_equals "xdotool" "$(delivery_select_backend x11 gnome)" "xdotool su X11"
    unset XDG_STATE_HOME
}

test_gnome_wayland_uses_clipboard() {
    create_mock "wl-copy" ""
    create_mock "wtype" ""
    export XDG_STATE_HOME="$TEST_TMPDIR/state" PASTE_IMAGE_SESSION_TYPE=wayland
    assert_equals "clipboard" "$(delivery_select_backend wayland gnome)" \
        "appunti su GNOME Wayland anche con wtype installato"
    unset XDG_STATE_HOME PASTE_IMAGE_SESSION_TYPE
}

test_sway_prefers_wtype() {
    create_mock "wtype" ""
    create_mock "wl-copy" ""
    export XDG_STATE_HOME="$TEST_TMPDIR/state" PASTE_IMAGE_SESSION_TYPE=wayland
    assert_equals "wtype" "$(delivery_select_backend wayland sway)" "wtype su sway"
    unset XDG_STATE_HOME PASTE_IMAGE_SESSION_TYPE
}

test_missing_tool_falls_through() {
    # PATH ristretto: senza questo il test dipenderebbe da cosa è installato
    # sulla macchina di sviluppo, e passerebbe o fallirebbe a seconda che
    # wtype ci sia o no.
    setup_restricted_path
    create_mock "wl-copy" ""
    export XDG_STATE_HOME="$TEST_TMPDIR/state" PASTE_IMAGE_SESSION_TYPE=wayland
    assert_equals "clipboard" "$(delivery_select_backend wayland sway)" \
        "ripiego sugli appunti senza wtype"
    unset XDG_STATE_HOME PASTE_IMAGE_SESSION_TYPE
}

test_learned_failure_skips_backend() {
    create_mock "wtype" ""
    create_mock "wl-copy" ""
    export XDG_STATE_HOME="$TEST_TMPDIR/state" PASTE_IMAGE_SESSION_TYPE=wayland
    export PASTE_IMAGE_DESKTOP=sway
    capability_mark_failed wtype
    assert_equals "clipboard" "$(delivery_select_backend wayland sway)" \
        "backend già fallito non viene ritentato"
    unset XDG_STATE_HOME PASTE_IMAGE_SESSION_TYPE PASTE_IMAGE_DESKTOP
}

test_ydotool_skipped_without_daemon() {
    create_mock "ydotool" ""
    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    export YDOTOOL_SOCKET="$TEST_TMPDIR/socket-inesistente"
    if _delivery_backend_usable ydotool; then
        _test_fail "ydotool considerato utilizzabile senza daemon in ascolto"
    fi
    unset XDG_STATE_HOME YDOTOOL_SOCKET
}

# --- Invio ---

test_send_via_xdotool_passes_text() {
    # shellcheck disable=SC2016 # Apici singoli intenzionali: corpo dello script mock
    create_mock "xdotool" 'case "$1" in getactivewindow) echo "999";; esac'
    delivery_send xdotool "/tmp/x.png" "" >/dev/null 2>&1
    assert_mock_called_with "xdotool" "type.*--clearmodifiers /tmp/x.png" "testo digitato"
}

test_send_via_clipboard_uses_wl_copy_on_wayland() {
    create_mock "wl-copy" ""
    export PASTE_IMAGE_SESSION_TYPE=wayland
    delivery_send clipboard "/tmp/x.png" >/dev/null 2>&1
    assert_mock_called "wl-copy" "wl-copy invocato su Wayland"
    unset PASTE_IMAGE_SESSION_TYPE
}

# Misurato su sway: senza setsid wl-copy resta nel process group del
# chiamante, e chi termina quel gruppo porta via la selezione prima che
# l'utente possa incollare.
test_wl_copy_is_detached_from_process_group() {
    create_mock "wl-copy" ""
    create_mock "setsid" ""
    export PASTE_IMAGE_SESSION_TYPE=wayland
    delivery_send clipboard "/tmp/x.png" >/dev/null 2>&1
    assert_mock_called_with "setsid" "wl-copy" "wl-copy lanciato tramite setsid"
    unset PASTE_IMAGE_SESSION_TYPE
}

test_send_via_clipboard_uses_xclip_on_x11() {
    create_mock "xclip" ""
    export PASTE_IMAGE_SESSION_TYPE=x11
    delivery_send clipboard "/tmp/x.png" >/dev/null 2>&1
    assert_mock_called_with "xclip" "-selection clipboard" "xclip invocato su X11"
    unset PASTE_IMAGE_SESSION_TYPE
}

test_unknown_backend_fails() {
    local exit_code=0
    delivery_send telepatia "/tmp/x.png" >/dev/null 2>&1 || exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        _test_fail "un backend inesistente non ha segnalato errore"
    fi
}

# --- Messaggio all'utente ---

# La sovrascrittura degli appunti è una perdita di dati silenziosa: la
# notifica deve dirlo, non limitarsi a confermare il successo.
test_clipboard_hint_mentions_overwrite() {
    local hint
    hint=$(delivery_hint clipboard)
    assert_contains "$hint" "Ctrl+V" "spiega cosa fare"
    assert_contains "$hint" "sostituito" "dichiara la sovrascrittura"
}

test_typing_hint_is_empty() {
    assert_equals "" "$(delivery_hint xdotool)" "nessun messaggio quando digita"
}

CR=$'\r'
LF=$'\n'
TAB=$'\t'
ESC=$'\033'
BEL=$'\a'
RLO=$'‮'
LRI=$'⁦'

run_test "Path legittimi accettati" test_safe_paths_accepted
run_test "Path ostili rifiutati" test_hostile_paths_rejected
run_test "Senza template: path nudo" test_render_without_template_is_bare_path
run_test "Template sostituito" test_render_substitutes_placeholder
run_test "Il path non viene risostituito" test_render_does_not_reinterpret_path
run_test "Template trattato come dato" test_render_treats_template_as_data
run_test "Backend forzato vince" test_forced_backend_wins
run_test "X11 preferisce xdotool" test_x11_prefers_xdotool_when_present
run_test "GNOME Wayland usa gli appunti" test_gnome_wayland_uses_clipboard
run_test "sway preferisce wtype" test_sway_prefers_wtype
run_test "Tool assente: si scende nella catena" test_missing_tool_falls_through
run_test "Fallimento appreso salta il backend" test_learned_failure_skips_backend
run_test "ydotool saltato senza daemon" test_ydotool_skipped_without_daemon
run_test "Invio via xdotool" test_send_via_xdotool_passes_text
run_test "Appunti via wl-copy su Wayland" test_send_via_clipboard_uses_wl_copy_on_wayland
run_test "Appunti via xclip su X11" test_send_via_clipboard_uses_xclip_on_x11
run_test "wl-copy staccato dal process group" test_wl_copy_is_detached_from_process_group
run_test "Backend sconosciuto fallisce" test_unknown_backend_fails
run_test "Il messaggio dichiara la sovrascrittura" test_clipboard_hint_mentions_overwrite
run_test "Nessun messaggio con digitazione" test_typing_hint_is_empty

print_summary "test_lib_delivery.sh"
