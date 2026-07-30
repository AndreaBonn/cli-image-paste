#!/usr/bin/env bash
#
# test_framework.sh — Mini-framework di test per cli-image-paste
#
# Fornisce isolamento per-test, assertion TAP-like e mock helpers.
# Viene caricato (source) da ogni test suite.
#

# --- Contatori globali ---
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_NAMES=()

# Flag per-test
_CURRENT_TEST_FAILED=0
_CURRENT_TEST_ERRORS=""

# Salva valori originali
_ORIG_HOME="$HOME"
_ORIG_PATH="$PATH"

# --- Isolamento dall'ambiente ospite ---
#
# Redirigere HOME non basta: le directory XDG hanno una variabile propria che
# vince su HOME, e il tipo di sessione grafica si legge dall'ambiente. Un test
# che le eredita misura il desktop di chi lo esegue, non il codice: passa sulla
# macchina di sviluppo sotto X11 e fallisce su un runner headless, e un file
# scritto in $XDG_CONFIG_HOME sopravvive alla suite e contamina le successive.
# Ogni suite dichiara la sessione che vuole con set_session_env.
_HOST_ENV_VARS=(XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_CACHE_HOME
                XDG_SESSION_TYPE XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP
                DISPLAY WAYLAND_DISPLAY)

declare -A _HOST_ENV_SAVED=()

_save_host_env() {
    local var
    for var in "${_HOST_ENV_VARS[@]}"; do
        # ${!var+x} distingue "non impostata" da "impostata a vuoto": il
        # ripristino deve rimettere l'assenza, non una stringa vuota.
        if [ -n "${!var+x}" ]; then
            _HOST_ENV_SAVED["$var"]="${!var}"
        fi
    done
    # L'esito del ciclo non è l'esito della funzione: l'ultima variabile
    # assente lascerebbe uno stato di uscita 1, che sotto set -e ucciderebbe
    # la suite proprio mentre la sorgia.
    return 0
}

_isolate_host_env() {
    local var
    for var in "${_HOST_ENV_VARS[@]}"; do
        unset "$var"
    done
    # Puntate dentro il fake home invece che lasciate assenti: se il codice
    # sotto test le legge, deve comunque scrivere in area usa e getta.
    export XDG_CONFIG_HOME="$FAKE_HOME/.config"
    export XDG_STATE_HOME="$FAKE_HOME/.local/state"
    export XDG_DATA_HOME="$FAKE_HOME/.local/share"
    export XDG_CACHE_HOME="$FAKE_HOME/.cache"
}

_restore_host_env() {
    local var
    for var in "${_HOST_ENV_VARS[@]}"; do
        if [ -n "${_HOST_ENV_SAVED[$var]+x}" ]; then
            export "$var=${_HOST_ENV_SAVED[$var]}"
        else
            unset "$var"
        fi
    done
}

_save_host_env

# Directory del progetto (due livelli su da tests/)
# shellcheck disable=SC2034 # Usato dai test suite che importano questo framework
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Isolamento per-test ---

setup_test_env() {
    TEST_TMPDIR=$(mktemp -d "/tmp/test_paste_XXXXXX")
    FAKE_HOME="$TEST_TMPDIR/fake_home"
    MOCK_BIN="$TEST_TMPDIR/mock_bin"
    MOCK_CALL_LOG="$TEST_TMPDIR/mock_calls.log"
    GSETTINGS_STATE="$TEST_TMPDIR/gsettings_state"

    mkdir -p "$FAKE_HOME" "$MOCK_BIN" "$GSETTINGS_STATE"
    mkdir -p "$FAKE_HOME/.local/bin"
    touch "$FAKE_HOME/.bashrc"
    touch "$FAKE_HOME/.zshrc"
    touch "$MOCK_CALL_LOG"

    export HOME="$FAKE_HOME"
    export PATH="$MOCK_BIN:$_ORIG_PATH"
    _isolate_host_env
    export MOCK_CALL_LOG
    export GSETTINGS_STATE
    export MOCK_BIN
    export TEST_TMPDIR
    export FAKE_HOME
}

teardown_test_env() {
    export HOME="$_ORIG_HOME"
    export PATH="$_ORIG_PATH"
    _restore_host_env
    unset MOCK_CALL_LOG GSETTINGS_STATE MOCK_BIN FAKE_HOME
    unset PASTE_IMAGE_OUTPUT_DIR
    unset PASTE_IMAGE_SESSION_TYPE PASTE_IMAGE_DESKTOP
    if [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ]; then
        rm -rf "$TEST_TMPDIR"
    fi
    unset TEST_TMPDIR
}

# --- Moduli del framework ---

_FRAMEWORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=framework/assertions.sh
source "$_FRAMEWORK_DIR/framework/assertions.sh"
# shellcheck source=framework/mocks.sh
source "$_FRAMEWORK_DIR/framework/mocks.sh"

# --- Helper per l'artefatto e i moduli ---

# Path dell'artefatto generato. I test invocano questo, non i moduli in lib/.
# shellcheck disable=SC2034 # Usato dai test suite che importano questo framework
PASTE_IMAGE_DIST="$PROJECT_DIR/dist/paste-image"

# Costruisce l'artefatto se assente o più vecchio di un modulo.
# Il runner builda comunque, questo copre l'esecuzione di una singola suite.
ensure_built() {
    local dist="$PROJECT_DIR/dist/paste-image"
    local module newest=""

    if [ -f "$dist" ]; then
        for module in "$PROJECT_DIR"/lib/*.sh; do
            [ -f "$module" ] || continue
            if [ -z "$newest" ] || [ "$module" -nt "$newest" ]; then
                newest="$module"
            fi
        done
        if [ -n "$newest" ] && [ ! "$newest" -nt "$dist" ]; then
            return 0
        fi
    fi

    bash "$PROJECT_DIR/scripts/build.sh" >/dev/null
}

# Sorgia un modulo di lib/ per testarne le funzioni in isolamento (livello L1).
# Uso: source_lib 10_env_detect.sh
source_lib() {
    local module="$1"
    # shellcheck disable=SC1090 # Path dinamico per costruzione: è il senso dell'helper
    source "$PROJECT_DIR/lib/$module"
}

# Forza tipo di sessione e desktop per i test che dipendono dall'ambiente.
# Uso: set_session_env wayland GNOME
set_session_env() {
    export PASTE_IMAGE_SESSION_TYPE="$1"
    export PASTE_IMAGE_DESKTOP="${2:-}"
}

# Crea un PNG minimo valido (8 byte di firma + contenuto fittizio).
# Serve ai test che devono distinguere un file immagine da un file vuoto.
make_fake_image() {
    local path="$1"
    printf '\x89PNG\r\n\x1a\n' > "$path"
    printf 'FAKE_IMAGE_CONTENT' >> "$path"
}

# --- Runner ---

run_test() {
    local name="$1"
    local func="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    _CURRENT_TEST_FAILED=0
    _CURRENT_TEST_ERRORS=""

    setup_test_env

    # Cattura stderr in un file temporaneo per diagnostica in caso di fallimento
    local stderr_file
    stderr_file=$(mktemp "/tmp/test_stderr_XXXXXX")

    # Esegui test nel shell corrente (non subshell), supprimendo stdout
    # stderr viene catturato nel file per mostrarlo solo in caso di errore
    local exit_code=0
    set +e
    $func >/dev/null 2>"$stderr_file"
    exit_code=$?
    set -e

    teardown_test_env

    if [ $_CURRENT_TEST_FAILED -ne 0 ] || [ $exit_code -ne 0 ]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  FAIL  $name"
        if [ -n "$_CURRENT_TEST_ERRORS" ]; then
            printf '%s' "$_CURRENT_TEST_ERRORS"
        fi
        if [ $exit_code -ne 0 ] && [ $_CURRENT_TEST_FAILED -eq 0 ]; then
            echo "    (crashed with exit code $exit_code)"
        fi
        # Mostra stderr catturato se non vuoto
        if [ -s "$stderr_file" ]; then
            echo "    stderr output:"
            sed 's/^/      /' "$stderr_file"
        fi
        FAILED_NAMES+=("$name")
    else
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  OK    $name"
    fi
    rm -f "$stderr_file"
}

print_summary() {
    local suite_name="${1:-Test Suite}"
    echo ""
    echo "--- $suite_name ---"
    echo "Totale: $TESTS_RUN | Passati: $TESTS_PASSED | Falliti: $TESTS_FAILED"
    if [ ${#FAILED_NAMES[@]} -gt 0 ]; then
        echo "Test falliti:"
        for name in "${FAILED_NAMES[@]}"; do
            echo "  - $name"
        done
    fi
    echo ""
    return $TESTS_FAILED
}
