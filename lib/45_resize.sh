# shellcheck shell=bash
#
# 45_resize.sh — Ridimensionamento e driver della pipeline
#
# Il ridimensionamento evita di spedire uno screenshot 4K quando il modello
# lo ridurrebbe comunque: costa banda e token senza aggiungere dettaglio
# utilizzabile. Lo strip dei metadati evita anche di spedire la
# geolocalizzazione di una foto.
#

# --- Dimensioni e ridimensionamento ---

# Stampa "larghezza altezza". Ritorna 1 se le dimensioni non sono leggibili.
image_dimensions() {
    local path="$1" bin out

    if command -v identify &>/dev/null; then
        out=$(identify -format '%w %h' "${path}[0]" 2>/dev/null) || return 1
    else
        bin=$(transform_magick_bin) || return 1
        out=$("$bin" "${path}[0]" -format '%w %h' info: 2>/dev/null) || return 1
    fi

    [ -n "$out" ] || return 1
    echo "$out"
}

# Decisione pura: serve ridimensionare? Un limite a 0 disabilita, e
# un'immagine già sotto la soglia non va toccata, altrimenti la si
# ricomprimerebbe senza guadagno.
image_needs_resize() {
    local width="$1" height="$2" max="$3"

    [ "$max" -eq 0 ] && return 1
    [ "$width" -gt "$max" ] && return 0
    [ "$height" -gt "$max" ] && return 0
    return 1
}

# Ridimensiona mantenendo le proporzioni e rimuove i metadati.
#
# Il lato lungo massimo di default è la soglia oltre cui i modelli
# ridimensionano comunque l'immagine lato loro: mandarne una più grande
# costa banda e token senza aggiungere dettaglio utilizzabile. Lo strip
# serve anche a non spedire la geolocalizzazione di uno screenshot.
image_resize() {
    local src="$1" dst="$2" max="$3" bin

    bin=$(transform_magick_bin) || return 1

    # shellcheck disable=SC2046 # I limiti sono una lista di argomenti
    MAGICK_CONFIGURE_PATH="$(_transform_policy_dir)" \
        "$bin" $(_transform_limits) "${src}[0]" \
        -resize "${max}x${max}>" -strip "png:$dst" 2>/dev/null
}

# --- Driver della pipeline ---
#
# Ogni file intermedio ha il proprio mktemp, mai un nome derivato per
# manipolazione di stringa: quella sarebbe la stessa race e lo stesso
# symlink attack che mktemp era stato adottato per eliminare.
#
# Gli intermedi vengono rimossi appena non servono: la pipeline moltiplica
# le copie dello stesso contenuto, che può essere lo screenshot di un
# gestore di password, e lasciarle scadere insieme al risultato finale ne
# allungherebbe la vita per giorni.

# La directory in cui la pipeline ha creato i suoi intermedi. Impostata
# dall'orchestratore, che gira nella shell principale.
TRANSFORM_TEMP_DIR=""

# Prefisso dei file intermedi. La pulizia lavora su questo pattern e non su
# un elenco accumulato: le funzioni che allocano un temporaneo stampano il
# path su stdout, quindi vengono invocate in una command substitution, e
# qualunque array popolato lì dentro vivrebbe in una subshell e sarebbe già
# perduto al ritorno. Il pattern è invece visibile a chiunque, anche se il
# processo muore a metà.
TRANSFORM_TEMP_PREFIX="paste_image_step_"

transform_cleanup_temps() {
    [ -n "$TRANSFORM_TEMP_DIR" ] || return 0
    [ -d "$TRANSFORM_TEMP_DIR" ] || return 0

    local temp
    for temp in "$TRANSFORM_TEMP_DIR/${TRANSFORM_TEMP_PREFIX}"*; do
        [ -f "$temp" ] && rm -f "$temp"
    done
    return 0
}

_transform_new_temp() {
    local dir="$1" ext="$2"
    mktemp "${dir}/${TRANSFORM_TEMP_PREFIX}XXXXXX.${ext}"
}

# Applica il ridimensionamento se serve. Stampa il path del file da usare:
# quello nuovo se ha ridimensionato, l'originale altrimenti.
#
# Uno step di miglioramento accessorio non deve mai far fallire l'operazione:
# se ImageMagick manca o la conversione va storta, si prosegue con il file
# che c'era, dopo averlo annotato nel log.
transform_apply_resize() {
    local path="$1" max="$2" dir="$3"
    local dims width height resized

    [ "$max" -eq 0 ] && { echo "$path"; return 0; }

    if ! transform_magick_available; then
        echo "$path"
        return 0
    fi

    if ! dims=$(image_dimensions "$path"); then
        echo "$path"
        return 0
    fi

    width="${dims%% *}"
    height="${dims##* }"

    if ! image_needs_resize "$width" "$height" "$max"; then
        echo "$path"
        return 0
    fi

    resized=$(_transform_new_temp "$dir" png) || { echo "$path"; return 0; }

    if ! image_resize "$path" "$resized" "$max"; then
        echo "$path"
        return 0
    fi

    echo "$resized"
}

# Esegue la pipeline sul file acquisito e stampa il path finale.
#
# L'originale non viene mai modificato in place: se la sorgente è un file
# dell'utente, indicato dal file manager, ridimensionarlo sul posto
# significherebbe alterare un suo file senza che l'abbia chiesto.
transform_run() {
    local path="$1" dir="$2"
    local result final

    TRANSFORM_TEMP_DIR="$dir"

    if [ "${RESIZE_ENABLED:-1}" != "1" ]; then
        echo "$path"
        return 0
    fi

    result=$(transform_apply_resize "$path" "${MAX_LONG_SIDE:-0}" "$dir")

    if [ "$result" = "$path" ]; then
        echo "$path"
        return 0
    fi

    # Il file intermedio diventa il risultato: gli si dà il nome definitivo
    # perché è quello che l'utente vedrà digitato nel terminale.
    if ! final=$(mktemp "${dir}/paste_image_$(date +%Y%m%d_%H%M%S)_XXXXXX.png"); then
        echo "$result"
        return 0
    fi

    if ! mv "$result" "$final"; then
        echo "$result"
        return 0
    fi

    # L'originale non serve più. Va rimosso solo se l'abbiamo creato noi:
    # riconoscibile dal prefisso. Un file indicato dal file manager
    # appartiene all'utente, e cancellarglielo dopo un incolla sarebbe
    # perdita di dati, non pulizia.
    if _transform_is_our_file "$path" "$dir"; then
        rm -f "$path"
    fi

    echo "$final"
}

# Vero se il file è stato prodotto da noi nella directory di lavoro.
_transform_is_our_file() {
    local path="$1" dir="$2" base

    [ "${path%/*}" = "$dir" ] || return 1
    base="${path##*/}"
    case "$base" in
        paste_image_*) return 0 ;;
        *) return 1 ;;
    esac
}


# Applica l'annotazione interattiva. A differenza del resize, questo step
# entra in gioco solo su richiesta esplicita dell'utente: ignorare un flag
# appena scritto sarebbe il peggior esito possibile, quindi qui l'assenza
# dello strumento è un errore e non una degradazione.
transform_apply_annotate() {
    local path="$1" dir="$2" tool annotated status

    if ! tool=$(annotate_tool); then
        notify "$(annotate_missing_message)"
        return 1
    fi

    annotated=$(_transform_new_temp "$dir" png) || return 1

    annotate_run "$tool" "$path" "$annotated"
    status=$?

    case "$status" in
        0)
            log "annotazione applicata con $tool"
            echo "$annotated"
            return 0
            ;;
        2)
            # Chiudere senza salvare è una decisione: si prosegue con
            # l'immagine originale, senza trattarlo come fallimento.
            log "annotazione chiusa senza salvare"
            rm -f "$annotated"
            echo "$path"
            return 0
            ;;
        *)
            notify "Annotazione non riuscita con $tool"
            rm -f "$annotated"
            return 1
            ;;
    esac
}
