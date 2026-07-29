# shellcheck shell=bash
#
# 60_shortcut.sh — Conversione del formato delle scorciatoie fra desktop
#
# Il formato canonico interno è quello GTK, già usato dalla configurazione
# GNOME: `<Control><Shift>v`. Ogni ambiente ha la propria notazione, e le
# conversioni sono funzioni pure, quindi verificabili senza possedere quei
# desktop.
#

# Formato GTK valido: uno o più <Modificatore> seguiti da un nome tasto.
# Esempi: <Control><Shift>v, <Super>Print, <Alt>F1, <Control>KP_Enter
shortcut_validate_gtk() {
    [[ "$1" =~ ^\<[A-Za-z]+\>(\<[A-Za-z]+\>)*[a-zA-Z0-9_]+$ ]]
}

# Estrae il nome del tasto, cioè quello che segue l'ultimo modificatore.
shortcut_key_of() {
    echo "${1##*>}"
}

# Stampa i modificatori, uno per riga, in minuscolo e senza parentesi.
shortcut_modifiers_of() {
    local spec="$1" mods
    mods="${spec%"$(shortcut_key_of "$spec")"}"
    echo "$mods" | tr -d '<' | tr '>' '\n' | grep -v '^$' | tr '[:upper:]' '[:lower:]'
}

# --- Conversioni ---
#
# I nomi dei modificatori differiscono fra ambienti, e sbagliarli produce
# una scorciatoia registrata ma inerte: il caso più difficile da
# diagnosticare per chi installa.

_map_modifier() {
    local mod="$1" target="$2"

    case "$target" in
        kde)
            case "$mod" in
                control|primary) echo "Ctrl" ;;
                shift)           echo "Shift" ;;
                alt)             echo "Alt" ;;
                super)           echo "Meta" ;;
                *)               return 1 ;;
            esac
            ;;
        sway|i3)
            case "$mod" in
                control|primary) echo "Control" ;;
                shift)           echo "Shift" ;;
                alt)             echo "Mod1" ;;
                super)           echo "Mod4" ;;
                *)               return 1 ;;
            esac
            ;;
        hyprland)
            case "$mod" in
                control|primary) echo "CTRL" ;;
                shift)           echo "SHIFT" ;;
                alt)             echo "ALT" ;;
                super)           echo "SUPER" ;;
                *)               return 1 ;;
            esac
            ;;
        *)
            return 1
            ;;
    esac
}

# Unisce modificatori e tasto con il separatore dell'ambiente di destinazione.
_join_shortcut() {
    local spec="$1" target="$2" separator="$3" key_case="$4"
    local mod mapped key parts=""

    while IFS= read -r mod; do
        [ -z "$mod" ] && continue
        mapped=$(_map_modifier "$mod" "$target") || return 1
        if [ -z "$parts" ]; then
            parts="$mapped"
        else
            parts="${parts}${separator}${mapped}"
        fi
    done < <(shortcut_modifiers_of "$spec")

    key=$(shortcut_key_of "$spec")
    case "$key_case" in
        lower)
            key=$(echo "$key" | tr '[:upper:]' '[:lower:]')
            ;;
        upper)
            # Solo i tasti a carattere singolo vanno in maiuscolo: un nome
            # come Print o KP_Enter è un identificatore, e "PRINT" non
            # verrebbe riconosciuto.
            if [ "${#key}" -eq 1 ]; then
                key=$(echo "$key" | tr '[:lower:]' '[:upper:]')
            fi
            ;;
    esac

    if [ -z "$parts" ]; then
        echo "$key"
    else
        echo "${parts}${separator}${key}"
    fi
}

# KDE usa la notazione di kglobalshortcutsrc: Ctrl+Shift+V
shortcut_gtk_to_kde() {
    shortcut_validate_gtk "$1" || return 1
    _join_shortcut "$1" kde "+" upper
}

# sway e i3 usano Mod4+Shift+v, con il tasto in minuscolo
shortcut_gtk_to_sway() {
    shortcut_validate_gtk "$1" || return 1
    _join_shortcut "$1" sway "+" lower
}

shortcut_gtk_to_i3() {
    shortcut_validate_gtk "$1" || return 1
    _join_shortcut "$1" i3 "+" lower
}

# Hyprland separa i modificatori dal tasto con una virgola
shortcut_gtk_to_hyprland() {
    shortcut_validate_gtk "$1" || return 1
    local spec="$1" mods key mod mapped parts=""

    while IFS= read -r mod; do
        [ -z "$mod" ] && continue
        mapped=$(_map_modifier "$mod" hyprland) || return 1
        if [ -z "$parts" ]; then
            parts="$mapped"
        else
            parts="${parts} ${mapped}"
        fi
    done < <(shortcut_modifiers_of "$spec")

    key=$(shortcut_key_of "$spec" | tr '[:upper:]' '[:lower:]')
    echo "${parts}, ${key}"
}

# --- Righe di configurazione pronte da incollare ---
#
# Sui window manager non esiste un registro da scrivere: la scorciatoia vive
# nel file di configurazione dell'utente, che è suo. Stampare la riga esatta
# è più utile e meno invasivo che modificargliela.

shortcut_config_line() {
    local wm="$1" spec="$2" command="$3" converted

    case "$wm" in
        sway)
            converted=$(shortcut_gtk_to_sway "$spec") || return 1
            echo "bindsym $converted exec $command"
            ;;
        i3)
            converted=$(shortcut_gtk_to_i3 "$spec") || return 1
            echo "bindsym $converted exec --no-startup-id $command"
            ;;
        hyprland)
            converted=$(shortcut_gtk_to_hyprland "$spec") || return 1
            echo "bind = $converted, exec, $command"
            ;;
        *)
            return 1
            ;;
    esac
}

# Etichetta del file di configurazione da mostrare all'utente. La tilde è
# voluta: è la forma in cui una persona riconosce il proprio file, non un
# percorso che questo codice apre.
# shellcheck disable=SC2088
shortcut_config_file_label() {
    case "$1" in
        sway)     echo "~/.config/sway/config" ;;
        i3)       echo "~/.config/i3/config" ;;
        hyprland) echo "~/.config/hypr/hyprland.conf" ;;
        *)        return 1 ;;
    esac
}

# Istruzioni pronte da seguire per un window manager. Stampate, non
# applicate: il file di configurazione appartiene all'utente, e un tool che
# lo modifica da sé è un tool di cui diffidare.
shortcut_print_instructions() {
    local wm="$1" spec="${2:-<Control><Shift>v}" command="$3"
    local line label

    if ! line=$(shortcut_config_line "$wm" "$spec" "$command"); then
        echo "Ambiente '$wm' non riconosciuto."
        echo "Ambienti disponibili: sway, i3, hyprland."
        return 1
    fi

    label=$(shortcut_config_file_label "$wm")

    echo "Aggiungi questa riga a $label:"
    echo ""
    echo "    $line"
    echo ""
    echo "Poi ricarica la configurazione del window manager."
    return 0
}
