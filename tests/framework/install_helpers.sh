# shellcheck shell=bash
#
# install_helpers.sh — Helper condivisi dalle suite su install.sh
#

INSTALL_SCRIPT="$PROJECT_DIR/install.sh"

# Helper: setup minimo per install
#
# La sessione va dichiarata: il registro delle scorciatoie è quello di GNOME e
# l'installer lo scrive solo se riconosce quel desktop. Ereditarlo dall'ambiente
# renderebbe l'esito dipendente dalla macchina che esegue i test. I test di
# altri desktop sovrascrivono l'override dopo questa chiamata.
setup_install_env() {
    set_session_env x11 gnome
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

# Helper: variante negativa di assert_mock_called_with
assert_mock_not_called_with_arg() {
    local cmd="$1" pattern="$2" label="$3"
    if grep "^${cmd} " "$MOCK_CALL_LOG" 2>/dev/null | grep -q -- "$pattern"; then
        _test_fail "$label: il mock '$cmd' è stato chiamato con '$pattern'"
    fi
}

# Helper: esegui install con stdin fornito
run_install() {
    local stdin_data="$1"
    echo -e "$stdin_data" | bash "$INSTALL_SCRIPT" 2>&1
}
