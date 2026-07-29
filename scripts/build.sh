#!/usr/bin/env bash
#
# build.sh — Genera dist/paste-image concatenando i moduli di lib/
#
# I sorgenti stanno in lib/NN_nome.sh e vengono concatenati in ordine
# numerico. L'output e' deterministico: nessun timestamp, nessun dato
# variabile, cosi' due build consecutive producono file identici e un
# diff fra due build resta significativo.
#

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB_DIR="$PROJECT_DIR/lib"
DIST_DIR="$PROJECT_DIR/dist"
OUTPUT="$DIST_DIR/paste-image"

# Solo 00_header.sh puo' contenere shebang e set -euo pipefail.
HEADER_MODULE="00_header.sh"

if [ ! -d "$LIB_DIR" ]; then
    echo "ERRORE: directory dei moduli non trovata: $LIB_DIR" >&2
    exit 1
fi

MODULES=()
while IFS= read -r module; do
    MODULES+=("$module")
done < <(find "$LIB_DIR" -maxdepth 1 -name '[0-9][0-9]_*.sh' -type f | sort)

if [ ${#MODULES[@]} -eq 0 ]; then
    echo "ERRORE: nessun modulo trovato in $LIB_DIR" >&2
    exit 1
fi

if [ "$(basename "${MODULES[0]}")" != "$HEADER_MODULE" ]; then
    echo "ERRORE: il primo modulo deve essere $HEADER_MODULE, trovato $(basename "${MODULES[0]}")" >&2
    exit 1
fi

# --- Verifica delle regole di modulo ---
# I moduli diversi dall'header non devono avere shebang ne' 'set -e...':
# la concatenazione li renderebbe righe morte in mezzo al file.
check_module_rules() {
    local module name errors=0
    for module in "${MODULES[@]:1}"; do
        name=$(basename "$module")
        if head -1 "$module" | grep -q '^#!'; then
            echo "ERRORE: $name contiene uno shebang (ammesso solo in $HEADER_MODULE)" >&2
            errors=1
        fi
        if grep -qE '^set -[eu]' "$module"; then
            echo "ERRORE: $name contiene 'set -e/-u' (ammesso solo in $HEADER_MODULE)" >&2
            errors=1
        fi
    done
    return $errors
}

check_module_rules

mkdir -p "$DIST_DIR"

{
    head -1 "$LIB_DIR/$HEADER_MODULE"
    cat <<'BANNER'
#
# ============================================================================
# FILE GENERATO — NON MODIFICARE
#
# Questo file e' prodotto da scripts/build.sh concatenando i moduli in lib/.
# Ogni modifica va fatta nel modulo corrispondente e poi ribuildata.
# ============================================================================
BANNER
    tail -n +2 "$LIB_DIR/$HEADER_MODULE"

    for module in "${MODULES[@]:1}"; do
        printf '\n# --- modulo: %s ---\n\n' "$(basename "$module")"
        cat "$module"
    done
} > "$OUTPUT"

chmod +x "$OUTPUT"

echo "Build completata: $OUTPUT ($(wc -l < "$OUTPUT") righe, ${#MODULES[@]} moduli)"
