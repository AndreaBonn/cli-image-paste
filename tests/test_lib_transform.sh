#!/usr/bin/env bash
#
# test_lib_transform.sh — Conversione di formato
#
# Dove ImageMagick è installato la conversione viene provata davvero, non
# solo mockata: un test che asserisce solo gli argomenti passati non
# accorgerebbe che il file prodotto non è un PNG valido.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

_LIB="$(cd "$SCRIPT_DIR/.." && pwd)/lib"
# shellcheck source=../lib/40_transform.sh
source "$_LIB/40_transform.sh"

# I test che richiedono ImageMagick reale vengono saltati dove non c'è, ma
# lo dichiarano: un test saltato in silenzio si confonde con uno passato.
_have_magick() {
    command -v magick &>/dev/null || command -v convert &>/dev/null
}

skip_notice() {
    echo "    SALTATO: $1" >&2
}

# --- Rilevamento del binario ---

test_magick_bin_prefers_im7() {
    create_mock "magick" ""
    create_mock "convert" ""
    assert_equals "magick" "$(transform_magick_bin)" "magick preferito a convert"
}

test_magick_bin_falls_back_to_im6() {
    setup_restricted_path
    create_mock "convert" ""
    assert_equals "convert" "$(transform_magick_bin)" "convert usato senza magick"
}

test_magick_absent_is_reported() {
    setup_restricted_path
    if transform_magick_available; then
        _test_fail "ImageMagick riportato presente senza alcun binario"
    fi
}

# --- Messaggi di errore ---

# "Manca ImageMagick" e "ImageMagick non sa rasterizzare SVG" richiedono
# azioni diverse: il messaggio deve distinguerle.
test_missing_message_distinguishes_svg() {
    setup_restricted_path
    local msg
    msg=$(transform_missing_message "image/svg+xml")
    assert_contains "$msg" "rsvg-convert" "SVG nomina il rasterizzatore"

    msg=$(transform_missing_message "image/webp")
    assert_contains "$msg" "imagemagick" "altri formati nominano ImageMagick"
}

test_missing_message_names_the_format() {
    setup_restricted_path
    assert_contains "$(transform_missing_message "image/tiff")" "image/tiff" "il formato è nominato"
}

# --- Policy ---

# La policy di sistema è assente su alcune distribuzioni e permissiva su
# altre: ImageMagick ha una storia di delegate che eseguono comandi, e qui
# l'input arriva dagli appunti.
test_policy_file_is_generated() {
    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    local dir
    dir=$(_transform_policy_dir)
    assert_file_exists "$dir/policy.xml" "policy generata"
    assert_file_contains "$dir/policy.xml" 'domain="delegate" rights="none" pattern="*"' \
        "delegate disabilitati"
    assert_file_contains "$dir/policy.xml" 'pattern="MSL"' "coder MSL disabilitato"
    assert_file_contains "$dir/policy.xml" 'pattern="MVG"' "coder MVG disabilitato"
    unset XDG_STATE_HOME
}

test_limits_are_passed() {
    local limits
    limits=$(_transform_limits)
    assert_contains "$limits" "-limit memory" "limite di memoria"
    assert_contains "$limits" "-limit disk" "limite di disco"
}

# --- Conversione reale ---

test_webp_converted_to_png() {
    if ! _have_magick; then
        skip_notice "ImageMagick non installato"
        return
    fi

    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    local bin src dst
    bin=$(transform_magick_bin)
    src="$TEST_TMPDIR/origine.webp"
    dst="$TEST_TMPDIR/risultato.png"

    if ! "$bin" -size 32x24 xc:red "webp:$src" 2>/dev/null; then
        skip_notice "questo ImageMagick non sa scrivere WebP"
        unset XDG_STATE_HOME
        return
    fi

    if ! image_convert "$src" "$dst" "image/webp"; then
        _test_fail "conversione fallita"
        unset XDG_STATE_HOME
        return
    fi

    assert_file_exists "$dst" "PNG prodotto"
    local kind
    kind=$(file -b --mime-type "$dst" 2>/dev/null)
    assert_equals "image/png" "$kind" "il risultato è davvero un PNG"
    unset XDG_STATE_HOME
}

# Una GIF animata ha più frame: senza selezione esplicita del primo,
# ImageMagick produrrebbe un file per frame invece di una sola immagine.
test_animated_gif_yields_single_frame() {
    if ! _have_magick; then
        skip_notice "ImageMagick non installato"
        return
    fi

    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    local bin src dst
    bin=$(transform_magick_bin)
    src="$TEST_TMPDIR/animata.gif"
    dst="$TEST_TMPDIR/frame.png"

    "$bin" -delay 10 -size 16x16 xc:red xc:blue xc:green "$src" 2>/dev/null

    if ! image_convert "$src" "$dst" "image/gif"; then
        _test_fail "conversione GIF fallita"
        unset XDG_STATE_HOME
        return
    fi

    assert_file_exists "$dst" "PNG prodotto"
    local extra=0 f
    for f in "$TEST_TMPDIR"/frame-*.png; do
        [ -f "$f" ] && extra=$((extra + 1))
    done
    assert_equals "0" "$extra" "nessun file per-frame aggiuntivo"
    unset XDG_STATE_HOME
}

test_metadata_stripped() {
    if ! _have_magick || ! command -v identify &>/dev/null; then
        skip_notice "ImageMagick o identify non disponibili"
        return
    fi

    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    local bin src dst
    bin=$(transform_magick_bin)
    src="$TEST_TMPDIR/con-commento.png"
    dst="$TEST_TMPDIR/pulito.png"

    "$bin" -size 16x16 xc:red -set comment "dato-riservato" "$src" 2>/dev/null
    image_convert "$src" "$dst" "image/png"

    local props
    props=$(identify -verbose "$dst" 2>/dev/null)
    assert_not_contains "$props" "dato-riservato" "commento rimosso dal risultato"
    unset XDG_STATE_HOME
}

test_conversion_fails_on_garbage_input() {
    if ! _have_magick; then
        skip_notice "ImageMagick non installato"
        return
    fi

    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    printf 'questo non e una immagine' > "$TEST_TMPDIR/finto.webp"

    if image_convert "$TEST_TMPDIR/finto.webp" "$TEST_TMPDIR/out.png" "image/webp"; then
        _test_fail "conversione riuscita su input non valido"
    fi
    unset XDG_STATE_HOME
}

test_svg_without_rasteriser_fails() {
    setup_restricted_path
    printf '<svg xmlns="http://www.w3.org/2000/svg"/>' > "$TEST_TMPDIR/x.svg"

    if image_convert_svg "$TEST_TMPDIR/x.svg" "$TEST_TMPDIR/x.png"; then
        _test_fail "rasterizzazione riuscita senza rsvg-convert"
    fi
}

run_test "magick preferito a convert" test_magick_bin_prefers_im7
run_test "Fallback su convert" test_magick_bin_falls_back_to_im6
run_test "Assenza di ImageMagick rilevata" test_magick_absent_is_reported
run_test "Messaggio distingue SVG" test_missing_message_distinguishes_svg
run_test "Messaggio nomina il formato" test_missing_message_names_the_format
run_test "Policy restrittiva generata" test_policy_file_is_generated
run_test "Limiti di risorsa passati" test_limits_are_passed
run_test "WebP convertito in PNG" test_webp_converted_to_png
run_test "GIF animata: un solo frame" test_animated_gif_yields_single_frame
run_test "Metadati rimossi" test_metadata_stripped
run_test "Input non valido fallisce" test_conversion_fails_on_garbage_input
run_test "SVG senza rasterizzatore fallisce" test_svg_without_rasteriser_fails

print_summary "test_lib_transform.sh"
