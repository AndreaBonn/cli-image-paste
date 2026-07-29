#!/usr/bin/env bash
#
# test_no_side_effects.sh — I moduli di lib/ definiscono solo funzioni
#
# Regola di modulo: nessun file di lib/, tranne l'header e l'orchestratore,
# può eseguire codice al momento del source. È la precondizione perché i test
# unitari possano sorgiare un modulo per esercitarne le funzioni, ed è anche
# ciò che rende sicura la concatenazione fatta da scripts/build.sh.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

# L'header porta shebang e set -euo pipefail, l'orchestratore chiama main:
# entrambi sono per definizione fuori dalla regola.
EXEMPT_MODULES=("00_header.sh" "90_main.sh")

is_exempt() {
    local name="$1" exempt
    for exempt in "${EXEMPT_MODULES[@]}"; do
        [ "$name" = "$exempt" ] && return 0
    done
    return 1
}

# --- Test: sorgiare un modulo non crea file né scrive nulla ---
test_source_creates_nothing() {
    local module name workdir before after
    workdir="$TEST_TMPDIR/sourcing"
    mkdir -p "$workdir"

    for module in "$PROJECT_DIR"/lib/*.sh; do
        [ -f "$module" ] || continue
        name=$(basename "$module")
        is_exempt "$name" && continue

        before=$(find "$workdir" -mindepth 1 | wc -l)

        # HOME dirottato: se un modulo scrivesse in ~/.local/state o simili
        # lo farebbe qui dentro, dove lo vediamo.
        (
            cd "$workdir" || exit 1
            HOME="$workdir" bash -c "source '$module'" >/dev/null 2>&1
        )

        after=$(find "$workdir" -mindepth 1 | wc -l)
        assert_equals "$before" "$after" "$name non crea file al source"
    done
}

# --- Test: sorgiare un modulo non termina la shell ---
test_source_does_not_exit() {
    local module name exit_code

    for module in "$PROJECT_DIR"/lib/*.sh; do
        [ -f "$module" ] || continue
        name=$(basename "$module")
        is_exempt "$name" && continue

        exit_code=0
        bash -c "source '$module'; exit 0" >/dev/null 2>&1 || exit_code=$?
        assert_exit_code "0" "$exit_code" "$name non esce al source"
    done
}

# --- Test: solo l'header dichiara shebang e set -euo pipefail ---
test_only_header_has_preamble() {
    local module name

    for module in "$PROJECT_DIR"/lib/*.sh; do
        [ -f "$module" ] || continue
        name=$(basename "$module")
        [ "$name" = "00_header.sh" ] && continue

        if head -1 "$module" | grep -q '^#!'; then
            _test_fail "$name contiene uno shebang"
        fi
        if grep -qE '^set -[eu]' "$module"; then
            _test_fail "$name contiene 'set -e/-u'"
        fi
    done
}

# --- Test: nessun exit fuori dall'orchestratore ---
test_no_exit_outside_main() {
    local module name

    for module in "$PROJECT_DIR"/lib/*.sh; do
        [ -f "$module" ] || continue
        name=$(basename "$module")
        is_exempt "$name" && continue

        # Cerca exit non commentati. Le funzioni ritornano exit code:
        # la decisione di uscire appartiene a 90_main.sh.
        if grep -nE '^[^#]*\bexit\b' "$module" | grep -vq 'flock'; then
            _test_fail "$name contiene un exit fuori dall'orchestratore"
        fi
    done
}

run_test "Sorgiare un modulo non crea file" test_source_creates_nothing
run_test "Sorgiare un modulo non termina la shell" test_source_does_not_exit
run_test "Solo l'header ha shebang e set -euo" test_only_header_has_preamble
run_test "Nessun exit fuori dall'orchestratore" test_no_exit_outside_main

print_summary "test_no_side_effects.sh"
