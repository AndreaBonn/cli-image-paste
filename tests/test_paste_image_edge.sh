#!/usr/bin/env bash
#
# test_paste_image_edge.sh — Fallback, errori di salvataggio, notifiche, pulizia
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"
# shellcheck source=framework/paste_image_helpers.sh
source "$SCRIPT_DIR/framework/paste_image_helpers.sh"

# --- Test 10: OUTPUT_DIR non scrivibile → fallback ---
test_output_dir_fallback() {
    setup_base_mocks
    setup_xclip_mock "image/png" "PNG_IMAGE_BYTES"
    create_date_mock "20260306_120005"

    local readonly_dir="$TEST_TMPDIR/readonly_output"
    mkdir -p "$readonly_dir"
    chmod 444 "$readonly_dir"

    use_output_dir "$readonly_dir"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

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

    use_output_dir "$TEST_TMPDIR"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

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

    use_output_dir "$TEST_TMPDIR"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

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
    set_session_env x11 gnome
    # shellcheck disable=SC2016 # Single quotes intenzionali: corpo dello script mock
    create_mock "xdotool" 'case "$1" in getactivewindow) echo "12345";; esac'
    setup_xclip_mock "image/png" "PNG_IMAGE_BYTES"
    create_date_mock "20260306_120008"

    use_output_dir "$TEST_TMPDIR"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

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
    set_session_env x11 gnome
    # shellcheck disable=SC2016 # Single quotes intenzionali: corpo dello script mock
    create_mock "xdotool" 'if [ "$1" = "getactivewindow" ]; then exit 1; fi'
    create_mock "notify-send" ""
    setup_xclip_mock "image/png" "PNG_IMAGE_BYTES"
    create_date_mock "20260306_120009"

    use_output_dir "$TEST_TMPDIR"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

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

    use_output_dir "$TEST_TMPDIR"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

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

    use_output_dir "$TEST_TMPDIR"

    # Crea file vecchi (>7 giorni) che devono essere eliminati dalla pulizia
    touch "$TEST_TMPDIR/paste_image_old1.png"
    touch "$TEST_TMPDIR/paste_image_old2.jpg"
    touch -d "10 days ago" "$TEST_TMPDIR/paste_image_old1.png"
    touch -d "10 days ago" "$TEST_TMPDIR/paste_image_old2.jpg"

    # Crea file recenti (<7 giorni) che devono essere preservati
    touch "$TEST_TMPDIR/paste_image_recent.png"
    touch "$TEST_TMPDIR/paste_image_recent.jpg"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

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

    use_output_dir "$TEST_TMPDIR"

    # Crea file vecchio con nome che non matcha paste_image_*
    touch "$TEST_TMPDIR/screenshot_20260101.png"
    touch -d "10 days ago" "$TEST_TMPDIR/screenshot_20260101.png"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "0" "$exit_code" "exit code"
    # Il file con pattern diverso non deve essere toccato
    assert_file_exists "$TEST_TMPDIR/screenshot_20260101.png" "file non matching preservato"
}

# --- Esecuzione ---

run_test "OUTPUT_DIR non scrivibile → fallback" test_output_dir_fallback
run_test "xclip salvataggio fallisce" test_xclip_save_fails
run_test "Immagine vuota (0 bytes)" test_empty_image
run_test "notify-send assente" test_no_notify_send
run_test "Fallback senza finestra attiva" test_no_active_window
run_test "MIME JPEG non confuso con PNG" test_jpeg_mime_not_confused
run_test "Pulizia: elimina file vecchi, preserva recenti" test_cleanup_deletes_old_preserves_recent
run_test "Pulizia: ignora file con pattern diverso" test_cleanup_ignores_non_matching

print_summary "test_paste_image_edge.sh"
