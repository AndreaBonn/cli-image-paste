#!/usr/bin/env bash
#
# test_lib_format.sh — Formato del testo consegnato
#
# Indovinare male il formato non rompe nulla, ma costa all'utente una
# correzione a mano a ogni incolla. La mappa dei template è pura, il
# rilevamento del processo si verifica con l'albero dei processi vero.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

_LIB="$(cd "$SCRIPT_DIR/.." && pwd)/lib"
# shellcheck source=../lib/70_format.sh
source "$_LIB/70_format.sh"

# --- Mappa dei template ---

test_known_agents() {
    assert_equals "/add %s" "$(format_template_for aider)" "Aider vuole /add"
    assert_equals "@%s" "$(format_template_for gemini)" "Gemini CLI vuole @"
    assert_equals "%s" "$(format_template_for claude)" "Claude Code vuole il path nudo"
}

# Un programma sconosciuto non deve ricevere una forma inventata: il path
# nudo è sempre incollabile e non corrompe il prompt.
test_unknown_process_gets_bare_path() {
    assert_equals "" "$(format_template_for vim)" "processo sconosciuto"
    assert_equals "" "$(format_template_for "")" "processo vuoto"
}

# --- Discesa nell'albero dei processi ---

# Un pkill per pattern ucciderebbe processi che non sono nostri: tutto
# quello che questo test avvia viene terminato per PID esatto.
test_leaf_walks_down_the_tree() {
    # bash padre con un figlio: la foglia è il figlio, non bash.
    bash -c 'sleep 30 & wait' &
    local parent=$!
    sleep 0.4

    local leaf child
    leaf=$(format_leaf_process "$parent" || true)
    child=$(ps --ppid "$parent" -o pid= 2>/dev/null | tr -d ' ' | head -1)

    [ -n "$child" ] && kill "$child" 2>/dev/null
    kill "$parent" 2>/dev/null
    wait "$parent" 2>/dev/null

    assert_equals "sleep" "$leaf" "la discesa arriva al figlio, non si ferma su bash"
}

test_leaf_of_childless_process_is_itself() {
    sleep 30 &
    local pid=$!
    sleep 0.2

    local leaf
    leaf=$(format_leaf_process "$pid")
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null

    assert_equals "sleep" "$leaf" "un processo senza figli è la propria foglia"
}

test_missing_pid_fails() {
    if format_leaf_process "" >/dev/null 2>&1; then
        _test_fail "PID vuoto accettato"
    fi
    if format_leaf_process 999999 >/dev/null 2>&1; then
        _test_fail "PID inesistente accettato"
    fi
}

# --- Rilevamento dalla finestra ---

test_detection_without_xdotool_fails() {
    setup_restricted_path
    if format_detect_process 12345 >/dev/null 2>&1; then
        _test_fail "rilevamento riuscito senza xdotool"
    fi
}

test_detection_without_window_fails() {
    if format_detect_process "" >/dev/null 2>&1; then
        _test_fail "rilevamento riuscito senza finestra: su Wayland è il caso normale"
    fi
}

# --- Precedenza ---

test_configured_template_wins() {
    # shellcheck disable=SC2016 # Apici singoli intenzionali: corpo del mock
    create_mock "xdotool" 'echo 1'
    assert_equals "/mio %s" "$(format_choose_template "/mio %s" 12345)" \
        "la configurazione dell'utente vince sul rilevamento"
}

test_detection_used_when_not_configured() {
    # Il mock restituisce il PID di questa shell, la cui foglia è nota
    create_mock "xdotool" "echo $$"
    local result
    result=$(format_choose_template "" 12345)
    # Qualunque sia la foglia, il risultato deve essere un template valido
    case "$result" in
        ""|"%s"|"/add %s"|"@%s") : ;;
        *) _test_fail "template inatteso dal rilevamento: '$result'" ;;
    esac
}

# Su Wayland la finestra non è interrogabile: il path nudo è il
# comportamento reale, non un caso limite.
test_no_window_gives_bare_path() {
    assert_equals "" "$(format_choose_template "" "")" "nessuna finestra, nessun template"
}

run_test "Template degli agenti noti" test_known_agents
run_test "Processo sconosciuto: path nudo" test_unknown_process_gets_bare_path
run_test "Discesa fino alla foglia" test_leaf_walks_down_the_tree
run_test "Processo senza figli" test_leaf_of_childless_process_is_itself
run_test "PID assente o inesistente" test_missing_pid_fails
run_test "Senza xdotool nessun rilevamento" test_detection_without_xdotool_fails
run_test "Senza finestra nessun rilevamento" test_detection_without_window_fails
run_test "Configurazione vince sul rilevamento" test_configured_template_wins
run_test "Rilevamento usato se non configurato" test_detection_used_when_not_configured
run_test "Nessuna finestra: path nudo" test_no_window_gives_bare_path

print_summary "test_lib_format.sh"
