# shellcheck shell=bash
#
# paste_image_helpers.sh — Helper condivisi dalle suite su paste-image
#
# Sorgiato dalle suite, non direttamente dal runner.
#

ensure_built
# shellcheck disable=SC2034 # Usata dalle suite che sorgiano questo helper
PASTE_IMAGE_SCRIPT="$PROJECT_DIR/dist/paste-image"

# Helper: dirotta la directory di output dello script tramite override
# esplicito da ambiente. Sostituisce la vecchia copia patchata con sed, che
# accoppiava i test alla forma testuale del sorgente e si rompeva in silenzio
# a ogni refactor.
use_output_dir() {
    export PASTE_IMAGE_OUTPUT_DIR="${1:-/tmp}"
}

# Helper: setup mock base (xclip, xdotool, notify-send)
#
# Dichiara anche la sessione: questi mock descrivono un desktop X11, che è
# l'ambiente in cui la consegna passa da xdotool. Senza la dichiarazione il
# percorso esercitato sarebbe quello della macchina ospite, e su un runner
# headless la catena diventa "clipboard": i mock non verrebbero mai chiamati.
setup_base_mocks() {
    set_session_env x11 gnome
    # shellcheck disable=SC2016 # Single quotes intenzionali: corpo dello script mock
    create_mock "xdotool" 'case "$1" in getactivewindow) echo "12345";; esac'
    create_mock "notify-send" ""
}

# Helper: mock xclip con TARGETS e dati immagine personalizzabili
# Nota: usa ${2-default} (senza :) per distinguere "" da "non passato"
setup_xclip_mock() {
    local targets="$1"
    local image_data="${2-FAKE_IMAGE_DATA}"
    local save_exit="${3:-0}"

    cat > "$MOCK_BIN/xclip" <<XCLIP_EOF
#!/usr/bin/env bash
echo "xclip \$*" >> "\$MOCK_CALL_LOG"

TARGET=""
for arg in "\$@"; do
    case "\$prev" in
        -t) TARGET="\$arg" ;;
    esac
    prev="\$arg"
done

if [ "\$TARGET" = "TARGETS" ]; then
    echo "$targets"
elif [ -n "\$TARGET" ]; then
    if echo "\$*" | grep -q "\-o"; then
        if [ "$save_exit" -ne 0 ]; then
            exit $save_exit
        fi
        printf '%s' "$image_data"
    fi
fi
XCLIP_EOF
    chmod +x "$MOCK_BIN/xclip"
}

# Helper: trova il primo file creato dallo script (pattern: paste_image_TIMESTAMP_RANDOM.EXT)
# Usa bash glob puro — funziona anche con PATH ristretto
find_created_file() {
    local dir="$1" timestamp="$2" ext="$3"
    local f
    for f in "${dir}/paste_image_${timestamp}_"*".${ext}"; do
        if [ -f "$f" ]; then
            echo "$f"
            return 0
        fi
    done
}

# Helper: conta i file creati dallo script che matchano il pattern
count_created_files() {
    local dir="$1" timestamp="$2" ext="$3"
    local count=0 f
    for f in "${dir}/paste_image_${timestamp}_"*".${ext}"; do
        [ -f "$f" ] && count=$((count + 1))
    done
    echo "$count"
}

