#!/usr/bin/env bash
#
# install-deps.sh — Verifica e installazione delle dipendenze
#
# I pacchetti necessari dipendono dalla sessione: su Wayland xclip e xdotool
# non servono a nulla, e proporli sarebbe rumore che l'utente impara a
# ignorare. Le dipendenze opzionali non vengono installate senza consenso e
# la loro assenza non blocca nulla.
#
# Invocato da install.sh. Esce con 1 se manca l'indispensabile e l'utente
# rifiuta di installarlo.
#

set -euo pipefail

_SELF="${BASH_SOURCE[0]}"
_SELF_DIR="${_SELF%/*}"
[ "$_SELF_DIR" = "$_SELF" ] && _SELF_DIR="."
MODULES="$(cd "$_SELF_DIR/../lib" && pwd)"

# shellcheck source=../lib/05_text.sh
source "$MODULES/05_text.sh"
# shellcheck source=../lib/10_env_detect.sh
source "$MODULES/10_env_detect.sh"

detect_package_manager() {
    if command -v apt &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    fi
}

# I nomi dei pacchetti divergono fra distribuzioni: sbagliarli manda
# l'utente a cercare a mano quello che l'installer diceva di saper fare.
package_name_for() {
    local logical="$1" manager="$2"

    case "$logical:$manager" in
        notify:apt)       echo "libnotify-bin" ;;
        notify:*)         echo "libnotify" ;;
        svg:apt)          echo "librsvg2-bin" ;;
        svg:*)            echo "librsvg2-tools" ;;
        clipboard-wl:*)   echo "wl-clipboard" ;;
        clipboard-x11:*)  echo "xclip" ;;
        typing-x11:*)     echo "xdotool" ;;
        typing-wl:*)      echo "wtype" ;;
        magick:*)         echo "imagemagick" ;;
        *)                echo "$logical" ;;
    esac
}

install_packages() {
    local manager="$1"
    shift

    case "$manager" in
        apt)
            sudo apt update -qq
            sudo apt install -y "$@"
            ;;
        dnf)    sudo dnf install -y "$@" ;;
        pacman) sudo pacman -S --noconfirm "$@" ;;
        *)      return 1 ;;
    esac
}

main() {
    local manager session missing=() optional=()
    manager=$(detect_package_manager)
    session=$(session_type)

    # Indispensabile: leggere gli appunti. Senza questo il tool non ha nulla
    # su cui lavorare.
    if [ "$session" = "wayland" ]; then
        command -v wl-paste &>/dev/null || missing+=("$(package_name_for clipboard-wl "$manager")")
        command -v wtype &>/dev/null || optional+=("$(package_name_for typing-wl "$manager")")
    else
        command -v xclip &>/dev/null || missing+=("$(package_name_for clipboard-x11 "$manager")")
        command -v xdotool &>/dev/null || optional+=("$(package_name_for typing-x11 "$manager")")
    fi

    command -v notify-send &>/dev/null || optional+=("$(package_name_for notify "$manager")")
    command -v magick &>/dev/null || command -v convert &>/dev/null || \
        optional+=("$(package_name_for magick "$manager")")

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Dipendenze indispensabili mancanti: ${missing[*]}"

        if [ -z "$manager" ]; then
            echo "ERRORE: nessun package manager riconosciuto (apt, dnf, pacman)."
            echo "Installa manualmente: ${missing[*]}"
            exit 1
        fi

        read -rp "Vuoi installarle con $manager? [S/n] " reply
        reply=${reply:-S}
        if [[ "$reply" =~ ^[SsYy]$ ]]; then
            install_packages "$manager" "${missing[@]}"
            echo "Dipendenze installate."
        else
            echo "Installazione annullata. Installa manualmente: ${missing[*]}"
            exit 1
        fi
    fi

    if [ ${#optional[@]} -gt 0 ]; then
        echo ""
        echo "Dipendenze opzionali non installate: ${optional[*]}"
        echo "Senza di esse alcune funzioni degradano, il tool resta usabile."

        # Il prompt compare solo con un terminale vero. Su stdin non
        # interattivo consumerebbe una riga destinata a un'altra domanda, e
        # un installer che si mangia l'input altrui è peggio di uno che non
        # chiede: chi automatizza installa le opzionali per conto proprio.
        if [ -n "$manager" ] && [ -t 0 ]; then
            read -rp "Vuoi installarle? [s/N] " reply
            reply=${reply:-N}
            if [[ "$reply" =~ ^[SsYy]$ ]]; then
                install_packages "$manager" "${optional[@]}" || \
                    echo "ATTENZIONE: installazione delle opzionali non riuscita, si prosegue."
            fi
        else
            echo "Per installarle: sudo <package-manager> install ${optional[*]}"
        fi
    fi

    echo "Dipendenze: OK"
}

main
