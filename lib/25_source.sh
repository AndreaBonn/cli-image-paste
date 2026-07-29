# shellcheck shell=bash
#
# 25_source.sh — Stadio SOURCE: da dove arriva l'immagine
#
# Le sorgenti sono alternative fra loro: gli appunti, un file già su disco
# indicato dal file manager, e in futuro uno screenshot o una voce dello
# storico. Ogni funzione stampa il path del file pronto, oppure notifica il
# motivo e ritorna non-zero.
#

# Solo la lettura degli appunti è indispensabile: il backend di consegna
# viene scelto fra quelli disponibili, quindi l'assenza di xdotool non è
# più un errore fatale.
#
# Ritorna 0 se un backend esiste. Altrimenti stampa il messaggio da mostrare
# e ritorna 1: la decisione di terminare appartiene all'orchestratore.
source_clipboard_backend_check() {
    if _clipboard_tool >/dev/null 2>&1; then
        return 0
    fi

    if [ "$(session_type)" = "wayland" ]; then
        echo "Errore: 'wl-paste' non è installato. Installa con: sudo apt install wl-clipboard"
    else
        echo "Errore: 'xclip' non è installato. Installa con: sudo apt install xclip"
    fi
    return 1
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

