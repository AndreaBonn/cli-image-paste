#!/usr/bin/env bash
#
# test_paste_image_sources.sh — Sorgenti alternative, end-to-end
#
# Esercita l'artefatto completo, non le singole funzioni: verifica che
# l'orchestratore colleghi davvero scelta del target, acquisizione e
# consegna.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"
# shellcheck source=framework/paste_image_helpers.sh
source "$SCRIPT_DIR/framework/paste_image_helpers.sh"

ensure_built

# Mock di xclip che annuncia i target indicati e restituisce, per il target
# richiesto, il payload corrispondente.
setup_xclip_payload_mock() {
    local targets="$1" payload="$2"

    cat > "$MOCK_BIN/xclip" <<XCLIP_EOF
#!/usr/bin/env bash
echo "xclip \$*" >> "\$MOCK_CALL_LOG"

TARGET=""
prev=""
for arg in "\$@"; do
    case "\$prev" in
        -t) TARGET="\$arg" ;;
    esac
    prev="\$arg"
done

if [ "\$TARGET" = "TARGETS" ]; then
    printf '%s\n' "$targets"
elif [ -n "\$TARGET" ]; then
    if echo "\$*" | grep -q '\-o'; then
        printf '%s' "$payload"
    fi
fi
XCLIP_EOF
    chmod +x "$MOCK_BIN/xclip"
}

count_images_in() {
    local dir="$1" count=0 f
    for f in "$dir"/paste_image_*; do
        [ -f "$f" ] && count=$((count + 1))
    done
    echo "$count"
}

# --- Un file copiato dal file manager non viene duplicato ---

test_existing_file_is_not_copied() {
    setup_base_mocks
    use_output_dir "$TEST_TMPDIR"

    local original="$TEST_TMPDIR/originale.png"
    make_fake_image "$original"

    setup_xclip_payload_mock "x-special/gnome-copied-files
image/png" "copy
file://$original"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "0" "$exit_code" "operazione completata"
    assert_mock_called_with "xdotool" "type.*$original" "digitato il path originale"
    assert_file_exists "$original" "l'originale è intatto"
    # Il contatore cerca il prefisso dei file generati dal tool: zero
    # significa che nessuna copia è stata prodotta.
    assert_equals "0" "$(count_images_in "$TEST_TMPDIR")" \
        "nessuna copia del file già su disco"
}

# --- Un riferimento rotto ripiega sui byte dell'immagine ---

test_broken_reference_falls_back_to_bytes() {
    setup_base_mocks
    use_output_dir "$TEST_TMPDIR"
    create_date_mock "20260306_130000"

    setup_xclip_payload_mock "x-special/gnome-copied-files
image/png" "copy
file://$TEST_TMPDIR/inesistente.png"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "0" "$exit_code" "operazione completata"
    local created
    created=$(find_created_file "$TEST_TMPDIR" "20260306_130000" "png")
    if [ -z "$created" ]; then
        _test_fail "nessun file creato dal ripiego sui byte"
    fi
}

# --- Un URI con schema diverso da file:// non viene seguito ---

test_non_file_uri_is_not_followed() {
    setup_base_mocks
    use_output_dir "$TEST_TMPDIR"
    create_date_mock "20260306_130001"

    setup_xclip_payload_mock "text/uri-list
image/png" "http://esempio.invalido/immagine.png"

    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || true

    assert_mock_not_called_with_pattern "xdotool" "esempio.invalido" \
        "l'URL remoto non viene digitato"
}

# Helper locale: variante negativa di assert_mock_called_with
assert_mock_not_called_with_pattern() {
    local cmd="$1" pattern="$2" label="$3"
    if grep "^${cmd} " "$MOCK_CALL_LOG" 2>/dev/null | grep -q -- "$pattern"; then
        _test_fail "$label: il mock '$cmd' è stato chiamato con '$pattern'"
    fi
}

# --- Formato non gestito senza convertitore: messaggio esplicito ---

test_unsupported_format_names_the_tool() {
    setup_restricted_path date find flock
    create_mock "notify-send" ""
    use_output_dir "$TEST_TMPDIR"

    setup_xclip_payload_mock "image/tiff" "BYTE_TIFF"

    local exit_code=0
    bash "$PASTE_IMAGE_SCRIPT" >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "1" "$exit_code" "operazione rifiutata"
    assert_mock_called_with "notify-send" "imagemagick" \
        "la notifica nomina il pacchetto da installare"
}

run_test "File dal file manager non duplicato" test_existing_file_is_not_copied
run_test "Riferimento rotto: ripiego sui byte" test_broken_reference_falls_back_to_bytes
run_test "URI non-file non seguito" test_non_file_uri_is_not_followed
run_test "Formato non gestito: messaggio utile" test_unsupported_format_names_the_tool

print_summary "test_paste_image_sources.sh"
