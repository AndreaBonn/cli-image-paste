#!/usr/bin/env bash
#
# test_paste_image.sh — Percorso principale: dipendenze, clipboard, creazione file
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"
# shellcheck source=framework/paste_image_helpers.sh
source "$SCRIPT_DIR/framework/paste_image_helpers.sh"

# --- Test 1: Dipendenza xclip mancante ---
test_missing_xclip() {
    setup_restricted_path
    create_mock "xdotool" ""

    local output exit_code=0
    output=$(bash "$PASTE_IMAGE_SCRIPT" 2>&1) || exit_code=$?

    assert_exit_code "1" "$exit_code" "exit code"
    assert_contains "$output" "xclip" "messaggio menziona xclip"
    assert_contains "$output" "Errore" "messaggio è un errore"
}

# --- Test 2: Dipendenza xdotool mancante ---
test_missing_xdotool() {
    setup_restricted_path
    create_mock "xclip" ""

    local output exit_code=0
    output=$(bash "$PASTE_IMAGE_SCRIPT" 2>&1) || exit_code=$?

    assert_exit_code "1" "$exit_code" "exit code"
    assert_contains "$output" "xdotool" "messaggio menziona xdotool"
    assert_contains "$output" "Errore" "messaggio è un errore"
}

# --- Test 3: Clipboard vuota ---
test_clipboard_empty() {
    setup_base_mocks
    setup_xclip_mock ""

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "1" "$exit_code" "exit code"
    assert_mock_called_with "notify-send" "vuoti" "notify con vuoti"
}

# --- Test 4: Clipboard senza immagine ---
test_clipboard_no_image() {
    setup_base_mocks
    setup_xclip_mock "text/plain"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "1" "$exit_code" "exit code"
    assert_mock_called_with "notify-send" "non contengono" "notify con non contengono"
}

# --- Test 5: PNG nella clipboard ---
test_png_clipboard() {
    setup_base_mocks
    setup_xclip_mock "image/png" "PNG_IMAGE_BYTES"
    create_date_mock "20260306_120000"

    use_output_dir "$TEST_TMPDIR"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "0" "$exit_code" "exit code"
    local created_file
    created_file=$(find_created_file "$TEST_TMPDIR" "20260306_120000" "png")
    if [ -z "$created_file" ]; then
        _test_fail "file png non creato"
        return
    fi
    # Verifica contenuto del file (non solo esistenza)
    assert_file_content_equals "$created_file" "PNG_IMAGE_BYTES" "contenuto file"
    # Verifica MIME type corretto nella chiamata di salvataggio
    assert_mock_called_with "xclip" "-t image/png -o" "MIME type corretto per salvataggio"
    # Verifica path completo passato a xdotool (con suffisso random mktemp)
    assert_mock_called_with "xdotool" "type.*--window 12345 $created_file" "path completo con window"
}

# --- Test 6: JPEG nella clipboard ---
test_jpeg_clipboard() {
    setup_base_mocks
    setup_xclip_mock "image/jpeg" "JPEG_IMAGE_BYTES"
    create_date_mock "20260306_120001"

    use_output_dir "$TEST_TMPDIR"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "0" "$exit_code" "exit code"
    local created_file
    created_file=$(find_created_file "$TEST_TMPDIR" "20260306_120001" "jpg")
    if [ -z "$created_file" ]; then
        _test_fail "file jpg non creato"
        return
    fi
    # Verifica contenuto
    assert_file_content_equals "$created_file" "JPEG_IMAGE_BYTES" "contenuto file"
    # Verifica MIME type: deve usare image/jpeg, NON image/png
    assert_mock_called_with "xclip" "-t image/jpeg -o" "MIME type corretto (jpeg, non png)"
}

# --- Test 7: PNG prioritario su JPEG ---
test_png_priority_over_jpeg() {
    setup_base_mocks
    setup_xclip_mock "image/jpeg
image/png" "PNG_IMAGE_BYTES"
    create_date_mock "20260306_120002"

    use_output_dir "$TEST_TMPDIR"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "0" "$exit_code" "exit code"
    local created_file
    created_file=$(find_created_file "$TEST_TMPDIR" "20260306_120002" "png")
    if [ -z "$created_file" ]; then
        _test_fail "file png prioritario non creato"
        return
    fi
    # Verifica che il salvataggio usi image/png (non image/jpeg)
    assert_mock_called_with "xclip" "-t image/png -o" "salvataggio con MIME png prioritario"
}

# --- Test 8: mktemp crea file univoci con stesso timestamp ---
test_mktemp_unique_files() {
    setup_base_mocks
    setup_xclip_mock "image/png" "IMAGE_DATA"
    create_date_mock "20260306_120003"

    use_output_dir "$TEST_TMPDIR"

    # Esegui lo script due volte con lo stesso timestamp
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || true
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || true

    # Devono esistere due file con nomi diversi (mktemp genera suffissi random)
    local count
    count=$(count_created_files "$TEST_TMPDIR" "20260306_120003" "png")
    assert_equals "2" "$count" "due file univoci creati con stesso timestamp"
}

# --- Test 9: mktemp crea file con permessi sicuri (0600) ---
test_mktemp_secure_permissions() {
    setup_base_mocks
    setup_xclip_mock "image/png" "PNG_IMAGE_BYTES"
    create_date_mock "20260306_120004"

    use_output_dir "$TEST_TMPDIR"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "0" "$exit_code" "exit code"
    local created_file
    created_file=$(find_created_file "$TEST_TMPDIR" "20260306_120004" "png")
    if [ -z "$created_file" ]; then
        _test_fail "file non creato"
        return
    fi
    # mktemp crea file con permessi 0600 (solo owner read/write)
    local perms
    perms=$(stat -c %a "$created_file")
    assert_equals "600" "$perms" "permessi file sicuri (0600)"
}

# --- Test: --version ---

test_version_flag() {
    local output exit_code

    set +e
    output=$(bash "$PASTE_IMAGE_SCRIPT" --version 2>&1)
    exit_code=$?
    set -e

    assert_exit_code "0" "$exit_code" "exit code"

    # Verifica formato "paste-image X.Y.Z"
    assert_contains "$output" "paste-image" "contiene paste-image"

    local match_exit
    set +e
    echo "$output" | grep -qE '[0-9]+\.[0-9]+\.[0-9]+'
    match_exit=$?
    set -e
    assert_exit_code "0" "$match_exit" "contiene versione X.Y.Z"
}

test_version_flag_short() {
    local output exit_code

    set +e
    output=$(bash "$PASTE_IMAGE_SCRIPT" -v 2>&1)
    exit_code=$?
    set -e

    assert_exit_code "0" "$exit_code" "exit code"
    assert_contains "$output" "paste-image" "contiene paste-image"
}

echo "=== test_paste_image.sh ==="

run_test "--version mostra versione" test_version_flag
run_test "-v mostra versione" test_version_flag_short
run_test "Dipendenza xclip mancante" test_missing_xclip
run_test "Dipendenza xdotool mancante" test_missing_xdotool
run_test "Clipboard vuota" test_clipboard_empty
run_test "Clipboard senza immagine" test_clipboard_no_image
run_test "PNG nella clipboard" test_png_clipboard
run_test "JPEG nella clipboard" test_jpeg_clipboard
run_test "PNG prioritario su JPEG" test_png_priority_over_jpeg
run_test "mktemp: file univoci con stesso timestamp" test_mktemp_unique_files
run_test "mktemp: permessi file sicuri (0600)" test_mktemp_secure_permissions

print_summary "test_paste_image.sh"
