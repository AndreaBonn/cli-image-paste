#!/usr/bin/env bash
#
# test_framework.sh — Mini-framework di test per paste-images-cli
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
    export MOCK_CALL_LOG
    export GSETTINGS_STATE
    export MOCK_BIN
    export TEST_TMPDIR
    export FAKE_HOME
}

teardown_test_env() {
    export HOME="$_ORIG_HOME"
    export PATH="$_ORIG_PATH"
    unset MOCK_CALL_LOG GSETTINGS_STATE MOCK_BIN FAKE_HOME
    if [ -n "${TEST_TMPDIR:-}" ] && [ -d "$TEST_TMPDIR" ]; then
        rm -rf "$TEST_TMPDIR"
    fi
    unset TEST_TMPDIR
}

# --- Assertion ---

_test_fail() {
    local msg="$1"
    _CURRENT_TEST_FAILED=1
    _CURRENT_TEST_ERRORS="${_CURRENT_TEST_ERRORS}    FAIL: ${msg}"$'\n'
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local label="${3:-assert_equals}"
    if [ "$expected" != "$actual" ]; then
        _test_fail "$label: expected '$expected', got '$actual'"
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local label="${3:-assert_exit_code}"
    if [ "$expected" != "$actual" ]; then
        _test_fail "$label: expected exit code $expected, got $actual"
    fi
}

assert_file_exists() {
    local path="$1"
    local label="${2:-assert_file_exists}"
    if [ ! -f "$path" ]; then
        _test_fail "$label: file '$path' does not exist"
    fi
}

assert_file_not_exists() {
    local path="$1"
    local label="${2:-assert_file_not_exists}"
    if [ -f "$path" ]; then
        _test_fail "$label: file '$path' exists but should not"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="${3:-assert_contains}"
    if ! echo "$haystack" | grep -qF "$needle"; then
        _test_fail "$label: output does not contain '$needle'"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local label="${3:-assert_not_contains}"
    if echo "$haystack" | grep -qF "$needle"; then
        _test_fail "$label: output should not contain '$needle'"
    fi
}

assert_file_contains() {
    local filepath="$1"
    local needle="$2"
    local label="${3:-assert_file_contains}"
    if [ ! -f "$filepath" ]; then
        _test_fail "$label: file '$filepath' does not exist"
    elif ! grep -qF "$needle" "$filepath"; then
        _test_fail "$label: file '$filepath' does not contain '$needle'"
    fi
}

assert_file_not_contains() {
    local filepath="$1"
    local needle="$2"
    local label="${3:-assert_file_not_contains}"
    if [ -f "$filepath" ] && grep -qF "$needle" "$filepath"; then
        _test_fail "$label: file '$filepath' should not contain '$needle'"
    fi
}

assert_mock_called() {
    local cmd="$1"
    local label="${2:-assert_mock_called}"
    if ! grep -q "^${cmd} " "$MOCK_CALL_LOG" 2>/dev/null && ! grep -q "^${cmd}$" "$MOCK_CALL_LOG" 2>/dev/null; then
        _test_fail "$label: mock '$cmd' was not called"
    fi
}

assert_mock_not_called() {
    local cmd="$1"
    local label="${2:-assert_mock_not_called}"
    if grep -q "^${cmd} " "$MOCK_CALL_LOG" 2>/dev/null || grep -q "^${cmd}$" "$MOCK_CALL_LOG" 2>/dev/null; then
        _test_fail "$label: mock '$cmd' was called but should not have been"
    fi
}

assert_file_content_equals() {
    local filepath="$1"
    local expected="$2"
    local label="${3:-assert_file_content_equals}"
    if [ ! -f "$filepath" ]; then
        _test_fail "$label: file '$filepath' does not exist"
    else
        local actual
        actual=$(cat "$filepath")
        if [ "$expected" != "$actual" ]; then
            _test_fail "$label: content mismatch (expected '$expected', got '${actual:0:80}')"
        fi
    fi
}

assert_gsettings_array_valid() {
    local value="$1"
    local label="${2:-assert_gsettings_array_valid}"
    # @as [] è un array vuoto valido
    if [ "$value" = "@as []" ]; then
        return
    fi
    # Deve iniziare con [ e finire con ]
    if [[ "$value" != "["*"]" ]]; then
        _test_fail "$label: array non inizia con [ o non finisce con ]: '$value'"
        return
    fi
    # No virgole doppie
    if echo "$value" | grep -qE ',[[:space:]]*,'; then
        _test_fail "$label: virgole doppie nell'array: '$value'"
    fi
    # No virgola iniziale dopo [
    if echo "$value" | grep -qE '^\[[[:space:]]*,'; then
        _test_fail "$label: virgola iniziale nell'array: '$value'"
    fi
    # No virgola finale prima di ]
    if echo "$value" | grep -qE ',[[:space:]]*\]'; then
        _test_fail "$label: virgola finale nell'array: '$value'"
    fi
}

assert_mock_called_with() {
    local cmd="$1"
    local args_pattern="$2"
    local label="${3:-assert_mock_called_with}"
    if ! grep "^${cmd} " "$MOCK_CALL_LOG" 2>/dev/null | grep -q -- "$args_pattern"; then
        _test_fail "$label: mock '$cmd' not called with args matching '$args_pattern'"
        if [ -f "$MOCK_CALL_LOG" ]; then
            local actual
            actual=$(grep "^${cmd}" "$MOCK_CALL_LOG" 2>/dev/null | head -5 | sed 's/^/      /')
            if [ -n "$actual" ]; then
                _CURRENT_TEST_ERRORS="${_CURRENT_TEST_ERRORS}    Actual calls:"$'\n'"${actual}"$'\n'
            fi
        fi
    fi
}

# --- Mock helpers ---

# --- PATH ristretto ---

# Crea un PATH contenente solo i comandi di sistema essenziali + eventuali extra.
# I mock in $MOCK_BIN hanno sempre precedenza.
# Uso: setup_restricted_path                  → solo comandi base
#      setup_restricted_path pgrep diff python3 → base + extra
# shellcheck disable=SC2120  # Argomenti opzionali: $@ aggiunge comandi extra
setup_restricted_path() {
    local sys_bin="$TEST_TMPDIR/sys_bin"
    mkdir -p "$sys_bin"
    local base_cmds=(bash grep sed echo cat rm mkdir chmod cp touch sleep tr head printf mktemp wc)
    local cmd real_path
    for cmd in "${base_cmds[@]}" "$@"; do
        real_path=$(which "$cmd" 2>/dev/null || true)
        if [ -n "$real_path" ] && [ -f "$real_path" ]; then
            ln -sf "$real_path" "$sys_bin/$cmd"
        fi
    done
    export PATH="$MOCK_BIN:$sys_bin"
}

# --- Mock helpers ---

create_mock() {
    local name="$1"
    local body="${2:-}"
    cat > "$MOCK_BIN/$name" <<MOCK_EOF
#!/usr/bin/env bash
echo "$name \$*" >> "\$MOCK_CALL_LOG"
$body
MOCK_EOF
    chmod +x "$MOCK_BIN/$name"
}

create_gsettings_mock() {
    local initial_value="${1:-@as []}"

    # Imposta valore iniziale per custom-keybindings
    echo "$initial_value" > "$GSETTINGS_STATE/custom-keybindings"

    cat > "$MOCK_BIN/gsettings" <<'GSETTINGS_EOF'
#!/usr/bin/env bash

echo "gsettings $*" >> "$MOCK_CALL_LOG"

ACTION="$1"
shift

case "$ACTION" in
    get)
        SCHEMA="$1"
        KEY="$2"
        if [[ "$SCHEMA" == *"custom-keybinding:"* ]]; then
            BINDING_PATH=$(echo "$SCHEMA" | sed 's/.*custom-keybinding://')
            STATE_FILE="$GSETTINGS_STATE/binding_${KEY}_$(echo "$BINDING_PATH" | tr '/' '_')"
        else
            STATE_FILE="$GSETTINGS_STATE/$KEY"
        fi
        if [ -f "$STATE_FILE" ]; then
            cat "$STATE_FILE"
        else
            echo "@as []"
        fi
        ;;
    set)
        SCHEMA="$1"
        KEY="$2"
        VALUE="$3"
        if [[ "$SCHEMA" == *"custom-keybinding:"* ]]; then
            BINDING_PATH=$(echo "$SCHEMA" | sed 's/.*custom-keybinding://')
            STATE_FILE="$GSETTINGS_STATE/binding_${KEY}_$(echo "$BINDING_PATH" | tr '/' '_')"
        else
            STATE_FILE="$GSETTINGS_STATE/$KEY"
        fi
        echo "$VALUE" > "$STATE_FILE"
        ;;
    reset)
        SCHEMA="$1"
        KEY="$2"
        if [[ "$SCHEMA" == *"custom-keybinding:"* ]]; then
            BINDING_PATH=$(echo "$SCHEMA" | sed 's/.*custom-keybinding://')
            STATE_FILE="$GSETTINGS_STATE/binding_${KEY}_$(echo "$BINDING_PATH" | tr '/' '_')"
        else
            STATE_FILE="$GSETTINGS_STATE/$KEY"
        fi
        rm -f "$STATE_FILE"
        ;;
esac
GSETTINGS_EOF
    chmod +x "$MOCK_BIN/gsettings"
}

create_date_mock() {
    local fixed_timestamp="$1"

    # Salva il path del date reale
    local real_date
    real_date=$(which date 2>/dev/null || echo "/usr/bin/date")

    cat > "$MOCK_BIN/date" <<DATE_EOF
#!/usr/bin/env bash
echo "date \$*" >> "\$MOCK_CALL_LOG"
if [ "\$1" = "+%Y%m%d_%H%M%S" ]; then
    echo "$fixed_timestamp"
else
    "$real_date" "\$@"
fi
DATE_EOF
    chmod +x "$MOCK_BIN/date"
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
