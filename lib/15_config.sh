# shellcheck shell=bash
# I valori di configurazione sono consumati dagli altri moduli dopo la
# concatenazione: in isolamento risultano tutti inutilizzati.
# shellcheck disable=SC2034
#
# 15_config.sh — Configurazione utente
#
# Il file di configurazione viene PARSATO, mai sorgiato: un `source` di un
# file utente sarebbe esecuzione di codice arbitrario a ogni pressione dello
# shortcut. Solo le chiavi in whitelist vengono accettate e ognuna passa una
# validazione per tipo.
#
# Precedenza: default < file di configurazione < variabile d'ambiente < flag.
#

# Chiavi ammesse e relativo tipo di validazione.
# Una chiave assente da questa tabella viene rifiutata, non ignorata.
_config_type_of() {
    case "$1" in
        MAX_LOG_LINES|NOTIFY_TIMEOUT|CLEANUP_DAYS|MAX_LONG_SIDE|HISTORY_SIZE)
            echo "int" ;;
        TYPING_DELAY)
            echo "decimal" ;;
        OUTPUT_DIR)
            echo "path" ;;
        FORMAT_TEMPLATE)
            echo "template" ;;
        TYPING_BACKEND)
            echo "backend" ;;
        PREFER_EXISTING_FILE|RESIZE_ENABLED)
            echo "bool" ;;
        *)
            return 1 ;;
    esac
}

# --- Default ---

config_defaults() {
    MAX_LOG_LINES=500          # Soglia di rotazione del file di log (in righe)
    NOTIFY_TIMEOUT=3000        # Durata notifiche desktop in millisecondi
    CLEANUP_DAYS=7             # Giorni dopo cui i file temporanei vengono eliminati
    TYPING_DELAY=0.1           # Pausa prima della digitazione (stabilità focus)
    OUTPUT_DIR="/tmp"          # Directory di destinazione delle immagini
    MAX_LONG_SIDE=1568         # Lato lungo massimo in pixel, 0 disabilita
    HISTORY_SIZE=50            # Voci conservate nello storico
    FORMAT_TEMPLATE=""         # Vuoto: path nudo, deciso dal rilevamento
    TYPING_BACKEND=""          # Vuoto: scelto dalla tabella per sessione
    PREFER_EXISTING_FILE=1     # Un file già su disco non viene duplicato
    RESIZE_ENABLED=1           # Ridimensionamento automatico oltre MAX_LONG_SIDE
}

config_file_path() {
    echo "${XDG_CONFIG_HOME:-$HOME/.config}/paste-image/config"
}

# --- Validazione per tipo ---

_config_valid_int() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

_config_valid_decimal() {
    [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]
}

_config_valid_path() {
    [[ "$1" == /* ]] && ! _config_has_control_chars "$1"
}

_config_valid_bool() {
    [[ "$1" == "0" || "$1" == "1" ]]
}

_config_valid_backend() {
    case "$1" in
        ""|xdotool|wtype|ydotool|clipboard) return 0 ;;
        *) return 1 ;;
    esac
}

# Caratteri di controllo C0/C1 e override bidirezionali Unicode.
# Il primo gruppo rende un valore eseguibile una volta digitato in un
# terminale, il secondo maschera visivamente il contenuto reale.
_config_has_control_chars() {
    local value="$1"
    [[ "$value" == *[[:cntrl:]]* ]] && return 0
    case "$value" in
        *$'‪'*|*$'‫'*|*$'‬'*|*$'‭'*|*$'‮'*) return 0 ;;
        *$'⁦'*|*$'⁧'*|*$'⁨'*|*$'⁩'*) return 0 ;;
    esac
    return 1
}

# Il template finisce digitato nel terminale a ogni invocazione, per sempre:
# un valore ostile qui persiste, a differenza di un path che arriva una volta
# sola dagli appunti. La validazione è a whitelist, non a blacklist.
_config_valid_template() {
    local value="$1"
    local stripped

    [ -z "$value" ] && return 0
    [ "${#value}" -gt 200 ] && return 1
    _config_has_control_chars "$value" && return 1

    # Esattamente un segnaposto
    stripped="${value//%s/}"
    [ "${#value}" -eq $(( ${#stripped} + 2 )) ] || return 1
    [[ "$stripped" == *%* ]] && return 1

    # Solo caratteri necessari a comporre un comando di allegato
    [[ "$stripped" =~ ^[A-Za-z0-9/@._:=+-]*[[:space:]]*[A-Za-z0-9/@._:=+-]*$ ]] || return 1
    return 0
}

_config_validate() {
    local type="$1" value="$2"
    case "$type" in
        int)      _config_valid_int "$value" ;;
        decimal)  _config_valid_decimal "$value" ;;
        path)     _config_valid_path "$value" ;;
        bool)     _config_valid_bool "$value" ;;
        backend)  _config_valid_backend "$value" ;;
        template) _config_valid_template "$value" ;;
        *)        return 1 ;;
    esac
}

# --- Parsing ---

# Rimuove una singola coppia di apici o virgolette attorno al valore.
_config_unquote() {
    local value="$1"
    if [[ "$value" == \"*\" && "${#value}" -ge 2 ]]; then
        value="${value:1:${#value}-2}"
    elif [[ "$value" == \'*\' && "${#value}" -ge 2 ]]; then
        value="${value:1:${#value}-2}"
    fi
    echo "$value"
}

# Legge il file di configurazione. Le anomalie finiscono in CONFIG_WARNINGS,
# che l'orchestratore riversa nel log una volta inizializzato lo stato:
# una chiave scartata in silenzio è indistinguibile da una applicata.
config_load_file() {
    local file="$1"
    local line key value type

    CONFIG_WARNINGS=()
    [ -f "$file" ] || return 0

    while IFS= read -r line || [ -n "$line" ]; do
        line="${line#"${line%%[![:space:]]*}"}"
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue

        if [[ "$line" != *=* ]]; then
            CONFIG_WARNINGS+=("riga senza '=' ignorata: $line")
            continue
        fi

        key="${line%%=*}"
        value="${line#*=}"
        key="${key%"${key##*[![:space:]]}"}"
        value="${value#"${value%%[![:space:]]*}"}"
        value="${value%"${value##*[![:space:]]}"}"
        value=$(_config_unquote "$value")

        if ! type=$(_config_type_of "$key"); then
            CONFIG_WARNINGS+=("chiave sconosciuta ignorata: $key")
            continue
        fi

        if ! _config_validate "$type" "$value"; then
            CONFIG_WARNINGS+=("valore non valido per $key, mantenuto il default")
            continue
        fi

        printf -v "$key" '%s' "$value"
    done < "$file"
}

# --- Override da ambiente ---

# Ogni chiave accetta un override PASTE_IMAGE_<CHIAVE>, che vince sul file.
# Passa dalla stessa validazione: l'ambiente non è più fidato del file.
config_apply_env() {
    local key env_name env_value type
    for key in MAX_LOG_LINES NOTIFY_TIMEOUT CLEANUP_DAYS TYPING_DELAY \
               OUTPUT_DIR MAX_LONG_SIDE HISTORY_SIZE FORMAT_TEMPLATE \
               TYPING_BACKEND PREFER_EXISTING_FILE RESIZE_ENABLED; do
        env_name="PASTE_IMAGE_${key}"
        env_value="${!env_name-}"
        [ -z "${!env_name+set}" ] && continue

        type=$(_config_type_of "$key") || continue
        if _config_validate "$type" "$env_value"; then
            printf -v "$key" '%s' "$env_value"
        else
            CONFIG_WARNINGS+=("valore non valido per $env_name, mantenuto il precedente")
        fi
    done
}

config_init() {
    config_defaults
    config_load_file "$(config_file_path)"
    config_apply_env
}
