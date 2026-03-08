#!/usr/bin/env bash
#
# test_paste_image.sh — Test per lo script principale paste-image
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

PASTE_IMAGE_SCRIPT="$PROJECT_DIR/paste-image"

# Helper: crea una copia dello script con OUTPUT_DIR personalizzabile
prepare_script() {
    local output_dir="${1:-/tmp}"
    local script_copy="$TEST_TMPDIR/paste-image-test"
    sed "s|^OUTPUT_DIR=\"/tmp\"|OUTPUT_DIR=\"${output_dir}\"|" "$PASTE_IMAGE_SCRIPT" > "$script_copy"
    chmod +x "$script_copy"
    echo "$script_copy"
}

# Helper: setup mock base (xclip, xdotool, notify-send)
setup_base_mocks() {
    # shellcheck disable=SC2016 # Single quotes intenzionali: corpo dello script mock
    create_mock "xdotool" 'case "$1" in getactivewindow) echo "12345";; esac'
    create_mock "notify-send" ""
}

# Helper: mock xclip con TARGETS e dati immagine personalizzabili
# Nota: usa ${2-default} (senza :) per distinguere "" da "non passato"
setup_xclip_mock() {
    local targets="$1"
    local image_data="${2-FAKE_IMAGE_DATA}"
    local save_exit="${3:-0}"

    cat > "$MOCK_BIN/xclip" <<XCLIP_EOF
#!/usr/bin/env bash
echo "xclip \$*" >> "\$MOCK_CALL_LOG"

TARGET=""
for arg in "\$@"; do
    case "\$prev" in
        -t) TARGET="\$arg" ;;
    esac
    prev="\$arg"
done

if [ "\$TARGET" = "TARGETS" ]; then
    echo "$targets"
elif [ -n "\$TARGET" ]; then
    if echo "\$*" | grep -q "\-o"; then
        if [ "$save_exit" -ne 0 ]; then
            exit $save_exit
        fi
        printf '%s' "$image_data"
    fi
fi
XCLIP_EOF
    chmod +x "$MOCK_BIN/xclip"
}

# Helper: trova il primo file creato dallo script (pattern: paste_image_TIMESTAMP_RANDOM.EXT)
# Usa bash glob puro — funziona anche con PATH ristretto
find_created_file() {
    local dir="$1" timestamp="$2" ext="$3"
    local f
    for f in "${dir}/paste_image_${timestamp}_"*".${ext}"; do
        if [ -f "$f" ]; then
            echo "$f"
            return 0
        fi
    done
}

# Helper: conta i file creati dallo script che matchano il pattern
count_created_files() {
    local dir="$1" timestamp="$2" ext="$3"
    local count=0 f
    for f in "${dir}/paste_image_${timestamp}_"*".${ext}"; do
        [ -f "$f" ] && count=$((count + 1))
    done
    echo "$count"
}

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

    local script_copy
    script_copy=$(prepare_script "$TEST_TMPDIR")

    local exit_code=0
    bash "$script_copy" >/dev/null 2>&1 || exit_code=$?

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

    local script_copy
    script_copy=$(prepare_script "$TEST_TMPDIR")

    local exit_code=0
    bash "$script_copy" >/dev/null 2>&1 || exit_code=$?

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

    local script_copy
    script_copy=$(prepare_script "$TEST_TMPDIR")

    local exit_code=0
    bash "$script_copy" >/dev/null 2>&1 || exit_code=$?

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

    local script_copy
    script_copy=$(prepare_script "$TEST_TMPDIR")

    # Esegui lo script due volte con lo stesso timestamp
    bash "$script_copy" >/dev/null 2>&1 || true
    bash "$script_copy" >/dev/null 2>&1 || true

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

    local script_copy
    script_copy=$(prepare_script "$TEST_TMPDIR")

    local exit_code=0
    bash "$script_copy" >/dev/null 2>&1 || exit_code=$?

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

# --- Test 10: OUTPUT_DIR non scrivibile → fallback ---
test_output_dir_fallback() {
    setup_base_mocks
    setup_xclip_mock "image/png" "PNG_IMAGE_BYTES"
    create_date_mock "20260306_120005"

    local readonly_dir="$TEST_TMPDIR/readonly_output"
    mkdir -p "$readonly_dir"
    chmod 444 "$readonly_dir"

    local script_copy
    script_copy=$(prepare_script "$readonly_dir")

    local exit_code=0
    bash "$script_copy" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "0" "$exit_code" "exit code"
    local created_file
    created_file=$(find_created_file "$FAKE_HOME/Pictures/paste_image" "20260306_120005" "png")
    if [ -z "$created_file" ]; then
        _test_fail "file in fallback dir non creato"
        chmod 755 "$readonly_dir"
        return
    fi
    assert_file_content_equals "$created_file" "PNG_IMAGE_BYTES" "contenuto in fallback"

    chmod 755 "$readonly_dir"
}

# --- Test 11: xclip salvataggio fallisce ---
test_xclip_save_fails() {
    setup_base_mocks
    setup_xclip_mock "image/png" "" "1"
    create_date_mock "20260306_120006"

    local script_copy
    script_copy=$(prepare_script "$TEST_TMPDIR")

    local exit_code=0
    bash "$script_copy" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "1" "$exit_code" "exit code"
    # Il file mktemp deve essere stato rimosso dal cleanup dello script
    local remaining
    remaining=$(count_created_files "$TEST_TMPDIR" "20260306_120006" "png")
    assert_equals "0" "$remaining" "file temp eliminato dopo errore"
    assert_mock_called_with "notify-send" "Errore" "notifica errore salvataggio"
}

# --- Test 12: Immagine vuota (0 bytes) ---
test_empty_image() {
    setup_base_mocks
    setup_xclip_mock "image/png" ""
    create_date_mock "20260306_120007"

    local script_copy
    script_copy=$(prepare_script "$TEST_TMPDIR")

    local exit_code=0
    bash "$script_copy" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "1" "$exit_code" "exit code"
    # Il file mktemp deve essere stato rimosso dal cleanup dello script
    local remaining
    remaining=$(count_created_files "$TEST_TMPDIR" "20260306_120007" "png")
    assert_equals "0" "$remaining" "file temp eliminato dopo immagine vuota"
    assert_mock_called_with "notify-send" "vuota" "notifica immagine vuota"
}

# --- Test 13: notify-send assente ---
test_no_notify_send() {
    setup_restricted_path
    # shellcheck disable=SC2016 # Single quotes intenzionali: corpo dello script mock
    create_mock "xdotool" 'case "$1" in getactivewindow) echo "12345";; esac'
    setup_xclip_mock "image/png" "PNG_IMAGE_BYTES"
    create_date_mock "20260306_120008"

    local script_copy
    script_copy=$(prepare_script "$TEST_TMPDIR")

    local exit_code=0
    bash "$script_copy" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "0" "$exit_code" "exit code"
    local created_file
    created_file=$(find_created_file "$TEST_TMPDIR" "20260306_120008" "png")
    if [ -z "$created_file" ]; then
        _test_fail "file non creato senza notify-send"
        return
    fi
    assert_file_content_equals "$created_file" "PNG_IMAGE_BYTES" "contenuto corretto"
}

# --- Test 14: Fallback xdotool senza finestra attiva ---
test_no_active_window() {
    # xdotool getactivewindow fallisce → lo script usa il fallback (type senza --window)
    # shellcheck disable=SC2016 # Single quotes intenzionali: corpo dello script mock
    create_mock "xdotool" 'if [ "$1" = "getactivewindow" ]; then exit 1; fi'
    create_mock "notify-send" ""
    setup_xclip_mock "image/png" "PNG_IMAGE_BYTES"
    create_date_mock "20260306_120009"

    local script_copy
    script_copy=$(prepare_script "$TEST_TMPDIR")

    local exit_code=0
    bash "$script_copy" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "0" "$exit_code" "exit code"
    local created_file
    created_file=$(find_created_file "$TEST_TMPDIR" "20260306_120009" "png")
    if [ -z "$created_file" ]; then
        _test_fail "file non creato"
        return
    fi
    # Verifica che xdotool type sia chiamato SENZA --window (branch fallback)
    if grep "^xdotool type" "$MOCK_CALL_LOG" | grep -q -- "--window"; then
        _test_fail "xdotool type non dovrebbe usare --window nel fallback"
    fi
    # Verifica che il type sia chiamato con --clearmodifiers e il path
    assert_mock_called_with "xdotool" "type --clearmodifiers $created_file" "type fallback con path"
}

# --- Test 15: MIME type JPEG non confuso con PNG ---
test_jpeg_mime_not_confused() {
    # TARGETS contiene solo image/jpeg (nessun PNG)
    # Lo script DEVE usare image/jpeg per il salvataggio, non image/png
    setup_base_mocks
    setup_xclip_mock "image/jpeg" "JPEG_ONLY_DATA"
    create_date_mock "20260306_120010"

    local script_copy
    script_copy=$(prepare_script "$TEST_TMPDIR")

    local exit_code=0
    bash "$script_copy" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "0" "$exit_code" "exit code"
    # Il file DEVE avere estensione .jpg, NON .png
    local created_jpg created_png_count
    created_jpg=$(find_created_file "$TEST_TMPDIR" "20260306_120010" "jpg")
    created_png_count=$(count_created_files "$TEST_TMPDIR" "20260306_120010" "png")
    if [ -z "$created_jpg" ]; then
        _test_fail "file .jpg non creato"
        return
    fi
    assert_equals "0" "$created_png_count" "NON deve creare .png"
    # La chiamata xclip -o DEVE usare image/jpeg
    assert_mock_called_with "xclip" "-t image/jpeg -o" "salvataggio con MIME jpeg"
    assert_file_content_equals "$created_jpg" "JPEG_ONLY_DATA" "contenuto jpeg"
}

# --- Test 16: Pulizia elimina file vecchi, preserva quelli recenti ---
test_cleanup_deletes_old_preserves_recent() {
    setup_base_mocks
    setup_xclip_mock "image/png" "PNG_IMAGE_BYTES"
    create_date_mock "20260306_120016"

    local script_copy
    script_copy=$(prepare_script "$TEST_TMPDIR")

    # Crea file vecchi (>7 giorni) che devono essere eliminati dalla pulizia
    touch "$TEST_TMPDIR/paste_image_old1.png"
    touch "$TEST_TMPDIR/paste_image_old2.jpg"
    touch -d "10 days ago" "$TEST_TMPDIR/paste_image_old1.png"
    touch -d "10 days ago" "$TEST_TMPDIR/paste_image_old2.jpg"

    # Crea file recenti (<7 giorni) che devono essere preservati
    touch "$TEST_TMPDIR/paste_image_recent.png"
    touch "$TEST_TMPDIR/paste_image_recent.jpg"

    local exit_code=0
    bash "$script_copy" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "0" "$exit_code" "exit code"
    # I file vecchi devono essere stati eliminati
    assert_file_not_exists "$TEST_TMPDIR/paste_image_old1.png" "png vecchio eliminato"
    assert_file_not_exists "$TEST_TMPDIR/paste_image_old2.jpg" "jpg vecchio eliminato"
    # I file recenti devono essere ancora presenti
    assert_file_exists "$TEST_TMPDIR/paste_image_recent.png" "png recente preservato"
    assert_file_exists "$TEST_TMPDIR/paste_image_recent.jpg" "jpg recente preservato"
}

# --- Test 17: Pulizia non tocca file con pattern diverso ---
test_cleanup_ignores_non_matching() {
    setup_base_mocks
    setup_xclip_mock "image/png" "PNG_IMAGE_BYTES"
    create_date_mock "20260306_120017"

    local script_copy
    script_copy=$(prepare_script "$TEST_TMPDIR")

    # Crea file vecchio con nome che non matcha paste_image_*
    touch "$TEST_TMPDIR/screenshot_20260101.png"
    touch -d "10 days ago" "$TEST_TMPDIR/screenshot_20260101.png"

    local exit_code=0
    bash "$script_copy" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "0" "$exit_code" "exit code"
    # Il file con pattern diverso non deve essere toccato
    assert_file_exists "$TEST_TMPDIR/screenshot_20260101.png" "file non matching preservato"
}

# --- Esecuzione ---

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
run_test "OUTPUT_DIR non scrivibile → fallback" test_output_dir_fallback
run_test "xclip salvataggio fallisce" test_xclip_save_fails
run_test "Immagine vuota (0 bytes)" test_empty_image
run_test "notify-send assente" test_no_notify_send
run_test "Fallback senza finestra attiva" test_no_active_window
run_test "MIME JPEG non confuso con PNG" test_jpeg_mime_not_confused
run_test "Pulizia: elimina file vecchi, preserva recenti" test_cleanup_deletes_old_preserves_recent
run_test "Pulizia: ignora file con pattern diverso" test_cleanup_ignores_non_matching

print_summary "test_paste_image.sh"
