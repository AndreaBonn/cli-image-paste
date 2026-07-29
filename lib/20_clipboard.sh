# shellcheck shell=bash
#
# 20_clipboard.sh — Lettura degli appunti
#
# Porta separata da quella di consegna: su Wayland leggere gli appunti
# funziona ovunque, è solo la digitazione a dipendere dal compositore.
#

# Formati immagine gestiti direttamente, in ordine di preferenza.
# PNG prima di JPEG: senza perdita e senza ricompressione.
CLIPBOARD_NATIVE_MIMES="image/png image/jpeg"

# Formati che richiedono una conversione prima di poter essere usati.
CLIPBOARD_CONVERTIBLE_MIMES="image/webp image/gif image/tiff image/bmp image/svg+xml image/avif"

# Target che descrivono un file già esistente su disco invece dei suoi byte.
CLIPBOARD_URI_TARGETS="x-special/gnome-copied-files text/uri-list"

# --- Backend ---

_clipboard_tool() {
    if [ "$(session_type)" = "wayland" ] && command -v wl-paste &>/dev/null; then
        echo "wl-paste"
    elif command -v xclip &>/dev/null; then
        echo "xclip"
    else
        return 1
    fi
}

# Stampa un target per riga.
clipboard_list_targets() {
    local tool
    tool=$(_clipboard_tool) || return 1

    case "$tool" in
        wl-paste) wl-paste --list-types 2>/dev/null ;;
        xclip)    xclip -selection clipboard -t TARGETS -o 2>/dev/null ;;
    esac
}

# Scrive il contenuto del target indicato sul file di destinazione.
clipboard_read() {
    local mime="$1" dest="$2" tool
    tool=$(_clipboard_tool) || return 1

    case "$tool" in
        wl-paste) wl-paste --type "$mime" --no-newline > "$dest" 2>/dev/null ;;
        xclip)    xclip -selection clipboard -t "$mime" -o > "$dest" 2>/dev/null ;;
    esac
}

# --- Scelta del target ---

# Stampa "azione|mime" dove azione è:
#   file      il target descrive un file già su disco, non va duplicato
#   native    formato utilizzabile così com'è
#   convert   formato che richiede conversione
# Ritorna 1 se non c'è nulla di utilizzabile.
#
# Il riferimento a un file esistente ha la precedenza: duplicare un file già
# su disco spreca spazio e produce un path che scade con la pulizia
# automatica, mentre l'originale resta.
clipboard_pick_target() {
    local targets="$1" prefer_existing="${2:-1}" mime

    if [ "$prefer_existing" = "1" ]; then
        for mime in $CLIPBOARD_URI_TARGETS; do
            if _targets_contain "$targets" "$mime"; then
                echo "file|$mime"
                return 0
            fi
        done
    fi

    for mime in $CLIPBOARD_NATIVE_MIMES; do
        if _targets_contain "$targets" "$mime"; then
            echo "native|$mime"
            return 0
        fi
    done

    for mime in $CLIPBOARD_CONVERTIBLE_MIMES; do
        if _targets_contain "$targets" "$mime"; then
            echo "convert|$mime"
            return 0
        fi
    done

    # Con la preferenza disattivata i riferimenti a file restano l'ultima
    # risorsa: meglio un path che nessuna immagine.
    if [ "$prefer_existing" != "1" ]; then
        for mime in $CLIPBOARD_URI_TARGETS; do
            if _targets_contain "$targets" "$mime"; then
                echo "file|$mime"
                return 0
            fi
        done
    fi

    return 1
}

# Confronto riga per riga: una sottostringa produrrebbe falsi positivi
# fra "image/png" e un ipotetico "image/png-fake".
_targets_contain() {
    local targets="$1" wanted="$2"
    printf '%s\n' "$targets" | grep -qxF "$wanted"
}

# --- Riferimenti a file ---

# Decodifica le sequenze percent di un URI.
#
# I backslash presenti nel nome del file vengono raddoppiati prima della
# conversione: printf '%b' li interpreterebbe come sequenze di escape, così
# un file chiamato "a\nb.png" produrrebbe un path con dentro un newline
# vero. Il '+' non viene toccato: vale come spazio nelle query string, non
# nella parte path di un URI, dove è un carattere legittimo.
uri_decode() {
    local encoded="$1"
    encoded="${encoded//\\/\\\\}"
    printf '%b' "${encoded//%/\\x}"
}

# Estrae il primo path utilizzabile dal payload di un target uri-list.
#
# Formati gestiti:
#   x-special/gnome-copied-files — prima riga "copy" o "cut", poi gli URI
#   text/uri-list                — un URI per riga, terminatori CRLF,
#                                  righe che iniziano con # sono commenti
#
# Solo lo schema file:// viene accettato: trash://, http:// e simili non
# descrivono un file leggibile qui e ora.
clipboard_file_from_uri() {
    local payload="$1" line uri path

    while IFS= read -r line; do
        # I terminatori dello standard sono CRLF: il CR va rimosso qui,
        # altrimenti finisce dentro il path e viene digitato nel terminale,
        # dove equivale a premere Invio.
        line="${line%$'\r'}"

        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue
        [ "$line" = "copy" ] && continue
        [ "$line" = "cut" ] && continue

        uri="$line"
        [[ "$uri" != file://* ]] && continue

        # Il decode precede ogni controllo: %0D diventa un CR solo dopo,
        # e un controllo fatto prima non lo vedrebbe.
        path=$(uri_decode "${uri#file://}")

        delivery_path_is_safe "$path" || continue
        [ -f "$path" ] || continue
        [ -r "$path" ] || continue

        echo "$path"
        return 0
    done <<< "$payload"

    return 1
}

# Legge il payload di un target uri-list e ne estrae il path.
clipboard_existing_file() {
    local mime="$1" payload tmp

    tmp=$(mktemp) || return 1
    if ! clipboard_read "$mime" "$tmp"; then
        rm -f "$tmp"
        return 1
    fi

    payload=$(cat "$tmp")
    rm -f "$tmp"

    clipboard_file_from_uri "$payload"
}

# --- Estensione dal MIME ---

clipboard_extension_for() {
    case "$1" in
        image/png)     echo "png" ;;
        image/jpeg)    echo "jpg" ;;
        image/webp)    echo "webp" ;;
        image/gif)     echo "gif" ;;
        image/tiff)    echo "tiff" ;;
        image/bmp)     echo "bmp" ;;
        image/avif)    echo "avif" ;;
        image/svg+xml) echo "svg" ;;
        *)             echo "bin" ;;
    esac
}
