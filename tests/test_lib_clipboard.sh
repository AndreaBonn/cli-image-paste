#!/usr/bin/env bash
#
# test_lib_clipboard.sh — Lettura appunti, priorità dei target, uri-list
#
# Il parsing degli URI è una superficie di attacco: il path estratto viene
# digitato nel terminale, dove un carattere di controllo equivale a premere
# Invio. Il decode percent va fatto prima della validazione, mai dopo.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

VERSION="test"
_LIB="$(cd "$SCRIPT_DIR/.." && pwd)/lib"
# shellcheck source=../lib/05_text.sh
source "$_LIB/05_text.sh"
# shellcheck source=../lib/10_env_detect.sh
source "$_LIB/10_env_detect.sh"
# shellcheck source=../lib/20_clipboard.sh
source "$_LIB/20_clipboard.sh"
# shellcheck source=../lib/30_delivery.sh
source "$_LIB/30_delivery.sh"

CR=$'\r'

# --- Scelta del target ---

test_png_preferred_over_jpeg() {
    assert_equals "native|image/png" \
        "$(clipboard_pick_target "$(printf 'image/jpeg\nimage/png')" 0)" \
        "PNG prima di JPEG"
}

test_native_preferred_over_convertible() {
    assert_equals "native|image/png" \
        "$(clipboard_pick_target "$(printf 'image/webp\nimage/png')" 0)" \
        "formato nativo prima di uno da convertire"
}

test_convertible_when_no_native() {
    assert_equals "convert|image/webp" \
        "$(clipboard_pick_target "image/webp" 0)" \
        "webp riconosciuto come convertibile"
}

# Un file già su disco non va duplicato: il suo path è stabile e non scade
# con la pulizia dei temporanei.
test_existing_file_wins_by_default() {
    assert_equals "file|x-special/gnome-copied-files" \
        "$(clipboard_pick_target "$(printf 'x-special/gnome-copied-files\nimage/png')" 1)" \
        "riferimento a file prima dei byte"
}

test_existing_file_can_be_deprioritised() {
    assert_equals "native|image/png" \
        "$(clipboard_pick_target "$(printf 'x-special/gnome-copied-files\nimage/png')" 0)" \
        "con la preferenza disattivata vincono i byte"
}

test_uri_target_is_last_resort_when_deprioritised() {
    assert_equals "file|text/uri-list" \
        "$(clipboard_pick_target "text/uri-list" 0)" \
        "meglio un path che nessuna immagine"
}

test_no_usable_target() {
    if clipboard_pick_target "$(printf 'text/plain\nTARGETS')" 1 >/dev/null; then
        _test_fail "target inutilizzabili accettati"
    fi
}

# Il confronto è per riga intera: una sottostringa produrrebbe falsi
# positivi fra "image/png" e un ipotetico "image/png-fake".
test_target_match_is_exact() {
    if clipboard_pick_target "image/png-fake" 1 >/dev/null; then
        _test_fail "target simile accettato come PNG"
    fi
}

# --- Decodifica degli URI ---

test_uri_decode_basic() {
    assert_equals "/tmp/con spazio.png" "$(uri_decode "/tmp/con%20spazio.png")" "spazio decodificato"
    assert_equals "/tmp/normale.png" "$(uri_decode "/tmp/normale.png")" "nulla da decodificare"
}

# printf '%b' interpreterebbe i backslash presenti nel nome del file:
# "a\nb.png" diventerebbe un path con dentro un newline vero.
test_uri_decode_preserves_backslash() {
    assert_equals '/tmp/a\nb.png' "$(uri_decode '/tmp/a\nb.png')" "backslash letterale conservato"
}

# Il '+' vale come spazio nelle query string, non nella parte path
test_uri_decode_keeps_plus() {
    assert_equals "/tmp/a+b.png" "$(uri_decode "/tmp/a+b.png")" "il piu' resta un piu'"
}

# --- Estrazione del path ---

test_gnome_copied_files_format() {
    local payload
    payload=$(printf 'copy\nfile://%s/uno.png' "$TEST_TMPDIR")
    make_fake_image "$TEST_TMPDIR/uno.png"
    assert_equals "$TEST_TMPDIR/uno.png" "$(clipboard_file_from_uri "$payload")" \
        "prima riga 'copy' saltata"
}

test_cut_line_also_skipped() {
    local payload
    payload=$(printf 'cut\nfile://%s/due.png' "$TEST_TMPDIR")
    make_fake_image "$TEST_TMPDIR/due.png"
    assert_equals "$TEST_TMPDIR/due.png" "$(clipboard_file_from_uri "$payload")" \
        "prima riga 'cut' saltata"
}

# Lo standard usa CRLF: il CR va rimosso, altrimenti finisce nel path e
# viene digitato nel terminale, dove equivale a premere Invio.
test_crlf_terminators_stripped() {
    local payload
    payload=$(printf 'file://%s/tre.png%s' "$TEST_TMPDIR" "$CR")
    make_fake_image "$TEST_TMPDIR/tre.png"
    assert_equals "$TEST_TMPDIR/tre.png" "$(clipboard_file_from_uri "$payload")" \
        "CR finale rimosso"
}

test_comment_lines_ignored() {
    local payload
    payload=$(printf '# commento\nfile://%s/quattro.png' "$TEST_TMPDIR")
    make_fake_image "$TEST_TMPDIR/quattro.png"
    assert_equals "$TEST_TMPDIR/quattro.png" "$(clipboard_file_from_uri "$payload")" \
        "riga di commento saltata"
}

test_percent_encoded_path_resolved() {
    local payload
    make_fake_image "$TEST_TMPDIR/con spazio.png"
    payload="file://${TEST_TMPDIR}/con%20spazio.png"
    assert_equals "$TEST_TMPDIR/con spazio.png" "$(clipboard_file_from_uri "$payload")" \
        "percent-encoding risolto"
}

test_non_file_schemes_rejected() {
    local uri
    for uri in "http://evil.example/x.png" "trash:///immagine.png" "admin:///etc/shadow"; do
        if clipboard_file_from_uri "$uri" >/dev/null; then
            _test_fail "schema non-file accettato: $uri"
        fi
    done
}

# Una riga di uri-list deve contenere un URI, non un path nudo. Senza il
# filtro sullo schema un path assoluto verrebbe accettato così com'è: è il
# caso in cui quel controllo non è ridondante rispetto alla validazione,
# che un path assoluto lo passa senza obiezioni.
test_bare_path_without_scheme_rejected() {
    make_fake_image "$TEST_TMPDIR/nudo.png"

    if clipboard_file_from_uri "$TEST_TMPDIR/nudo.png" >/dev/null; then
        _test_fail "path nudo senza schema accettato come URI"
    fi
}

test_missing_file_rejected() {
    if clipboard_file_from_uri "file://$TEST_TMPDIR/non-esiste.png" >/dev/null; then
        _test_fail "riferimento a file inesistente accettato"
    fi
}

# Il decode precede la validazione: %0D diventa un CR solo dopo, e un
# controllo fatto prima non lo vedrebbe.
test_encoded_control_chars_rejected() {
    local encoded
    for encoded in "%0D" "%0A" "%1b"; do
        if clipboard_file_from_uri "file://$TEST_TMPDIR/a${encoded}b.png" >/dev/null; then
            _test_fail "path con carattere di controllo codificato accettato ($encoded)"
        fi
    done
}

# Il test precedente non discrimina la validazione: un file con un CR nel
# nome di solito non esiste, quindi verrebbe scartato comunque dal controllo
# di esistenza. Qui il file ostile viene creato davvero (su Linux solo '/' e
# NUL sono vietati in un nome), così l'unica barriera rimasta è la
# validazione. È il caso reale: un archivio scompattato o un repository
# clonato può contenerlo, e copiarlo dal file manager è un gesto normale.
test_existing_file_with_control_char_in_name_rejected() {
    local hostile="$TEST_TMPDIR/innocuo${CR}id.png"
    make_fake_image "$hostile"

    if [ ! -f "$hostile" ]; then
        _test_fail "impossibile creare il file ostile, test non significativo"
        return
    fi

    if clipboard_file_from_uri "file://$TEST_TMPDIR/innocuo%0Did.png" >/dev/null; then
        _test_fail "path di un file ESISTENTE con CR nel nome accettato"
    fi
}

# Stesso ragionamento per gli override bidirezionali: il file esiste, quindi
# solo la validazione può fermarlo.
test_existing_file_with_bidi_override_rejected() {
    local marker hostile
    marker=$(printf '‮')
    hostile="$TEST_TMPDIR/${marker}gnp.exe"
    make_fake_image "$hostile"

    if [ ! -f "$hostile" ]; then
        _test_fail "impossibile creare il file ostile, test non significativo"
        return
    fi

    if clipboard_file_from_uri "file://$TEST_TMPDIR/%E2%80%AEgnp.exe" >/dev/null; then
        _test_fail "path di un file ESISTENTE con override bidirezionale accettato"
    fi
}

test_bidi_override_rejected() {
    if clipboard_file_from_uri "file://$TEST_TMPDIR/%E2%80%AEgnp.exe" >/dev/null; then
        _test_fail "path con override bidirezionale accettato"
    fi
}

# Il primo URI utilizzabile vince, gli altri vengono ignorati
test_first_usable_uri_wins() {
    local payload
    make_fake_image "$TEST_TMPDIR/valido.png"
    payload=$(printf 'copy\nfile://%s/assente.png\nfile://%s/valido.png' "$TEST_TMPDIR" "$TEST_TMPDIR")
    assert_equals "$TEST_TMPDIR/valido.png" "$(clipboard_file_from_uri "$payload")" \
        "si scende al primo URI utilizzabile"
}

# --- Estensioni ---

test_extension_mapping() {
    assert_equals "png" "$(clipboard_extension_for image/png)" "png"
    assert_equals "jpg" "$(clipboard_extension_for image/jpeg)" "jpeg"
    assert_equals "webp" "$(clipboard_extension_for image/webp)" "webp"
    assert_equals "svg" "$(clipboard_extension_for image/svg+xml)" "svg"
    assert_equals "bin" "$(clipboard_extension_for application/octet-stream)" "sconosciuto"
}

# --- Backend ---

test_wayland_uses_wl_paste() {
    create_mock "wl-paste" ""
    export PASTE_IMAGE_SESSION_TYPE=wayland
    assert_equals "wl-paste" "$(_clipboard_tool)" "wl-paste su Wayland"
    unset PASTE_IMAGE_SESSION_TYPE
}

test_x11_uses_xclip() {
    create_mock "xclip" ""
    export PASTE_IMAGE_SESSION_TYPE=x11
    assert_equals "xclip" "$(_clipboard_tool)" "xclip su X11"
    unset PASTE_IMAGE_SESSION_TYPE
}

test_list_targets_uses_right_flags() {
    create_mock "wl-paste" ""
    export PASTE_IMAGE_SESSION_TYPE=wayland
    clipboard_list_targets >/dev/null 2>&1
    assert_mock_called_with "wl-paste" "list-types" "flag corretto per wl-paste"
    unset PASTE_IMAGE_SESSION_TYPE
}

run_test "PNG preferito a JPEG" test_png_preferred_over_jpeg
run_test "Nativo preferito a convertibile" test_native_preferred_over_convertible
run_test "Convertibile senza nativo" test_convertible_when_no_native
run_test "File esistente vince di default" test_existing_file_wins_by_default
run_test "Preferenza file disattivabile" test_existing_file_can_be_deprioritised
run_test "URI come ultima risorsa" test_uri_target_is_last_resort_when_deprioritised
run_test "Nessun target utilizzabile" test_no_usable_target
run_test "Confronto target esatto" test_target_match_is_exact
run_test "Decodifica percent" test_uri_decode_basic
run_test "Backslash letterale conservato" test_uri_decode_preserves_backslash
run_test "Il piu' non diventa spazio" test_uri_decode_keeps_plus
run_test "Formato Nautilus" test_gnome_copied_files_format
run_test "Riga 'cut' saltata" test_cut_line_also_skipped
run_test "Terminatori CRLF rimossi" test_crlf_terminators_stripped
run_test "Righe di commento ignorate" test_comment_lines_ignored
run_test "Path percent-encoded risolto" test_percent_encoded_path_resolved
run_test "Schemi non-file rifiutati" test_non_file_schemes_rejected
run_test "File inesistente rifiutato" test_missing_file_rejected
run_test "Path nudo senza schema rifiutato" test_bare_path_without_scheme_rejected
run_test "Control char codificati rifiutati" test_encoded_control_chars_rejected
run_test "Override bidirezionale rifiutato" test_bidi_override_rejected
run_test "File esistente con CR nel nome rifiutato" test_existing_file_with_control_char_in_name_rejected
run_test "File esistente con override bidi rifiutato" test_existing_file_with_bidi_override_rejected
run_test "Primo URI utilizzabile vince" test_first_usable_uri_wins
run_test "Mappatura delle estensioni" test_extension_mapping
run_test "Wayland usa wl-paste" test_wayland_uses_wl_paste
run_test "X11 usa xclip" test_x11_uses_xclip
run_test "Flag corretti per la lista target" test_list_targets_uses_right_flags

print_summary "test_lib_clipboard.sh"
