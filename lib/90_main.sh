# shellcheck shell=bash
#
# 90_main.sh — Orchestrazione
#
# Unico modulo che esegue codice al livello superiore: tutti gli altri
# definiscono soltanto funzioni. Le decisioni di uscita vivono qui.
#

# --- Verifica dipendenze ---

check_dependency() {
    if ! command -v "$1" &>/dev/null; then
        notify "Errore: '$1' non è installato. Installa con: sudo apt install $2"
        echo "Errore: '$1' non è installato." >&2
        echo "Installa con: sudo apt install $2" >&2
        exit 1
    fi
}

# --- Directory di output ---

resolve_output_dir() {
    local dir="${PASTE_IMAGE_OUTPUT_DIR:-/tmp}"

    # Fallback se la directory scelta non è scrivibile
    if [ ! -w "$dir" ]; then
        dir="$HOME/Pictures/paste_image"
        mkdir -p "$dir"
    fi

    echo "$dir"
}

# Rimuove le immagini paste_image_* più vecchie di CLEANUP_DAYS per evitare accumulo
cleanup_old_files() {
    local dir="$1"
    find "$dir" -maxdepth 1 -name 'paste_image_*.png' -mtime +"$CLEANUP_DAYS" -delete 2>/dev/null || true
    find "$dir" -maxdepth 1 -name 'paste_image_*.jpg' -mtime +"$CLEANUP_DAYS" -delete 2>/dev/null || true
}

# --- Rilevamento immagine negli appunti ---

# Stampa "mime|estensione" per il primo formato supportato trovato.
# Ritorna 1 se gli appunti non contengono un'immagine gestibile.
detect_clipboard_image() {
    local targets="$1"

    if echo "$targets" | grep -q "image/png"; then
        echo "image/png|png"
    elif echo "$targets" | grep -q "image/jpeg"; then
        echo "image/jpeg|jpg"
    else
        return 1
    fi
}

# --- Orchestrazione ---

main() {
    if [[ "${1:-}" == "--version" || "${1:-}" == "-v" ]]; then
        echo "paste-image $VERSION"
        exit 0
    fi

    store_init

    check_dependency xclip xclip
    check_dependency xdotool xdotool

    local output_dir
    output_dir=$(resolve_output_dir)
    cleanup_old_files "$output_dir"

    # La finestra attiva va catturata PRIMA di qualunque altra operazione:
    # è l'unico momento in cui il terminale ha ancora il focus. Ogni step
    # che apre una finestra propria (annotazione, selezione area) rende
    # inutile una cattura successiva, che prenderebbe quella finestra.
    local active_window
    active_window=$(xdotool getactivewindow 2>/dev/null || true)

    local targets
    targets=$(xclip -selection clipboard -t TARGETS -o 2>/dev/null || true)

    if [ -z "$targets" ]; then
        notify "Appunti vuoti — nessuna immagine trovata"
        exit 1
    fi

    local detected mime ext
    if ! detected=$(detect_clipboard_image "$targets"); then
        notify "Appunti non contengono un'immagine"
        exit 1
    fi
    mime="${detected%%|*}"
    ext="${detected##*|}"

    local timestamp file_path
    timestamp=$(date +%Y%m%d_%H%M%S)

    # mktemp crea il file atomicamente con permessi 0600,
    # eliminando prevedibilità del nome e race condition TOCTOU
    file_path=$(mktemp "${output_dir}/paste_image_${timestamp}_XXXXXX.${ext}") || {
        notify "Errore nella creazione del file temporaneo"
        exit 1
    }

    if ! xclip -selection clipboard -t "$mime" -o > "$file_path" 2>/dev/null; then
        notify "Errore nel salvataggio dell'immagine"
        rm -f "$file_path"
        exit 1
    fi

    if [ ! -s "$file_path" ]; then
        notify "Immagine vuota negli appunti"
        rm -f "$file_path"
        exit 1
    fi

    deliver_path "$file_path" "$active_window"

    notify "Immagine incollata: $(basename "$file_path")"
}

# --- Consegna ---

deliver_path() {
    local file_path="$1"
    local active_window="$2"

    if [ -n "$active_window" ]; then
        xdotool windowfocus --sync "$active_window" 2>/dev/null || true
        sleep "$TYPING_DELAY"
        xdotool type --clearmodifiers --window "$active_window" "$file_path"
    else
        # Fallback: digita senza specificare la finestra
        sleep "$TYPING_DELAY"
        xdotool type --clearmodifiers "$file_path"
    fi
}

main "$@"
