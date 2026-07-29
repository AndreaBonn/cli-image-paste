# shellcheck shell=bash
#
# 40_transform.sh — Trasformazioni sul file immagine
#
# Ogni step è una funzione file → file: non conosce la pipeline, non alloca
# temporanei, non notifica e non decide se saltare sé stesso. È ciò che
# rende testabile la parte di codice destinata a crescere di più.
#

# --- ImageMagick ---

# ImageMagick 7 espone `magick`, la 6 solo `convert`. Su una installazione
# solo-IM7 `convert` può mancare del tutto, quindi vanno cercati entrambi e
# il messaggio d'errore deve nominarli entrambi.
transform_magick_bin() {
    if command -v magick &>/dev/null; then
        echo "magick"
    elif command -v convert &>/dev/null; then
        echo "convert"
    else
        return 1
    fi
}

transform_magick_available() {
    transform_magick_bin >/dev/null 2>&1
}

# Policy restrittiva dedicata, non quella di sistema.
#
# La policy di sistema è assente su alcune distribuzioni e permissiva su
# altre, e ImageMagick ha una storia di delegate che eseguono comandi
# (CVE-2016-3714) e di coder che leggono file arbitrari. L'input qui arriva
# dagli appunti, cioè da contenuto potenzialmente ostile.
_transform_policy_dir() {
    local dir="${XDG_STATE_HOME:-$HOME/.local/state}/paste-image/magick"
    local policy="$dir/policy.xml"

    if [ ! -f "$policy" ]; then
        mkdir -p "$dir"
        cat > "$policy" <<'POLICY'
<policymap>
  <policy domain="delegate" rights="none" pattern="*"/>
  <policy domain="coder" rights="none" pattern="MSL"/>
  <policy domain="coder" rights="none" pattern="MVG"/>
  <policy domain="coder" rights="none" pattern="EPHEMERAL"/>
  <policy domain="coder" rights="none" pattern="URL"/>
  <policy domain="coder" rights="none" pattern="HTTPS"/>
  <policy domain="coder" rights="none" pattern="HTTP"/>
  <policy domain="coder" rights="none" pattern="FTP"/>
  <policy domain="coder" rights="none" pattern="TEXT"/>
  <policy domain="coder" rights="none" pattern="SHOW"/>
  <policy domain="coder" rights="none" pattern="WIN"/>
  <policy domain="coder" rights="none" pattern="PLT"/>
  <policy domain="path" rights="none" pattern="@*"/>
</policymap>
POLICY
    fi

    echo "$dir"
}

# Limiti di risorsa passati sulla riga di comando, come difesa in
# profondità rispetto alla policy: un'immagine che dichiara dimensioni
# enormi nell'header consuma memoria prima ancora di essere decodificata.
_transform_limits() {
    echo "-limit memory 256MiB -limit map 512MiB -limit disk 1GiB -limit thread 2"
}

# --- Conversione di formato ---

# Converte src in PNG su dst. Ritorna 1 se ImageMagick manca o fallisce.
#
# Le GIF animate hanno più frame: senza selezione esplicita del primo,
# ImageMagick produrrebbe un file per frame invece di una singola immagine.
image_convert() {
    local src="$1" dst="$2" mime="${3:-}"
    local bin source_spec

    bin=$(transform_magick_bin) || return 1

    source_spec="$src"
    case "$mime" in
        image/gif) source_spec="${src}[0]" ;;
    esac

    # Argomenti passati come lista, mai una stringa interpolata in una
    # shell: il path arriva da una sorgente esterna.
    # shellcheck disable=SC2046 # I limiti sono una lista di argomenti, non un singolo token
    MAGICK_CONFIGURE_PATH="$(_transform_policy_dir)" \
        "$bin" $(_transform_limits) "$source_spec" -strip "png:$dst" 2>/dev/null
}

# Gli SVG non sono immagini raster: richiedono un rasterizzatore, e quello
# generico di ImageMagick ha una superficie di attacco più ampia di uno
# strumento dedicato, che tratta un solo formato.
image_convert_svg() {
    local src="$1" dst="$2"

    if command -v rsvg-convert &>/dev/null; then
        rsvg-convert --format=png --output="$dst" "$src" 2>/dev/null
        return
    fi

    return 1
}

# Messaggio che distingue le due cause: "manca ImageMagick" e "ImageMagick
# non sa rasterizzare questo formato" richiedono azioni diverse.
transform_missing_message() {
    local mime="$1"

    if [ "$mime" = "image/svg+xml" ] && ! command -v rsvg-convert &>/dev/null; then
        echo "Immagine SVG negli appunti: serve rsvg-convert. Installa con: sudo apt install librsvg2-bin"
        return
    fi

    echo "Formato $mime non gestito senza ImageMagick. Installa con: sudo apt install imagemagick"
}

# --- Punto di ingresso della conversione ---

# Converte verso PNG scegliendo lo strumento adatto al formato di partenza.
transform_to_png() {
    local src="$1" dst="$2" mime="$3"

    case "$mime" in
        image/svg+xml) image_convert_svg "$src" "$dst" ;;
        *)             image_convert "$src" "$dst" "$mime" ;;
    esac
}

# --- Annotazione ---
#
# È l'unico step interattivo, quindi va per ultimo: tutto ciò che è
# automatico deve essere già finito quando l'utente prende il controllo.
# Serve a indicare "questo bottone qui" e a oscurare dati sensibili prima di
# mandare uno screenshot a un servizio esterno.

annotate_tool() {
    local tool
    for tool in satty swappy; do
        command -v "$tool" &>/dev/null && { echo "$tool"; return 0; }
    done
    return 1
}

annotate_missing_message() {
    echo "Per annotare serve satty o swappy. Installa con: sudo apt install swappy"
}

# Apre l'annotatore sul file e scrive il risultato su dst.
#
# Ritorna 0 con dst scritto, 2 se l'utente ha chiuso senza salvare, 1 su
# errore. Chiudere senza salvare è una decisione: si consegna l'originale.
annotate_run() {
    local tool="$1" src="$2" dst="$3"

    case "$tool" in
        satty)  satty --filename "$src" --output-filename "$dst" --early-exit 2>/dev/null ;;
        swappy) swappy -f "$src" -o "$dst" 2>/dev/null ;;
        *)      return 1 ;;
    esac

    # Entrambi gli strumenti possono uscire con successo senza aver salvato:
    # l'unico segnale affidabile è se il file di destinazione ha contenuto.
    if [ ! -s "$dst" ]; then
        rm -f "$dst"
        return 2
    fi

    return 0
}
