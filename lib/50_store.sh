# shellcheck shell=bash
#
# 50_store.sh — Log, notifiche e stato su disco
#
# Nessun codice eseguito al momento del source: solo definizioni.
# L'inizializzazione avviene con store_init(), chiamata dall'orchestratore.
#

# --- Inizializzazione ---

# Prepara la directory di stato e rileva il metodo di notifica disponibile.
# Va chiamata prima di qualunque uso di log() o notify().
store_init() {
    LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/paste-image"
    LOG_FILE="$LOG_DIR/paste_image.log"

    mkdir -p "$LOG_DIR"
    chmod 700 "$LOG_DIR" 2>/dev/null || true

    NOTIFY_METHOD=$(_detect_notify_method)
}

_detect_notify_method() {
    if command -v notify-send &>/dev/null; then
        echo "notify-send"
    elif command -v zenity &>/dev/null; then
        echo "zenity"
    else
        echo "none"
    fi
}

# --- Logging ---

log() {
    # Scrittura + rotazione atomiche tramite flock (elimina race condition TOCTOU)
    (
        flock -w 2 9 || exit 0

        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"

        # Ruota il log se supera MAX_LOG_LINES
        if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt "$MAX_LOG_LINES" ]; then
            tail -n "$((MAX_LOG_LINES / 2))" "$LOG_FILE" > "${LOG_FILE}.tmp" && \
                mv "${LOG_FILE}.tmp" "$LOG_FILE"
        fi
    ) 9>"${LOG_FILE}.lock" || true
}

# --- Notifiche ---

notify() {
    local msg="$1"
    log "$msg"

    case "$NOTIFY_METHOD" in
        notify-send)
            notify-send -t "$NOTIFY_TIMEOUT" "paste-image" "$msg"
            ;;
        zenity)
            zenity --notification --text="paste-image: $msg" 2>/dev/null &
            ;;
    esac
}

# --- Storico delle immagini ---
#
# La consegna via appunti sovrascrive gli appunti stessi, quindi distrugge
# l'immagine di partenza: un secondo tentativo è impossibile. Il file resta
# su disco, e questo storico è ciò che permette di riconsegnarlo senza
# ripassare dagli appunti. Non è un extra: è la rete di sicurezza di una
# conseguenza diretta del modo in cui la consegna funziona su GNOME Wayland.

history_file() {
    echo "$LOG_DIR/history"
}

# Registra un path. Il file più recente è in cima, così --last senza
# argomenti non deve contare nulla.
history_append() {
    local path="$1" file existing
    file=$(history_file)

    (
        flock -w 2 9 || exit 0

        existing=""
        if [ -f "$file" ]; then
            # La stessa immagine consegnata due volte non deve occupare due
            # posizioni: sposterebbe in basso quelle davvero diverse.
            existing=$(grep -vxF "$path" "$file" 2>/dev/null || true)
        fi

        {
            printf '%s\n' "$path"
            [ -n "$existing" ] && printf '%s\n' "$existing"
        } | head -n "${HISTORY_SIZE:-50}" > "${file}.tmp"

        mv "${file}.tmp" "$file"
    ) 9>"${file}.lock" || true
}

# Stampa il path dell'ennesima voce, 1 essendo la più recente.
# Ritorna 1 se la voce non esiste, 2 se esiste ma il file non c'è più.
history_get() {
    local index="${1:-1}" file path
    file=$(history_file)

    [ -f "$file" ] || return 1
    [ "$index" -ge 1 ] 2>/dev/null || return 1

    path=$(sed -n "${index}p" "$file" 2>/dev/null)
    [ -n "$path" ] || return 1

    # Un'immagine può essere stata rimossa dalla pulizia automatica o
    # dall'utente: dirlo è più utile che digitare un path morto.
    [ -f "$path" ] || return 2

    echo "$path"
}

history_prune_missing() {
    local file path kept=""
    file=$(history_file)
    [ -f "$file" ] || return 0

    while IFS= read -r path; do
        [ -f "$path" ] && kept="${kept}${path}"$'\n'
    done < "$file"

    printf '%s' "$kept" > "$file"
}
