# shellcheck shell=bash
#
# 80_usage.sh — Aiuto e diagnostica
#
# La diagnostica esiste perché il comportamento dipende dall'ambiente in modi
# che l'utente non può vedere: quale backend è stato scelto, perché, e cosa è
# disponibile. Una segnalazione che arriva con queste informazioni dentro si
# risolve, una senza costa tre scambi di messaggi.
#

print_usage() {
    cat <<'USAGE'
paste-image — consegna un'immagine al terminale attivo come percorso di file

Uso:
  paste-image                     Legge l'immagine dagli appunti
  paste-image --screenshot        Cattura un'area dello schermo
  paste-image --last [N]          Riconsegna l'ennesima immagine recente
  paste-image --annotate          Apre l'annotatore prima di consegnare

Informazioni:
  --version, -v                   Mostra la versione
  --help, -h                      Mostra questo aiuto
  --doctor                        Mostra ambiente rilevato e strumenti
  --print-shortcut WM             Stampa la riga di config per sway, i3, hyprland
  --reset-capabilities            Riprova i backend segnati come non funzionanti

Le opzioni si combinano: --screenshot --annotate cattura un'area e la apre
nell'annotatore prima di consegnare il percorso.

Configurazione: ~/.config/paste-image/config
Ogni chiave accetta un override d'ambiente PASTE_IMAGE_<CHIAVE>.
USAGE
}

_report_tool() {
    local label="$1" tool="$2" path
    path=$(command -v "$tool" 2>/dev/null) || path="assente"
    printf '  %-22s %s\n' "$label" "$path"
}

print_diagnostics() {
    local session desktop chain backend

    config_init
    session=$(session_type)
    desktop=$(session_desktop)
    chain=$(delivery_chain_for "$session" "$desktop")
    backend=$(delivery_select_backend "$session" "$desktop" "$TYPING_BACKEND")

    echo "paste-image $VERSION"
    echo ""
    echo "Ambiente:"
    printf '  %-22s %s\n' "tipo di sessione" "$session"
    printf '  %-22s %s\n' "desktop" "$desktop"
    printf '  %-22s %s\n' "XDG_SESSION_TYPE" "${XDG_SESSION_TYPE:-non impostata}"
    printf '  %-22s %s\n' "XDG_CURRENT_DESKTOP" "${XDG_CURRENT_DESKTOP:-non impostata}"
    echo ""
    echo "Consegna:"
    printf '  %-22s %s\n' "catena prevista" "$chain"
    printf '  %-22s %s\n' "backend scelto" "$backend"
    if [ -n "$TYPING_BACKEND" ]; then
        printf '  %-22s %s\n' "forzato da config" "$TYPING_BACKEND"
    fi
    echo ""
    echo "Strumenti:"
    _report_tool "appunti X11" xclip
    _report_tool "appunti Wayland" wl-paste
    _report_tool "digitazione X11" xdotool
    _report_tool "digitazione Wayland" wtype
    _report_tool "digitazione uinput" ydotool
    _report_tool "conversione" "$(transform_magick_bin 2>/dev/null || echo magick)"
    _report_tool "rasterizzatore SVG" rsvg-convert
    _report_tool "cattura schermo" "$(screenshot_tool_for "$session" "$desktop" 2>/dev/null || echo grim)"
    _report_tool "annotazione" "$(annotate_tool 2>/dev/null || echo swappy)"
    _report_tool "notifiche" notify-send
    echo ""
    echo "Percorsi:"
    printf '  %-22s %s\n' "immagini" "$OUTPUT_DIR"
    printf '  %-22s %s\n' "configurazione" "$(config_file_path)"
    printf '  %-22s %s\n' "stato e log" "${XDG_STATE_HOME:-$HOME/.local/state}/paste-image"

    # Un backend segnato come non funzionante spiega un comportamento che
    # altrimenti sembrerebbe arbitrario.
    local caps
    caps=$(capabilities_file)
    if [ -f "$caps" ]; then
        echo ""
        echo "Backend esclusi dopo un fallimento (--reset-capabilities per riprovare):"
        sed 's/^/  /' "$caps"
    fi
}
