#!/usr/bin/env bash
#
# install.sh — Installazione di paste-image
#
# Installa lo script, le dipendenze e configura lo shortcut GNOME.
#

set -euo pipefail

# Risoluzione del path senza dirname: un PATH minimale non ha coreutils.
_SELF="${BASH_SOURCE[0]}"
_SELF_DIR="${_SELF%/*}"
[ "$_SELF_DIR" = "$_SELF" ] && _SELF_DIR="."
SCRIPT_DIR="$(cd "$_SELF_DIR" && pwd)"
INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="paste-image"

# I sorgenti stanno in lib/: l'eseguibile è un artefatto generato.
# Viene costruito se assente o più vecchio di un modulo, così installare
# da un checkout appena clonato funziona senza passaggi manuali.
DIST_SCRIPT="$SCRIPT_DIR/dist/$SCRIPT_NAME"

needs_build() {
    local module
    [ -f "$DIST_SCRIPT" ] || return 0
    for module in "$SCRIPT_DIR"/lib/*.sh; do
        [ -f "$module" ] || continue
        [ "$module" -nt "$DIST_SCRIPT" ] && return 0
    done
    return 1
}

if needs_build; then
    echo "Costruzione dell'eseguibile dai moduli in lib/..."
    bash "$SCRIPT_DIR/scripts/build.sh"
    echo ""
fi

# Leggi versione dall'artefatto
VERSION=$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' "$DIST_SCRIPT")
BINDING_ID="paste-image"
BINDING_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/${BINDING_ID}/"
DEFAULT_SHORTCUT="<Control><Shift>v"

echo "=== Installazione paste-image v${VERSION} ==="
echo ""

# --- 1. Verifica e installa dipendenze ---

# Rileva package manager disponibile
if command -v apt &>/dev/null; then
    PKG_MANAGER="apt"
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
elif command -v pacman &>/dev/null; then
    PKG_MANAGER="pacman"
else
    PKG_MANAGER=""
fi

# Mappa il nome del pacchetto notify-send in base alla distro
case "$PKG_MANAGER" in
    apt)    NOTIFY_PKG="libnotify-bin" ;;
    dnf)    NOTIFY_PKG="libnotify" ;;
    pacman) NOTIFY_PKG="libnotify" ;;
    *)      NOTIFY_PKG="libnotify (o equivalente)" ;;
esac

MISSING_PKGS=()

if ! command -v xclip &>/dev/null; then
    MISSING_PKGS+=("xclip")
fi

if ! command -v xdotool &>/dev/null; then
    MISSING_PKGS+=("xdotool")
fi

if ! command -v notify-send &>/dev/null; then
    MISSING_PKGS+=("$NOTIFY_PKG")
fi

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo "Dipendenze mancanti: ${MISSING_PKGS[*]}"

    if [ -z "$PKG_MANAGER" ]; then
        echo "ERRORE: Nessun package manager riconosciuto (apt, dnf, pacman)."
        echo "Installa manualmente: ${MISSING_PKGS[*]}"
        exit 1
    fi

    read -rp "Vuoi installarle con $PKG_MANAGER? [S/n] " REPLY
    REPLY=${REPLY:-S}
    if [[ "$REPLY" =~ ^[SsYy]$ ]]; then
        case "$PKG_MANAGER" in
            apt)
                sudo apt update -qq
                sudo apt install -y "${MISSING_PKGS[@]}"
                ;;
            dnf)
                sudo dnf install -y "${MISSING_PKGS[@]}"
                ;;
            pacman)
                sudo pacman -S --noconfirm "${MISSING_PKGS[@]}"
                ;;
        esac
        echo "Dipendenze installate."
    else
        echo "Installazione annullata. Installa manualmente: ${MISSING_PKGS[*]}"
        exit 1
    fi
fi

echo "Dipendenze: OK"

# --- 2. Copia script in ~/.local/bin ---

# La migrazione legge lo script v1 ancora installato: va fatta PRIMA di
# sovrascriverlo, altrimenti i valori personalizzati sono già persi.
bash "$SCRIPT_DIR/scripts/migrate-config.sh" "$INSTALL_DIR/$SCRIPT_NAME"

mkdir -p "$INSTALL_DIR"
cp "$DIST_SCRIPT" "$INSTALL_DIR/$SCRIPT_NAME"
chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
echo "Script copiato in: $INSTALL_DIR/$SCRIPT_NAME"

# --- 3. Verifica PATH ---

add_to_path_if_needed() {
    local rc_file="$1"
    if [ -f "$rc_file" ]; then
        # shellcheck disable=SC2016 # Single quotes intenzionali: scriviamo il letterale $HOME/$PATH nel file
        if ! grep -qF 'export PATH="$HOME/.local/bin:$PATH"' "$rc_file" 2>/dev/null; then
            {
                echo '# Aggiunto da paste-image installer'
                echo 'export PATH="$HOME/.local/bin:$PATH"'
            } >> "$rc_file"
            echo "PATH aggiunto a: $rc_file"
        fi
    fi
}

if ! echo "$PATH" | tr ':' '\n' | grep -q "$HOME/.local/bin"; then
    add_to_path_if_needed "$HOME/.bashrc"
    add_to_path_if_needed "$HOME/.zshrc"
    export PATH="$HOME/.local/bin:$PATH"
    echo "NOTA: Riavvia il terminale o esegui 'source ~/.bashrc' per aggiornare il PATH."
else
    echo "PATH: OK"
fi

# --- 4. Configura shortcut GNOME ---

echo ""
echo "--- Configurazione shortcut GNOME ---"

# Validazione formato shortcut GTK
# Formato valido: uno o più <Modifier> seguiti da un nome tasto
# Es: <Control><Shift>v, <Super>Print, <Alt>F1, <Control>KP_Enter
validate_shortcut() {
    [[ "$1" =~ ^\<[A-Za-z]+\>(\<[A-Za-z]+\>)*[a-zA-Z0-9_]+$ ]]
}

# Chiedi shortcut all'utente (con validazione)
while true; do
    read -rp "Shortcut da tastiera (default: $DEFAULT_SHORTCUT): " USER_SHORTCUT
    SHORTCUT="${USER_SHORTCUT:-$DEFAULT_SHORTCUT}"
    if validate_shortcut "$SHORTCUT"; then
        break
    fi
    echo "ERRORE: formato shortcut non valido. Usa il formato GTK, es: <Control><Alt>v"
done

# Leggi keybindings esistenti
SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
CURRENT_BINDINGS=$(gsettings get "$SCHEMA" custom-keybindings 2>/dev/null || echo "@as []")

# Verifica conflitti: controlla se lo shortcut è già usato da un altro binding
if [ "$CURRENT_BINDINGS" != "@as []" ]; then
    # Estrai i path dei binding esistenti
    EXISTING_PATHS=$(echo "$CURRENT_BINDINGS" | tr -d "[]'" | tr ',' '\n' | sed 's/^ *//')
    for EXISTING_PATH in $EXISTING_PATHS; do
        if [ -z "$EXISTING_PATH" ]; then
            continue
        fi
        EXISTING_BINDING=$(gsettings get "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${EXISTING_PATH}" binding 2>/dev/null || echo "")
        EXISTING_BINDING=$(echo "$EXISTING_BINDING" | tr -d "'")
        EXISTING_NAME=$(gsettings get "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${EXISTING_PATH}" name 2>/dev/null || echo "")
        EXISTING_NAME=$(echo "$EXISTING_NAME" | tr -d "'")

        if [ "$EXISTING_BINDING" = "$SHORTCUT" ] && [ "$EXISTING_PATH" != "$BINDING_PATH" ]; then
            echo "ATTENZIONE: Lo shortcut '$SHORTCUT' è già assegnato a '$EXISTING_NAME'."
            read -rp "Vuoi usarlo comunque? [s/N] " CONFIRM
            CONFIRM=${CONFIRM:-N}
            if [[ ! "$CONFIRM" =~ ^[SsYy]$ ]]; then
                while true; do
                    read -rp "Inserisci un altro shortcut (formato GTK, es. <Control><Alt>v): " SHORTCUT
                    if [ -z "$SHORTCUT" ]; then
                        echo "Nessuno shortcut configurato. Puoi farlo manualmente dopo."
                        break
                    fi
                    if validate_shortcut "$SHORTCUT"; then
                        break
                    fi
                    echo "ERRORE: formato shortcut non valido. Usa il formato GTK, es: <Control><Alt>v"
                done
            fi
            break
        fi
    done
fi

if [ -n "$SHORTCUT" ]; then
    # Configura il keybinding
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${BINDING_PATH}" name "Paste Image"
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${BINDING_PATH}" command "$INSTALL_DIR/$SCRIPT_NAME"
    gsettings set "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${BINDING_PATH}" binding "$SHORTCUT"

    # Aggiungi all'array dei custom-keybindings (manipolazione strutturata con Python)
    NEW_BINDINGS=$(python3 -c "
import sys, ast
current, new_path = sys.argv[1], sys.argv[2]
arr = [] if current == '@as []' else ast.literal_eval(current)
if new_path not in arr:
    arr.append(new_path)
print(str(arr) if arr else '@as []')
" "$CURRENT_BINDINGS" "$BINDING_PATH")

    gsettings set "$SCHEMA" custom-keybindings "$NEW_BINDINGS"

    # Validazione post-modifica: verifica che l'array sia ancora valido
    VERIFY_BINDINGS=$(gsettings get "$SCHEMA" custom-keybindings 2>/dev/null || echo "")
    if ! python3 -c "
import sys, ast
val = sys.argv[1]
if val != '@as []': ast.literal_eval(val)
" "$VERIFY_BINDINGS" 2>/dev/null; then
        echo "ERRORE: l'array custom-keybindings risulta malformato dopo la modifica."
        echo "Ripristino il valore precedente..."
        gsettings set "$SCHEMA" custom-keybindings "$CURRENT_BINDINGS"
    else
        echo "Shortcut configurato: $SHORTCUT → paste-image"
    fi
fi

# --- 5. Verifica gsd-media-keys (gestisce gli shortcut custom) ---

bash "$SCRIPT_DIR/scripts/check-shortcut-service.sh"

# --- 6. Riepilogo ---

echo ""
echo "=== Installazione completata ==="
echo ""
echo "  Versione: $VERSION"
echo "  Script:   $INSTALL_DIR/$SCRIPT_NAME"
if [ -n "$SHORTCUT" ]; then
    echo "  Shortcut: $SHORTCUT"
fi
echo ""
echo "Come usare:"
echo "  1. Copia un'immagine negli appunti (screenshot, browser, ecc.)"
echo "  2. Porta il focus sul terminale con il coding assistant"
echo "  3. Premi $SHORTCUT"
echo "  4. Il path dell'immagine apparirà nel terminale"
echo "  5. Premi Invio per inviare l'immagine al coding assistant"
echo ""
echo "Per disinstallare: bash uninstall.sh"
