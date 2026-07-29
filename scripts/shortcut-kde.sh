#!/usr/bin/env bash
#
# shortcut-kde.sh — Registra o rimuove la scorciatoia su KDE Plasma
#
# Uso: shortcut-kde.sh install <scorciatoia-gtk> <comando>
#      shortcut-kde.sh remove
#
# KDE tiene le scorciatoie globali in ~/.config/kglobalshortcutsrc, un file
# in stile INI, e le associa a un file .desktop. Il file viene modificato
# preservando tutto il resto: contiene le scorciatoie di ogni applicazione
# dell'utente, e riscriverlo per intero sarebbe distruttivo.
#
# Il funzionamento reale su KDE non è stato verificato: non c'è hardware
# disponibile. Quello che è verificato è il contenuto prodotto nel file.
#

set -euo pipefail

_SELF="${BASH_SOURCE[0]}"
_SELF_DIR="${_SELF%/*}"
[ "$_SELF_DIR" = "$_SELF" ] && _SELF_DIR="."
MODULES="$(cd "$_SELF_DIR/../lib" && pwd)"

# shellcheck source=../lib/05_text.sh
source "$MODULES/05_text.sh"
# shellcheck source=../lib/60_shortcut.sh
source "$MODULES/60_shortcut.sh"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
SHORTCUTS_FILE="$CONFIG_DIR/kglobalshortcutsrc"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DESKTOP_ID="paste-image.desktop"
FRIENDLY_NAME="Paste Image"

write_desktop_entry() {
    local command="$1"

    mkdir -p "$DESKTOP_DIR"
    cat > "$DESKTOP_DIR/$DESKTOP_ID" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$FRIENDLY_NAME
Comment=Incolla un'immagine dagli appunti nel terminale attivo
Exec=$command
Terminal=false
NoDisplay=true
X-KDE-GlobalAccel-CommandShortcut=true
DESKTOP
}

# Rimuove il gruppo [paste-image.desktop] e le sue righe, lasciando intatto
# tutto il resto del file.
strip_existing_group() {
    local source_file="$1" dest_file="$2"
    local in_group=0 line

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            "[$DESKTOP_ID]")
                in_group=1
                continue
                ;;
            \[*\])
                in_group=0
                ;;
        esac
        [ "$in_group" -eq 1 ] && continue
        printf '%s\n' "$line"
    done < "$source_file" > "$dest_file"
}

do_install() {
    local spec="$1" command="$2" converted tmp

    if ! converted=$(shortcut_gtk_to_kde "$spec"); then
        echo "ERRORE: scorciatoia '$spec' non convertibile per KDE." >&2
        return 1
    fi

    write_desktop_entry "$command"
    mkdir -p "$CONFIG_DIR"
    touch "$SHORTCUTS_FILE"

    # Backup prima di toccare un file che contiene le scorciatoie di tutto
    # il desktop: se la scrittura andasse storta, perderle sarebbe un danno
    # sproporzionato rispetto alla funzione che stiamo aggiungendo.
    cp "$SHORTCUTS_FILE" "${SHORTCUTS_FILE}.paste-image-backup"

    tmp=$(mktemp)
    strip_existing_group "$SHORTCUTS_FILE" "$tmp"

    {
        printf '[%s]\n' "$DESKTOP_ID"
        printf '_k_friendly_name=%s\n' "$FRIENDLY_NAME"
        printf '_launch=%s,none,%s\n' "$converted" "$FRIENDLY_NAME"
    } >> "$tmp"

    mv "$tmp" "$SHORTCUTS_FILE"
    echo "Scorciatoia registrata in $SHORTCUTS_FILE: $converted"

    reload_kglobalaccel "$converted"
}

# Senza una ricarica il file è scritto ma la scorciatoia resta inerte fino
# al prossimo login. Se il servizio non risponde lo diciamo, invece di
# lasciare l'utente a chiedersi perché non funziona.
reload_kglobalaccel() {
    local converted="$1"

    if command -v kquitapp6 &>/dev/null && command -v kstart6 &>/dev/null; then
        if kquitapp6 kglobalaccel &>/dev/null; then
            sleep 1
            kstart6 kglobalaccel &>/dev/null || true
            echo "Servizio delle scorciatoie ricaricato."
            return 0
        fi
    elif command -v kquitapp5 &>/dev/null && command -v kstart5 &>/dev/null; then
        if kquitapp5 kglobalaccel &>/dev/null; then
            sleep 1
            kstart5 kglobalaccel &>/dev/null || true
            echo "Servizio delle scorciatoie ricaricato."
            return 0
        fi
    fi

    echo ""
    echo "Non è stato possibile ricaricare il servizio delle scorciatoie."
    echo "La scorciatoia $converted sarà attiva dopo il prossimo accesso,"
    echo "oppure impostala da Impostazioni di sistema > Scorciatoie."
    return 0
}

do_remove() {
    local tmp

    if [ -f "$DESKTOP_DIR/$DESKTOP_ID" ]; then
        rm -f "$DESKTOP_DIR/$DESKTOP_ID"
        echo "Voce desktop rimossa: $DESKTOP_DIR/$DESKTOP_ID"
    fi

    if [ ! -f "$SHORTCUTS_FILE" ]; then
        echo "Nessun file di scorciatoie KDE da aggiornare."
        return 0
    fi

    tmp=$(mktemp)
    strip_existing_group "$SHORTCUTS_FILE" "$tmp"
    mv "$tmp" "$SHORTCUTS_FILE"
    echo "Scorciatoia rimossa da $SHORTCUTS_FILE"

    rm -f "${SHORTCUTS_FILE}.paste-image-backup"
}

case "${1:-}" in
    install)
        do_install "${2:?scorciatoia mancante}" "${3:?comando mancante}"
        ;;
    remove)
        do_remove
        ;;
    *)
        echo "Uso: $0 install <scorciatoia-gtk> <comando> | remove" >&2
        exit 1
        ;;
esac
