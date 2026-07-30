#!/usr/bin/env bash
#
# test_framework_isolation.sh — Un test non vede la macchina che lo esegue
#
# Dirottare HOME non basta a isolare un test: le directory XDG hanno una
# variabile propria che vince su HOME, e il tipo di sessione grafica si legge
# dall'ambiente. Ereditarle significa misurare il desktop di chi esegue la
# suite: verde sotto X11 sulla macchina di sviluppo, rossa su un runner
# headless, e un file scritto in $XDG_CONFIG_HOME che sopravvive alla suite e
# cambia l'esito di quelle successive.
#
# La sonda gira in un processo separato con un ambiente ospite ostile, perché
# l'invariante deve valere anche dove l'host non ha nulla da nascondere.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

HOST_CONFIG_HOME="/host-config-che-non-deve-comparire"
HOST_SESSION_TYPE="sessione-ospite"
HOST_DESKTOP="desktop-ospite"

# Esegue una mini-suite figlia e riporta, in un file di risultato, che cosa
# vede il corpo di un test e che cosa resta nell'ambiente dopo il teardown.
_run_isolation_probe() {
    local probe="$TEST_TMPDIR/probe.sh" out="$TEST_TMPDIR/probe_out"

    cat > "$probe" <<'PROBE'
source "$FRAMEWORK"

probe_body() {
    {
        echo "dentro_config=${XDG_CONFIG_HOME-assente}"
        echo "dentro_state=${XDG_STATE_HOME-assente}"
        echo "dentro_sessione=${XDG_SESSION_TYPE-assente}"
        echo "dentro_desktop=${XDG_CURRENT_DESKTOP-assente}"
        echo "dentro_home=$HOME"
    } > "$PROBE_OUT"
}

run_test "sonda" probe_body >/dev/null 2>&1
{
    echo "dopo_config=${XDG_CONFIG_HOME-assente}"
    echo "dopo_sessione=${XDG_SESSION_TYPE-assente}"
    echo "dopo_desktop=${XDG_CURRENT_DESKTOP-assente}"
} >> "$PROBE_OUT"
PROBE

    FRAMEWORK="$SCRIPT_DIR/test_framework.sh" \
    PROBE_OUT="$out" \
    XDG_CONFIG_HOME="$HOST_CONFIG_HOME" \
    XDG_SESSION_TYPE="$HOST_SESSION_TYPE" \
    XDG_CURRENT_DESKTOP="$HOST_DESKTOP" \
        bash "$probe" >/dev/null 2>&1

    echo "$out"
}

# Legge una chiave dal file prodotto dalla sonda.
_probe_value() {
    sed -n "s/^$2=//p" "$1"
}

# --- Test: le directory XDG puntano dentro il fake home ---
test_xdg_dirs_redirected() {
    local out config state home
    out=$(_run_isolation_probe)

    config=$(_probe_value "$out" "dentro_config")
    state=$(_probe_value "$out" "dentro_state")
    home=$(_probe_value "$out" "dentro_home")

    assert_equals "$home/.config" "$config" "XDG_CONFIG_HOME dirottata nel fake home"
    assert_equals "$home/.local/state" "$state" "XDG_STATE_HOME dirottata nel fake home"
}

# --- Test: la sessione grafica dell'host non filtra nel test ---
test_host_session_not_visible() {
    local out
    out=$(_run_isolation_probe)

    assert_equals "assente" "$(_probe_value "$out" "dentro_sessione")" \
        "XDG_SESSION_TYPE dell'host non visibile"
    assert_equals "assente" "$(_probe_value "$out" "dentro_desktop")" \
        "XDG_CURRENT_DESKTOP dell'host non visibile"
}

# --- Test: il teardown restituisce l'ambiente originale ---
# Senza ripristino la suite lascerebbe l'ambiente alterato a chi la invoca,
# spostando il problema invece di risolverlo.
test_teardown_restores_host_env() {
    local out
    out=$(_run_isolation_probe)

    assert_equals "$HOST_CONFIG_HOME" "$(_probe_value "$out" "dopo_config")" \
        "XDG_CONFIG_HOME ripristinata dopo il teardown"
    assert_equals "$HOST_SESSION_TYPE" "$(_probe_value "$out" "dopo_sessione")" \
        "XDG_SESSION_TYPE ripristinata dopo il teardown"
    assert_equals "$HOST_DESKTOP" "$(_probe_value "$out" "dopo_desktop")" \
        "XDG_CURRENT_DESKTOP ripristinata dopo il teardown"
}

# --- Test: quel che il codice sotto test scrive resta nel fake home ---
test_config_writes_stay_in_fake_home() {
    local config_file
    config_file="$XDG_CONFIG_HOME/paste-image/config"

    mkdir -p "$(dirname "$config_file")"
    echo "CLEANUP_DAYS=30" > "$config_file"

    case "$config_file" in
        "$FAKE_HOME"/*) ;;
        *) _test_fail "il config è finito fuori dal fake home: $config_file" ;;
    esac
    assert_file_exists "$config_file" "config scritto nell'area usa e getta"
}

run_test "Directory XDG dentro il fake home" test_xdg_dirs_redirected
run_test "Sessione dell'host non visibile" test_host_session_not_visible
run_test "Teardown ripristina l'ambiente" test_teardown_restores_host_env
run_test "Le scritture restano nel fake home" test_config_writes_stay_in_fake_home

print_summary "test_framework_isolation.sh"
