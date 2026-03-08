#!/usr/bin/env bash
#
# run_tests.sh — Runner che scopre ed esegue tutte le test suite
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0
FAILED_SUITE_NAMES=()
SHELLCHECK_FAILED=0

echo "==============================="
echo "  paste-images-cli test runner"
echo "==============================="
echo ""

# ── ShellCheck: analisi statica prima dei test funzionali ──
echo "--- ShellCheck: analisi statica ---"
echo ""

if command -v shellcheck &>/dev/null; then
    SHELLCHECK_TARGETS=(
        "$PROJECT_DIR/paste-image"
        "$PROJECT_DIR/install.sh"
        "$PROJECT_DIR/uninstall.sh"
    )
    # Aggiungi anche i file di test e il runner stesso
    for f in "$SCRIPT_DIR"/*.sh; do
        [ -f "$f" ] && SHELLCHECK_TARGETS+=("$f")
    done

    SHELLCHECK_OK=0
    SHELLCHECK_FAIL=0
    for target in "${SHELLCHECK_TARGETS[@]}"; do
        rel_path="${target#"$PROJECT_DIR"/}"
        if shellcheck "$target" 2>&1; then
            SHELLCHECK_OK=$((SHELLCHECK_OK + 1))
        else
            SHELLCHECK_FAIL=$((SHELLCHECK_FAIL + 1))
            echo "  FAIL: $rel_path"
        fi
    done

    echo ""
    echo "ShellCheck: $SHELLCHECK_OK OK, $SHELLCHECK_FAIL errori"
    if [ "$SHELLCHECK_FAIL" -gt 0 ]; then
        SHELLCHECK_FAILED=1
        echo "ATTENZIONE: ShellCheck ha trovato problemi. Correggerli prima del commit."
    fi
    echo ""
else
    echo "ATTENZIONE: shellcheck non installato — analisi statica saltata."
    echo "Installa con: sudo apt install shellcheck"
    echo ""
fi

# ── Test funzionali ──
echo "--- Test funzionali ---"
echo ""

# Scopri ed esegui tutti i test_*.sh (escluso test_framework.sh)
for test_file in "$SCRIPT_DIR"/test_*.sh; do
    [ -f "$test_file" ] || continue
    basename_file=$(basename "$test_file")

    # Salta il framework
    if [ "$basename_file" = "test_framework.sh" ]; then
        continue
    fi

    TOTAL_SUITES=$((TOTAL_SUITES + 1))

    if bash "$test_file"; then
        PASSED_SUITES=$((PASSED_SUITES + 1))
    else
        FAILED_SUITES=$((FAILED_SUITES + 1))
        FAILED_SUITE_NAMES+=("$basename_file")
    fi
done

# Riepilogo finale
echo "==============================="
echo "  RIEPILOGO FINALE"
echo "==============================="
echo ""
echo "Suite eseguite: $TOTAL_SUITES"
echo "Passate:        $PASSED_SUITES"
echo "Fallite:        $FAILED_SUITES"

if [ "$SHELLCHECK_FAILED" -gt 0 ]; then
    echo "ShellCheck:     FALLITO"
else
    echo "ShellCheck:     OK"
fi

if [ ${#FAILED_SUITE_NAMES[@]} -gt 0 ] || [ "$SHELLCHECK_FAILED" -gt 0 ]; then
    if [ ${#FAILED_SUITE_NAMES[@]} -gt 0 ]; then
        echo ""
        echo "Suite fallite:"
        for name in "${FAILED_SUITE_NAMES[@]}"; do
            echo "  - $name"
        done
    fi
    echo ""
    exit 1
else
    echo ""
    echo "Tutti i test passati!"
    echo ""
    exit 0
fi
