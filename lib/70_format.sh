# shellcheck shell=bash
#
# 70_format.sh — Formato del testo consegnato al terminale
#
# Ogni assistente vuole il path in una forma diversa: nudo per Claude Code,
# preceduto da /add per Aider, da @ per Gemini CLI. Indovinare male non rompe
# nulla ma costa all'utente una correzione a mano ogni volta.
#
# Su Wayland la finestra attiva non è interrogabile, quindi il rilevamento
# non è possibile e il path nudo diventa il comportamento reale, non un caso
# limite: è sempre incollabile e non corrompe il prompt.
#

# Template per un programma noto. Funzione pura: nessun accesso al sistema.
format_template_for() {
    case "$1" in
        aider)                echo "/add %s" ;;
        gemini)               echo "@%s" ;;
        claude|claude-code)   echo "%s" ;;
        *)                    echo "" ;;
    esac
}

# Scende nell'albero dei processi partendo dal PID della finestra fino alla
# foglia: il PID della finestra è quello dell'emulatore di terminale, mentre
# il programma che ci interessa è il suo discendente più profondo.
#
# La discesa segue sempre il primo figlio e si ferma a una profondità
# massima: un albero con un ciclo, o più profondo del previsto, farebbe
# girare a vuoto un processo che l'utente sta aspettando.
format_leaf_process() {
    local pid="$1" depth=0 child name
    local max_depth=12

    [ -n "$pid" ] || return 1

    while [ "$depth" -lt "$max_depth" ]; do
        child=$(ps --ppid "$pid" -o pid= --sort=start_time 2>/dev/null | tail -1 | tr -d ' ')
        [ -z "$child" ] && break
        pid="$child"
        depth=$((depth + 1))
    done

    name=$(ps -p "$pid" -o comm= 2>/dev/null | tr -d ' ')
    [ -n "$name" ] || return 1
    echo "$name"
}

# Rileva il programma in primo piano nel terminale attivo.
# Ritorna 1 quando il rilevamento non è possibile, che su Wayland è sempre.
format_detect_process() {
    local window="$1" pid

    [ -n "$window" ] || return 1
    command -v xdotool &>/dev/null || return 1

    pid=$(xdotool getwindowpid "$window" 2>/dev/null) || return 1
    format_leaf_process "$pid"
}

# Sceglie il template da usare, rispettando la precedenza:
# configurazione esplicita dell'utente, poi rilevamento, poi path nudo.
format_choose_template() {
    local configured="$1" window="$2" process

    if [ -n "$configured" ]; then
        echo "$configured"
        return 0
    fi

    if process=$(format_detect_process "$window"); then
        format_template_for "$process"
        return 0
    fi

    echo ""
}
