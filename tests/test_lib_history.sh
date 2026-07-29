#!/usr/bin/env bash
#
# test_lib_history.sh — Storico e riconsegna
#
# La consegna via appunti sovrascrive gli appunti, quindi distrugge
# l'immagine di partenza: senza storico un secondo tentativo richiederebbe di
# rifare lo screenshot. È la rete di sicurezza di una conseguenza diretta del
# modo in cui la consegna funziona su GNOME Wayland.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

_LIB="$(cd "$SCRIPT_DIR/.." && pwd)/lib"
# shellcheck source=../lib/50_store.sh
source "$_LIB/50_store.sh"
# shellcheck source=../lib/55_history.sh
source "$_LIB/55_history.sh"

notify() { echo "notify: $1"; }
log() { :; }

setup_history() {
    LOG_DIR="$TEST_TMPDIR/state"
    HISTORY_SIZE=5
    mkdir -p "$LOG_DIR"
}

make_image() {
    local path="$TEST_TMPDIR/$1"
    make_fake_image "$path"
    echo "$path"
}

# --- Registrazione ---

test_most_recent_is_first() {
    setup_history
    local a b c
    a=$(make_image uno.png); b=$(make_image due.png); c=$(make_image tre.png)

    history_append "$a"
    history_append "$b"
    history_append "$c"

    assert_equals "$c" "$(history_get 1)" "il più recente è in posizione 1"
    assert_equals "$b" "$(history_get 2)" "il precedente è in posizione 2"
    assert_equals "$a" "$(history_get 3)" "il primo è in fondo"
}

test_default_index_is_one() {
    setup_history
    local a
    a=$(make_image uno.png)
    history_append "$a"
    assert_equals "$a" "$(history_get)" "senza indice si prende il più recente"
}

# La stessa immagine consegnata due volte non deve occupare due posizioni:
# sposterebbe in basso quelle davvero diverse.
test_duplicate_is_moved_not_added() {
    setup_history
    local a b
    a=$(make_image uno.png); b=$(make_image due.png)

    history_append "$a"
    history_append "$b"
    history_append "$a"

    assert_equals "$a" "$(history_get 1)" "la ripetizione risale in cima"
    assert_equals "$b" "$(history_get 2)" "l'altra scende di uno"
    local lines
    lines=$(wc -l < "$(history_file)")
    assert_equals "2" "$lines" "nessuna riga duplicata"
}

test_size_limit_is_enforced() {
    setup_history
    HISTORY_SIZE=3
    local i path
    for i in 1 2 3 4 5; do
        path=$(make_image "img$i.png")
        history_append "$path"
    done

    local lines
    lines=$(wc -l < "$(history_file)")
    assert_equals "3" "$lines" "storico potato al limite"
    assert_equals "$TEST_TMPDIR/img5.png" "$(history_get 1)" "resta il più recente"
}

# --- Lettura ---

test_missing_entry_reports_one() {
    setup_history
    local status=0
    history_get 7 >/dev/null || status=$?
    assert_exit_code "1" "$status" "posizione inesistente"
}

test_empty_history_reports_one() {
    setup_history
    local status=0
    history_get 1 >/dev/null || status=$?
    assert_exit_code "1" "$status" "storico vuoto"
}

# Un'immagine può essere stata rimossa dalla pulizia automatica: dirlo è più
# utile che digitare un percorso morto nel terminale.
test_deleted_file_reports_two() {
    setup_history
    local a
    a=$(make_image uno.png)
    history_append "$a"
    rm -f "$a"

    local status=0
    history_get 1 >/dev/null || status=$?
    assert_exit_code "2" "$status" "voce presente ma file scomparso"
}

test_invalid_index_rejected() {
    setup_history
    local a status=0
    a=$(make_image uno.png)
    history_append "$a"

    history_get 0 >/dev/null || status=$?
    assert_exit_code "1" "$status" "indice 0 non valido"

    status=0
    history_get "abc" >/dev/null || status=$?
    assert_exit_code "1" "$status" "indice non numerico"
}

# --- Potatura ---

test_prune_removes_only_missing() {
    setup_history
    local a b
    a=$(make_image uno.png); b=$(make_image due.png)
    history_append "$a"
    history_append "$b"
    rm -f "$b"

    history_prune_missing

    assert_file_contains "$(history_file)" "$a" "la voce viva resta"
    assert_file_not_contains "$(history_file)" "due.png" "la voce morta è rimossa"
}

# --- Sorgente ---

test_source_returns_path() {
    setup_history
    local a
    a=$(make_image uno.png)
    history_append "$a"

    assert_equals "$a" "$(source_from_history 1)" "riconsegna il percorso"
}

test_source_reports_deleted_file() {
    setup_history
    local a output status=0
    a=$(make_image uno.png)
    history_append "$a"
    rm -f "$a"

    output=$(source_from_history 1) || status=$?
    assert_exit_code "1" "$status" "errore riportato"
    assert_contains "$output" "non esiste più" "spiega perché"
}

test_source_reports_missing_entry() {
    setup_history
    local output status=0
    output=$(source_from_history 5) || status=$?
    assert_exit_code "1" "$status" "errore riportato"
    assert_contains "$output" "Nessuna immagine" "distingue dal file cancellato"
}

run_test "Il più recente è in cima" test_most_recent_is_first
run_test "Indice predefinito" test_default_index_is_one
run_test "Ripetizione spostata, non aggiunta" test_duplicate_is_moved_not_added
run_test "Limite di dimensione applicato" test_size_limit_is_enforced
run_test "Posizione inesistente" test_missing_entry_reports_one
run_test "Storico vuoto" test_empty_history_reports_one
run_test "File cancellato segnalato a parte" test_deleted_file_reports_two
run_test "Indice non valido" test_invalid_index_rejected
run_test "Potatura rimuove solo i mancanti" test_prune_removes_only_missing
run_test "Sorgente restituisce il percorso" test_source_returns_path
run_test "Sorgente segnala il file cancellato" test_source_reports_deleted_file
run_test "Sorgente segnala la voce assente" test_source_reports_missing_entry

print_summary "test_lib_history.sh"
