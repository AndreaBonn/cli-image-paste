# shellcheck shell=bash
#
# 05_text.sh — Controlli sul testo destinato al terminale
#
# Fonte unica per la classificazione dei caratteri pericolosi. Prima queste
# regole erano duplicate fra la validazione della configurazione e quella
# del path, e le due liste erano già divergenti: una copriva i separatori
# di riga Unicode e l'altra no.
#

# Vero se il testo contiene caratteri che non devono mai raggiungere il
# terminale.
#
# Due famiglie, con motivazioni diverse:
#
# - caratteri di controllo: verificato empiricamente che `xdotool type`
#   sintetizza il keysym Return per un CR e Linefeed per un LF, quindi
#   equivalgono a premere Invio nel prompt in attesa. Rientrano qui anche
#   i separatori di riga Unicode (NEL, LS, PS), che `[[:cntrl:]]` cattura
#   solo con un locale UTF-8: sotto LC_ALL=C, come in un servizio systemd
#   senza LANG ereditato, passerebbero. Il confronto su byte letterali non
#   dipende dal locale.
#
# - override e isolate bidirezionali: non eseguono nulla, ma invertono la
#   resa visiva. L'utente legge "documento.png" e conferma un altro nome.
text_has_unsafe_chars() {
    local value="$1"

    [[ "$value" == *[[:cntrl:]]* ]] && return 0

    # NEL, LINE SEPARATOR, PARAGRAPH SEPARATOR
    case "$value" in
        *$''*|*$' '*|*$' '*) return 0 ;;
    esac

    # LRE, RLE, PDF, LRO, RLO
    case "$value" in
        *$'‪'*|*$'‫'*|*$'‬'*|*$'‭'*|*$'‮'*) return 0 ;;
    esac

    # LRI, RLI, FSI, PDI
    case "$value" in
        *$'⁦'*|*$'⁧'*|*$'⁨'*|*$'⁩'*) return 0 ;;
    esac

    return 1
}
