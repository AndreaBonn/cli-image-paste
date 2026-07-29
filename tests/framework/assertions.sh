# shellcheck shell=bash
#
# assertions.sh — Assertion del mini-framework di test
#
# Sorgiato da test_framework.sh, non direttamente dalle suite.
#

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
    if ! echo "$haystack" | grep -qF -- "$needle"; then
        _test_fail "$label: output does not contain '$needle'"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local label="${3:-assert_not_contains}"
    if echo "$haystack" | grep -qF -- "$needle"; then
        _test_fail "$label: output should not contain '$needle'"
    fi
}

assert_file_contains() {
    local filepath="$1"
    local needle="$2"
    local label="${3:-assert_file_contains}"
    if [ ! -f "$filepath" ]; then
        _test_fail "$label: file '$filepath' does not exist"
    elif ! grep -qF -- "$needle" "$filepath"; then
        _test_fail "$label: file '$filepath' does not contain '$needle'"
    fi
}

assert_file_not_contains() {
    local filepath="$1"
    local needle="$2"
    local label="${3:-assert_file_not_contains}"
    if [ -f "$filepath" ] && grep -qF -- "$needle" "$filepath"; then
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

