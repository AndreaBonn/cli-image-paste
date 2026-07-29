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
