# shellcheck shell=bash
#
# 90_main.sh — Orchestrazione
#
# Unico modulo che esegue codice al livello superiore: tutti gli altri
# definiscono soltanto funzioni. Le decisioni di uscita vivono qui.
#

# --- Configurazione ---

# Il parser accumula le anomalie perché gira prima che il log esista.
# Vanno riversate appena possibile: una chiave scartata in silenzio è
# indistinguibile da una applicata.
flush_config_warnings() {
    local warning
    for warning in ${CONFIG_WARNINGS+"${CONFIG_WARNINGS[@]}"}; do
        log "config: $warning"
    done
}

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
    # shellcheck disable=SC2153 # Assegnata da config_defaults in 15_config.sh
    local dir="$OUTPUT_DIR"

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

    config_init
    store_init
    flush_config_warnings

    # Solo la lettura degli appunti è indispensabile. Il backend di
    # consegna viene scelto fra quelli disponibili: l'assenza di xdotool
    # non è più un errore fatale, si ripiega sugli appunti.
    check_dependency xclip xclip

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

    deliver_path "$file_path" "$active_window" || exit 1

    notify "Immagine incollata: $(basename "$file_path")"
}

# --- Consegna ---

deliver_path() {
    local file_path="$1"
    local active_window="$2"
    local backend text hint

    # Nulla raggiunge il terminale senza essere passato di qui: ciò che
    # viene digitato è input di shell, e un carattere di controllo nel
    # path equivale a premere Invio nel prompt in attesa.
    if ! delivery_path_is_safe "$file_path"; then
        notify "Path non sicuro, consegna annullata"
        return 1
    fi

    backend=$(delivery_select_backend "$(session_type)" "$(session_desktop)" "$TYPING_BACKEND")
    text=$(delivery_render "$file_path" "$FORMAT_TEMPLATE")

    if ! delivery_send "$backend" "$text" "$active_window"; then
        # Il compositore non si può interrogare sulle sue capacità: lo si
        # scopre fallendo. Registrato il negativo, si riprova con gli
        # appunti, che nessun compositore può negare.
        capability_mark_failed "$backend"
        log "backend '$backend' fallito, ripiego sugli appunti"
        backend="clipboard"
        if ! delivery_send "$backend" "$text"; then
            notify "Impossibile consegnare il path al terminale"
            return 1
        fi
    fi

    hint=$(delivery_hint "$backend")
    [ -n "$hint" ] && notify "$hint"
    return 0
}

main "$@"
