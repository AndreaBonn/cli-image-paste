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

# --- Orchestrazione ---

main() {
    case "${1:-}" in
        --version|-v)
            echo "paste-image $VERSION"
            exit 0
            ;;
        --print-shortcut)
            # Utile su sway, i3 e Hyprland, dove non esiste un registro da
            # scrivere e la scorciatoia va nel file dell'utente.
            shortcut_print_instructions "${2:-}" "${3:-<Control><Shift>v}" \
                "$HOME/.local/bin/paste-image"
            exit $?
            ;;
        --reset-capabilities)
            capabilities_reset
            echo "Cache delle capacità azzerata: i backend verranno riprovati."
            exit 0
            ;;
    esac

    config_init
    store_init
    flush_config_warnings

    local backend_error
    if ! backend_error=$(source_clipboard_backend_check); then
        # Stesso testo nella notifica e su stderr: chi lancia il comando a
        # mano deve leggere quello che legge chi usa la scorciatoia.
        notify "$backend_error"
        echo "$backend_error" >&2
        exit 1
    fi

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

    # Gli intermedi della pipeline non sopravvivono all'uscita, nemmeno se
    # qualcosa fallisce a metà: la pipeline moltiplica le copie di contenuto
    # che può essere sensibile.
    trap transform_cleanup_temps EXIT

    file_path=$(transform_run "$file_path" "$output_dir")

    local hint
    hint=$(deliver_path "$file_path" "$active_window") || exit 1

    if [ -n "$hint" ]; then
        notify "$hint"
    else
        notify "Immagine incollata: $(basename "$file_path")"
    fi
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

    # L'hint viene stampato, non notificato: l'orchestratore lo unisce al
    # messaggio finale. Due notifiche consecutive per una sola azione sono
    # rumore, e la seconda copre la prima prima che si riesca a leggerla.
    delivery_hint "$backend"
    return 0
}

main "$@"
