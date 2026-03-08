#!/usr/bin/env bash
#
# uninstall.sh — Disinstallazione di paste-image
#
# Rimuove lo script e il keybinding GNOME.
# NON rimuove le dipendenze di sistema.
#

set -euo pipefail

INSTALL_DIR="$HOME/.local/bin"
SCRIPT_NAME="paste-image"
BINDING_ID="paste-image"
BINDING_PATH="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/${BINDING_ID}/"
SCHEMA="org.gnome.settings-daemon.plugins.media-keys"

# Leggi versione dallo script installato (se ancora presente)
INSTALLED_VERSION=""
if [ -f "$INSTALL_DIR/$SCRIPT_NAME" ]; then
    INSTALLED_VERSION=$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' "$INSTALL_DIR/$SCRIPT_NAME")
fi

if [ -n "$INSTALLED_VERSION" ]; then
    echo "=== Disinstallazione paste-image v${INSTALLED_VERSION} ==="
else
    echo "=== Disinstallazione paste-image ==="
fi
echo ""

# --- 1. Rimuovi script ---

if [ -f "$INSTALL_DIR/$SCRIPT_NAME" ]; then
    rm "$INSTALL_DIR/$SCRIPT_NAME"
    echo "Script rimosso: $INSTALL_DIR/$SCRIPT_NAME"
else
    echo "Script non trovato in $INSTALL_DIR/$SCRIPT_NAME (già rimosso?)"
fi

# --- 2. Rimuovi keybinding GNOME ---

CURRENT_BINDINGS=$(gsettings get "$SCHEMA" custom-keybindings 2>/dev/null || echo "@as []")

if echo "$CURRENT_BINDINGS" | grep -q "$BINDING_ID"; then
    # Resetta le proprietà del binding
    gsettings reset "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${BINDING_PATH}" name 2>/dev/null || true
    gsettings reset "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${BINDING_PATH}" command 2>/dev/null || true
    gsettings reset "org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:${BINDING_PATH}" binding 2>/dev/null || true

    # Rimuovi il path dall'array (manipolazione strutturata con Python)
    NEW_BINDINGS=$(python3 -c "
import sys, ast
current, remove_path = sys.argv[1], sys.argv[2]
arr = [] if current == '@as []' else ast.literal_eval(current)
arr = [p for p in arr if p != remove_path]
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
        echo "Shortcut GNOME rimosso."
    fi
else
    echo "Nessuno shortcut GNOME trovato per paste-image."
fi

# --- 3. Rimuovi modifiche al PATH dal shell config ---

remove_from_rc() {
    local rc_file="$1"
    if [ -f "$rc_file" ] && grep -q '# Aggiunto da paste-image installer' "$rc_file" 2>/dev/null; then
        # Rimuovi riga vuota + commento se consecutive (cleanup vecchie installazioni
        # che aggiungevano una blank line prima del commento)
        sed -i '/^$/{N;/\n# Aggiunto da paste-image installer$/d;}' "$rc_file"
        # Rimuovi commento rimasto (nuove installazioni senza riga vuota,
        # o vecchie installazioni dove l'utente ha editato il file)
        sed -i '/^# Aggiunto da paste-image installer$/d' "$rc_file"
        # shellcheck disable=SC2016 # Il pattern matcha il letterale $HOME/$PATH nel file
        sed -i '/^export PATH="\$HOME\/\.local\/bin:\$PATH"$/d' "$rc_file"
        echo "Rimossa modifica PATH da: $rc_file"
    fi
}

remove_from_rc "$HOME/.bashrc"
remove_from_rc "$HOME/.zshrc"

# --- 4. Rimuovi log e stato ---

LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/paste-image"
if [ -d "$LOG_DIR" ]; then
    rm -rf "$LOG_DIR"
    echo "Directory log rimossa: $LOG_DIR"
else
    echo "Directory log non trovata (già rimossa?)"
fi

# --- 5. Pulizia file temporanei ---

TMP_FILES=(/tmp/paste_image_*.png)
# Se il glob non matcha, bash restituisce il pattern letterale
if [ -e "${TMP_FILES[0]}" ]; then
    TMP_COUNT=${#TMP_FILES[@]}
    echo "Trovati $TMP_COUNT file temporanei in /tmp."
    rm -f /tmp/paste_image_*.png
    echo "File temporanei rimossi."
else
    echo "Nessun file temporaneo trovato in /tmp."
fi

# --- 6. Riepilogo ---

echo ""
echo "=== Disinstallazione completata ==="
echo ""
echo "NOTA: Le dipendenze di sistema (xclip, xdotool, libnotify-bin)"
echo "      NON sono state rimosse (potrebbero essere usate da altri programmi)."
