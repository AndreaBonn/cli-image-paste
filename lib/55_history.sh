# shellcheck shell=bash
#
# 55_history.sh — Riconsegna di un'immagine già acquisita
#
# Serve perché la consegna via appunti sovrascrive gli appunti stessi e
# distrugge l'immagine di partenza: senza questo, un secondo tentativo
# richiederebbe di rifare lo screenshot o ricopiare l'immagine.
#

# Riconsegna un'immagine già acquisita, senza ripassare dagli appunti.
source_from_history() {
    local index="${1:-1}" path status=0

    path=$(history_get "$index") || status=$?

    case "$status" in
        0)
            log "riconsegna dallo storico, posizione $index"
            echo "$path"
            return 0
            ;;
        2)
            notify "L'immagine in posizione $index non esiste più sul disco"
            history_prune_missing
            return 1
            ;;
        *)
            notify "Nessuna immagine in posizione $index nello storico"
            return 1
            ;;
    esac
}
