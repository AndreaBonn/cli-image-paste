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
    # Un solo pattern per tutte le estensioni prodotte: la pipeline ne
    # aggiunge di nuove (raw intermedi, formati convertiti) e un elenco
    # esplicito resterebbe indietro in silenzio.
    find "$dir" -maxdepth 1 -name 'paste_image_*' -type f \
        -mtime +"$CLEANUP_DAYS" -delete 2>/dev/null || true
}

# --- Acquisizione dell'immagine ---

# Solo la lettura degli appunti è indispensabile: il backend di consegna
# viene scelto fra quelli disponibili, quindi l'assenza di xdotool non è
# più un errore fatale.
require_clipboard_backend() {
    local message

    if _clipboard_tool >/dev/null 2>&1; then
        return 0
    fi

    if [ "$(session_type)" = "wayland" ]; then
        message="Errore: 'wl-paste' non è installato. Installa con: sudo apt install wl-clipboard"
    else
        message="Errore: 'xclip' non è installato. Installa con: sudo apt install xclip"
    fi

    # Stesso testo nella notifica e su stderr: chi lancia il comando a mano
    # deve leggere quello che legge chi lo lancia dallo shortcut.
    notify "$message"
    echo "$message" >&2
    exit 1
}

# Il concetto di finestra attiva esiste solo su X11: altrove non c'è nulla
# da catturare e la consegna non ne ha bisogno.
capture_active_window() {
    if [ "$(session_type)" = "x11" ] && command -v xdotool &>/dev/null; then
        xdotool getactivewindow 2>/dev/null || true
    fi
}

# Stampa il path dell'immagine pronta alla consegna, oppure notifica il
# motivo e ritorna 1.
acquire_image() {
    local output_dir="$1"
    local targets picked action mime

    targets=$(clipboard_list_targets)
    if [ -z "$targets" ]; then
        notify "Appunti vuoti — nessuna immagine trovata"
        return 1
    fi

    if ! picked=$(clipboard_pick_target "$targets" "$PREFER_EXISTING_FILE"); then
        notify "Appunti non contengono un'immagine"
        return 1
    fi

    action="${picked%%|*}"
    mime="${picked##*|}"

    case "$action" in
        file)    _acquire_existing_file "$mime" "$output_dir" ;;
        native)  _acquire_native "$mime" "$output_dir" ;;
        convert) _acquire_converted "$mime" "$output_dir" ;;
        *)       return 1 ;;
    esac
}

# Un file già su disco non viene duplicato: il suo path è stabile e non
# scade con la pulizia automatica dei temporanei.
_acquire_existing_file() {
    local mime="$1" output_dir="$2" path

    if path=$(clipboard_existing_file "$mime"); then
        log "riferimento a file esistente: $path"
        echo "$path"
        return 0
    fi

    # Il target c'era ma non puntava a un file utilizzabile: si riprova
    # con i dati binari, se presenti.
    local targets picked
    targets=$(clipboard_list_targets)
    if picked=$(clipboard_pick_target "$targets" 0) && [ "${picked%%|*}" != "file" ]; then
        _acquire_from_action "$picked" "$output_dir"
        return
    fi

    notify "Il riferimento negli appunti non punta a un file leggibile"
    return 1
}

_acquire_from_action() {
    local picked="$1" output_dir="$2"
    local action="${picked%%|*}" mime="${picked##*|}"

    case "$action" in
        native)  _acquire_native "$mime" "$output_dir" ;;
        convert) _acquire_converted "$mime" "$output_dir" ;;
        *)       return 1 ;;
    esac
}

_acquire_native() {
    local mime="$1" output_dir="$2" ext file_path

    ext=$(clipboard_extension_for "$mime")
    file_path=$(_new_image_file "$output_dir" "$ext") || return 1

    if ! clipboard_read "$mime" "$file_path"; then
        notify "Errore nel salvataggio dell'immagine"
        rm -f "$file_path"
        return 1
    fi

    if [ ! -s "$file_path" ]; then
        notify "Immagine vuota negli appunti"
        rm -f "$file_path"
        return 1
    fi

    echo "$file_path"
}

# Formato non utilizzabile così com'è: senza il convertitore non esiste
# nessun file da consegnare, quindi qui il fallimento è della sorgente,
# non una degradazione accettabile.
_acquire_converted() {
    local mime="$1" output_dir="$2" raw png ext

    if ! transform_magick_available && [ "$mime" != "image/svg+xml" ]; then
        notify "$(transform_missing_message "$mime")"
        return 1
    fi

    ext=$(clipboard_extension_for "$mime")
    raw=$(mktemp "${output_dir}/paste_image_raw_XXXXXX.${ext}") || return 1

    if ! clipboard_read "$mime" "$raw" || [ ! -s "$raw" ]; then
        notify "Errore nella lettura dell'immagine dagli appunti"
        rm -f "$raw"
        return 1
    fi

    png=$(_new_image_file "$output_dir" "png") || { rm -f "$raw"; return 1; }

    if ! transform_to_png "$raw" "$png" "$mime"; then
        notify "$(transform_missing_message "$mime")"
        rm -f "$raw" "$png"
        return 1
    fi

    # L'intermedio non serve oltre la conversione: lasciarlo scadere con il
    # risultato finale moltiplicherebbe le copie di contenuto sensibile.
    rm -f "$raw"
    log "convertito da $mime a png"
    echo "$png"
}

# mktemp crea il file atomicamente con permessi 0600, eliminando
# prevedibilità del nome e race condition TOCTOU.
_new_image_file() {
    local output_dir="$1" ext="$2" timestamp

    timestamp=$(date +%Y%m%d_%H%M%S)
    if ! mktemp "${output_dir}/paste_image_${timestamp}_XXXXXX.${ext}"; then
        notify "Errore nella creazione del file temporaneo"
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

    require_clipboard_backend

    local output_dir
    output_dir=$(resolve_output_dir)
    cleanup_old_files "$output_dir"

    # La finestra attiva va catturata PRIMA di qualunque altra operazione:
    # è l'unico momento in cui il terminale ha ancora il focus. Ogni step
    # che apre una finestra propria (annotazione, selezione area) rende
    # inutile una cattura successiva, che prenderebbe quella finestra.
    local active_window
    active_window=$(capture_active_window)

    local file_path
    file_path=$(acquire_image "$output_dir") || exit 1

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
