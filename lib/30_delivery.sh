# shellcheck shell=bash
#
# 30_delivery.sh — Consegna del path al terminale
#
# Porta separata da quella di lettura degli appunti: sono assi ortogonali.
# Su GNOME Wayland leggere gli appunti funziona benissimo, è solo la
# consegna a non essere ottenibile.
#
# Il concetto di "finestra attiva" esiste solo su X11 e solo per la
# consegna via xdotool: resta privato di quella implementazione, altrimenti
# ogni backend Wayland avrebbe uno stub inutile.
#

# --- Validazione di ciò che viene digitato ---
#
# Tutto ciò che finisce digitato è input di shell. Verificato empiricamente:
# `xdotool type` sintetizza il keysym Return per un CR e Linefeed per un LF,
# quindi un carattere di controllo dentro un path equivale a premere Invio
# in un prompt idle, che è esattamente lo scenario d'uso del tool.
#
# Gli override bidirezionali Unicode non eseguono nulla ma mentono sulla
# resa visiva: l'utente legge un nome innocuo e ne conferma un altro.
delivery_path_is_safe() {
    local path="$1"

    [ -n "$path" ] || return 1
    [[ "$path" == /* ]] || return 1

    text_has_unsafe_chars "$path" && return 1

    return 0
}

# --- Selezione del backend ---

# Stampa il primo backend utilizzabile della catena, tenendo conto dei
# tool effettivamente installati, della scelta esplicita dell'utente e dei
# fallimenti già appresi.
delivery_select_backend() {
    local session="$1" desktop="$2" forced="${3:-}"
    local chain backend

    # Una scelta esplicita vale anche se il tool sembra assente: l'utente
    # può saperne più di noi sul proprio sistema.
    if [ -n "$forced" ]; then
        echo "$forced"
        return 0
    fi

    chain=$(delivery_chain_for "$session" "$desktop")

    for backend in $chain; do
        _delivery_backend_usable "$backend" || continue
        echo "$backend"
        return 0
    done

    # La consegna via appunti è l'ultima rete: non richiede di simulare
    # tastiera, quindi è l'unica che non può essere negata dal compositore.
    echo "clipboard"
}

_delivery_backend_usable() {
    local backend="$1"

    capability_failed "$backend" && return 1

    case "$backend" in
        xdotool)   command -v xdotool &>/dev/null ;;
        wtype)     command -v wtype &>/dev/null ;;
        ydotool)   command -v ydotool &>/dev/null && _ydotool_daemon_running ;;
        clipboard) _delivery_clipboard_tool >/dev/null ;;
        *)         return 1 ;;
    esac
}

# ydotool senza daemon in ascolto si blocca o fallisce lentamente:
# va verificato prima di sceglierlo, non dopo.
_ydotool_daemon_running() {
    local socket="${YDOTOOL_SOCKET:-/run/user/$(id -u)/.ydotool_socket}"
    [ -S "$socket" ]
}

# --- Testo da consegnare ---

# Applica il template di formato al path. La sostituzione è letterale:
# passare il template come primo argomento di printf lo renderebbe una
# format string sotto controllo esterno.
delivery_render() {
    local path="$1" template="${2:-}"

    if [ -z "$template" ]; then
        printf '%s' "$path"
        return
    fi

    printf '%s' "${template//%s/$path}"
}

# --- Implementazioni ---

# X11: il focus va restituito alla finestra catturata prima di digitare.
# Dopo uno step interattivo il ritardo non è stimabile, quindi si attende
# la condizione invece di dormire un tempo fisso: uno sleep costante passa
# in sviluppo e fallisce su macchina carica, digitando altrove.
_delivery_xdotool_send() {
    local text="$1" window="${2:-}"

    if [ -z "$window" ]; then
        sleep "$TYPING_DELAY"
        xdotool type --clearmodifiers "$text"
        return
    fi

    xdotool windowfocus --sync "$window" 2>/dev/null || true
    _wait_for_focus "$window"
    xdotool type --clearmodifiers --window "$window" "$text"
}

_wait_for_focus() {
    local window="$1" waited=0 current
    local step_ms=20
    local timeout_ms=2000

    while [ "$waited" -lt "$timeout_ms" ]; do
        current=$(xdotool getactivewindow 2>/dev/null || echo "")
        [ "$current" = "$window" ] && return 0
        sleep 0.02
        waited=$((waited + step_ms))
    done

    # Il focus non è tornato: si digita comunque sulla finestra esplicita,
    # che è più sicuro che digitare su quella attiva sbagliata.
    return 1
}

_delivery_wtype_send() {
    local text="$1"
    sleep "$TYPING_DELAY"
    wtype "$text"
}

_delivery_ydotool_send() {
    local text="$1"
    sleep "$TYPING_DELAY"
    ydotool type "$text"
}

# Nessuna simulazione di tastiera: il testo finisce negli appunti e lo
# incolla l'utente. È l'unica modalità che nessun compositore può negare.
_delivery_clipboard_send() {
    local text="$1" tool
    tool=$(_delivery_clipboard_tool) || return 1

    case "$tool" in
        wl-copy)
            printf '%s' "$text" | wl-copy
            ;;
        xclip)
            # xclip mantiene la selezione con un processo che sopravvive al
            # chiamante: verificato, il contenuto resta leggibile dopo
            # l'uscita dello script.
            printf '%s' "$text" | xclip -selection clipboard -i
            ;;
    esac
}

_delivery_clipboard_tool() {
    if [ "$(session_type)" = "wayland" ] && command -v wl-copy &>/dev/null; then
        echo "wl-copy"
    elif command -v xclip &>/dev/null; then
        echo "xclip"
    else
        return 1
    fi
}

# --- Messaggio per l'utente ---
#
# La modalità possiede il proprio testo: senza questo, un condizionale
# sulla modalità ricomparirebbe dentro la funzione di notifica.
delivery_hint() {
    case "$1" in
        clipboard)
            echo "Path negli appunti: premi Ctrl+V per incollarlo. Il contenuto precedente degli appunti è stato sostituito."
            ;;
        *)
            echo ""
            ;;
    esac
}

# --- Punto di ingresso ---

# Consegna il testo con il backend indicato. Ritorna non-zero se il
# backend fallisce, così l'orchestratore può registrare il negativo.
delivery_send() {
    local backend="$1" text="$2" window="${3:-}"

    case "$backend" in
        xdotool)   _delivery_xdotool_send "$text" "$window" ;;
        wtype)     _delivery_wtype_send "$text" ;;
        ydotool)   _delivery_ydotool_send "$text" ;;
        clipboard) _delivery_clipboard_send "$text" ;;
        *)         return 1 ;;
    esac
}
