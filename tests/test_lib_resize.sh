#!/usr/bin/env bash
#
# test_lib_resize.sh — Ridimensionamento e pulizia degli intermedi
#
# Il resize serve a non spedire uno screenshot 4K quando il modello lo
# ridimensionerebbe comunque: costa banda e token senza aggiungere
# dettaglio utilizzabile.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

_LIB="$(cd "$SCRIPT_DIR/.." && pwd)/lib"
# shellcheck source=../lib/40_transform.sh
source "$_LIB/40_transform.sh"
# shellcheck source=../lib/45_resize.sh
source "$_LIB/45_resize.sh"

_have_magick() {
    command -v magick &>/dev/null || command -v convert &>/dev/null
}

skip_notice() {
    echo "    SALTATO: $1" >&2
}

# --- Ridimensionamento ---

test_needs_resize_decision_table() {
    local casi=(
        "4000|3000|1568|si"
        "1568|1000|1568|no"
        "1569|1000|1568|si"
        "800|600|1568|no"
        "800|4000|1568|si"
        "4000|3000|0|no"
        "100|100|0|no"
    )
    local caso w h max atteso resto esito
    for caso in "${casi[@]}"; do
        w="${caso%%|*}"; resto="${caso#*|}"
        h="${resto%%|*}"; resto="${resto#*|}"
        max="${resto%%|*}"; atteso="${resto##*|}"
        if image_needs_resize "$w" "$h" "$max"; then esito="si"; else esito="no"; fi
        assert_equals "$atteso" "$esito" "${w}x${h} con limite $max"
    done
}

test_resize_produces_expected_dimensions() {
    if ! _have_magick; then skip_notice "ImageMagick non installato"; return; fi

    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    local bin src dst dims
    bin=$(transform_magick_bin)
    src="$TEST_TMPDIR/grande.png"
    dst="$TEST_TMPDIR/ridotta.png"

    "$bin" -size 4000x3000 xc:blue "$src" 2>/dev/null
    image_resize "$src" "$dst" 1568

    dims=$(image_dimensions "$dst")
    assert_equals "1568 1176" "$dims" "proporzioni mantenute sul lato lungo"
    unset XDG_STATE_HOME
}

# Ridimensionare un'immagine già piccola la ricomprimerebbe senza guadagno.
test_small_image_left_untouched() {
    if ! _have_magick; then skip_notice "ImageMagick non installato"; return; fi

    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    local bin src result
    bin=$(transform_magick_bin)
    src="$TEST_TMPDIR/piccola.png"
    "$bin" -size 800x600 xc:red "$src" 2>/dev/null

    result=$(transform_apply_resize "$src" 1568 "$TEST_TMPDIR")
    assert_equals "$src" "$result" "restituito l'originale, nessun file nuovo"
    unset XDG_STATE_HOME
}

# L'originale può essere un file dell'utente indicato dal file manager:
# modificarlo sul posto sarebbe alterare un suo file senza richiesta.
test_original_never_modified_in_place() {
    if ! _have_magick; then skip_notice "ImageMagick non installato"; return; fi

    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    local bin src before after result
    bin=$(transform_magick_bin)
    src="$TEST_TMPDIR/originale-utente.png"
    "$bin" -size 3000x2000 xc:green "$src" 2>/dev/null
    before=$(image_dimensions "$src")

    result=$(transform_apply_resize "$src" 1000 "$TEST_TMPDIR")
    after=$(image_dimensions "$src")

    assert_equals "$before" "$after" "dimensioni dell'originale invariate"
    if [ "$result" = "$src" ]; then
        _test_fail "nessun file nuovo prodotto: avrebbe dovuto ridimensionare"
    fi
    unset XDG_STATE_HOME
}

test_resize_disabled_by_zero() {
    if ! _have_magick; then skip_notice "ImageMagick non installato"; return; fi
    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    local bin src result
    bin=$(transform_magick_bin)
    src="$TEST_TMPDIR/enorme.png"
    "$bin" -size 3000x2000 xc:black "$src" 2>/dev/null

    result=$(transform_apply_resize "$src" 0 "$TEST_TMPDIR")
    assert_equals "$src" "$result" "limite 0 disabilita il ridimensionamento"
    unset XDG_STATE_HOME
}

# Uno step accessorio non deve mai far fallire l'operazione: senza
# ImageMagick si prosegue con il file che c'è.
test_resize_degrades_without_magick() {
    setup_restricted_path
    printf 'contenuto' > "$TEST_TMPDIR/x.png"
    local result
    result=$(transform_apply_resize "$TEST_TMPDIR/x.png" 100 "$TEST_TMPDIR")
    assert_equals "$TEST_TMPDIR/x.png" "$result" "restituito l'originale senza errori"
}

# --- Pulizia degli intermedi ---

test_temps_are_cleaned() {
    TRANSFORM_TEMP_DIR="$TEST_TMPDIR"
    local a b
    a=$(_transform_new_temp "$TEST_TMPDIR" png)
    b=$(_transform_new_temp "$TEST_TMPDIR" png)
    assert_file_exists "$a" "primo intermedio creato"
    assert_file_exists "$b" "secondo intermedio creato"

    transform_cleanup_temps
    assert_file_not_exists "$a" "primo intermedio rimosso"
    assert_file_not_exists "$b" "secondo intermedio rimosso"
}

# Il nome dell'intermedio non deve derivare dall'originale per manipolazione
# di stringa: sarebbe la race che mktemp era stato adottato per eliminare.
test_temp_names_are_unique() {
    TRANSFORM_TEMP_DIR="$TEST_TMPDIR"
    local a b
    a=$(_transform_new_temp "$TEST_TMPDIR" png)
    b=$(_transform_new_temp "$TEST_TMPDIR" png)
    if [ "$a" = "$b" ]; then
        _test_fail "due intermedi con lo stesso nome"
    fi
    transform_cleanup_temps
}

# Gli intermedi seguono il pattern usato dalla pulizia automatica, altrimenti
# resterebbero su disco per sempre se qualcosa interrompesse il processo.
test_temp_names_match_cleanup_pattern() {
    TRANSFORM_TEMP_DIR="$TEST_TMPDIR"
    local temp base
    temp=$(_transform_new_temp "$TEST_TMPDIR" png)
    base=$(basename "$temp")
    case "$base" in
        paste_image_*) : ;;
        *) _test_fail "nome '$base' fuori dal pattern di pulizia paste_image_*" ;;
    esac
    transform_cleanup_temps
}

run_test "Tabella di decisione del resize" test_needs_resize_decision_table
run_test "Dimensioni dopo il resize" test_resize_produces_expected_dimensions
run_test "Immagine piccola non toccata" test_small_image_left_untouched
run_test "Originale mai modificato in place" test_original_never_modified_in_place
run_test "Limite 0 disabilita" test_resize_disabled_by_zero
run_test "Degradazione senza ImageMagick" test_resize_degrades_without_magick
run_test "Intermedi rimossi" test_temps_are_cleaned
run_test "Nomi degli intermedi univoci" test_temp_names_are_unique
run_test "Intermedi coperti dalla pulizia" test_temp_names_match_cleanup_pattern


# --- L'originale non deve restare su disco ---

# Dopo il resize l'immagine di partenza non serve più: lasciarla scadere
# insieme al risultato raddoppierebbe le copie dello stesso contenuto, che
# può essere lo screenshot di un gestore di password.
test_our_original_is_removed_after_resize() {
    if ! _have_magick; then skip_notice "ImageMagick non installato"; return; fi

    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    MAX_LONG_SIDE=1000
    RESIZE_ENABLED=1

    local bin src result
    bin=$(transform_magick_bin)
    src="$TEST_TMPDIR/paste_image_20260101_aaaaaa.png"
    "$bin" -size 3000x2000 xc:blue "$src" 2>/dev/null

    result=$(transform_run "$src" "$TEST_TMPDIR")

    assert_file_not_exists "$src" "l'originale prodotto da noi è stato rimosso"
    assert_file_exists "$result" "il risultato esiste"
    unset XDG_STATE_HOME
}

# Un file indicato dal file manager appartiene all'utente: cancellarglielo
# dopo un incolla sarebbe perdita di dati, non pulizia.
test_user_file_is_never_removed() {
    if ! _have_magick; then skip_notice "ImageMagick non installato"; return; fi

    export XDG_STATE_HOME="$TEST_TMPDIR/state"
    MAX_LONG_SIDE=1000
    RESIZE_ENABLED=1

    local bin src result
    bin=$(transform_magick_bin)
    src="$TEST_TMPDIR/foto-delle-vacanze.png"
    "$bin" -size 3000x2000 xc:green "$src" 2>/dev/null

    result=$(transform_run "$src" "$TEST_TMPDIR")

    assert_file_exists "$src" "il file dell'utente è intatto"
    assert_file_exists "$result" "il risultato ridimensionato esiste"
    if [ "$result" = "$src" ]; then
        _test_fail "avrebbe dovuto produrre un file separato"
    fi
    unset XDG_STATE_HOME
}

# Un file nostro ma in un'altra directory non è nostro da cancellare.
test_file_outside_work_dir_is_not_ours() {
    local other="$TEST_TMPDIR/altrove"
    mkdir -p "$other"
    printf 'x' > "$other/paste_image_20260101_bbbbbb.png"

    if _transform_is_our_file "$other/paste_image_20260101_bbbbbb.png" "$TEST_TMPDIR"; then
        _test_fail "considerato nostro un file fuori dalla directory di lavoro"
    fi
}

test_resize_disabled_leaves_everything() {
    RESIZE_ENABLED=0
    local src="$TEST_TMPDIR/paste_image_20260101_cccccc.png"
    printf 'contenuto' > "$src"

    local result
    result=$(transform_run "$src" "$TEST_TMPDIR")
    assert_equals "$src" "$result" "nessuna trasformazione"
    assert_file_exists "$src" "originale conservato"
    RESIZE_ENABLED=1
}

run_test "Originale nostro rimosso dopo il resize" test_our_original_is_removed_after_resize
run_test "File dell'utente mai rimosso" test_user_file_is_never_removed
run_test "File fuori dalla directory non e' nostro" test_file_outside_work_dir_is_not_ours
run_test "Resize disabilitato: nulla cambia" test_resize_disabled_leaves_everything

print_summary "test_lib_resize.sh"
