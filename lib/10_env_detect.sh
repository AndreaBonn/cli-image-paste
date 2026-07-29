# shellcheck shell=bash
#
# 10_env_detect.sh — Rilevamento della sessione grafica e del desktop
#
# Il rilevamento avviene a ogni invocazione e non viene messo in cache:
# leggere una variabile d'ambiente e chiamare `command -v` costa meno di un
# millisecondo, contro i due fork del backend appunti e il ritardo di
# stabilizzazione del focus. Non c'è nulla da risparmiare, e una cache qui
# comprerebbe solo il rischio di valori stantii al cambio di sessione.
#
# L'unico fatto che viene memorizzato è il negativo appreso: quando un
# backend di digitazione fallisce davvero, non lo si ritenta.
#

# --- Sessione ---

# Stampa "x11", "wayland" oppure "none".
# L'override serve ai test: gli ambienti target non sono riproducibili
# tutti sulla macchina di sviluppo.
session_type() {
    if [ -n "${PASTE_IMAGE_SESSION_TYPE:-}" ]; then
        echo "$PASTE_IMAGE_SESSION_TYPE"
        return
    fi

    case "${XDG_SESSION_TYPE:-}" in
        wayland) echo "wayland"; return ;;
        x11)     echo "x11"; return ;;
    esac

    # XDG_SESSION_TYPE non è garantita: fuori da un login manager può
    # mancare del tutto. I socket sono il fatto, la variabile è il racconto.
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        echo "wayland"
    elif [ -n "${DISPLAY:-}" ]; then
        echo "x11"
    else
        echo "none"
    fi
}

# Stampa il desktop normalizzato in minuscolo: gnome, kde, sway, hyprland,
# i3, unity, xfce, cinnamon, altro. XDG_CURRENT_DESKTOP può contenere più
# valori separati da due punti, in ordine di specificità decrescente.
session_desktop() {
    if [ -n "${PASTE_IMAGE_DESKTOP:-}" ]; then
        _normalize_desktop "$PASTE_IMAGE_DESKTOP"
        return
    fi

    local raw="${XDG_CURRENT_DESKTOP:-${XDG_SESSION_DESKTOP:-}}"
    if [ -z "$raw" ]; then
        echo "altro"
        return
    fi

    _normalize_desktop "$raw"
}

_normalize_desktop() {
    local raw="$1" first

    # "ubuntu:GNOME" -> "GNOME": il prefisso è la personalizzazione della
    # distribuzione, il suffisso è il desktop vero.
    first="${raw##*:}"
    first=$(echo "$first" | tr '[:upper:]' '[:lower:]')

    case "$first" in
        gnome*|ubuntu*|pop*)      echo "gnome" ;;
        kde|plasma*)              echo "kde" ;;
        sway)                     echo "sway" ;;
        hyprland)                 echo "hyprland" ;;
        i3)                       echo "i3" ;;
        unity)                    echo "unity" ;;
        xfce)                     echo "xfce" ;;
        x-cinnamon|cinnamon)      echo "cinnamon" ;;
        river|wayfire|labwc)      echo "wlroots" ;;
        *)                        echo "altro" ;;
    esac
}

# --- Catene di consegna ---

# Stampa la catena di backend da provare, in ordine, separati da spazio.
#
# Su GNOME Wayland la consegna via appunti è la PRIMA voce, non un ripiego:
# Mutter non implementa il protocollo virtual-keyboard che serve a wtype, e
# ydotool richiede un daemon con accesso a /dev/uinput. Un ripiego si
# scopre fallendo, e wtype fallirebbe dopo che il file è già stato creato,
# con un errore che l'utente vede come "non è successo niente".
delivery_chain_for() {
    local session="$1" desktop="$2"

    case "$session" in
        x11)
            echo "xdotool clipboard"
            ;;
        wayland)
            case "$desktop" in
                gnome|unity|cinnamon) echo "clipboard" ;;
                sway|hyprland|wlroots) echo "wtype clipboard" ;;
                *) echo "wtype clipboard" ;;
            esac
            ;;
        *)
            echo "clipboard"
            ;;
    esac
}

# --- Negativo appreso ---
#
# Non esiste modo di interrogare un compositore per sapere se implementa
# virtual-keyboard: l'unico modo di scoprirlo è provare. Quando la prova
# fallisce, il fatto viene registrato e non si ritenta.
#
# La chiave contiene sessione, desktop e versione: cambiare sessione cambia
# la chiave, quindi non serve un tempo di scadenza. Il tempo non è la
# variabile giusta, lo è l'identità del compositore.

capabilities_file() {
    echo "${XDG_STATE_HOME:-$HOME/.local/state}/paste-image/capabilities"
}

capability_key() {
    echo "$(session_type):$(session_desktop):$VERSION"
}

capability_failed() {
    local backend="$1" file
    file=$(capabilities_file)
    [ -f "$file" ] || return 1
    grep -qxF "$(capability_key)|$backend" "$file"
}

capability_mark_failed() {
    local backend="$1" file
    file=$(capabilities_file)
    mkdir -p "$(dirname "$file")"
    capability_failed "$backend" && return 0
    echo "$(capability_key)|$backend" >> "$file"
}

capabilities_reset() {
    rm -f "$(capabilities_file)"
}
