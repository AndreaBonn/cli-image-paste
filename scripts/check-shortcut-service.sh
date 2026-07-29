#!/usr/bin/env bash
#
# check-shortcut-service.sh — Verifica il servizio che gestisce gli shortcut
#
# Su GNOME gli shortcut custom sono gestiti da gsd-media-keys: se non è in
# esecuzione il keybinding risulta registrato ma inerte, che è il sintomo
# più comune di "lo shortcut non funziona ma lo script sì".
#
# Invocato da install.sh. Non fallisce mai: segnala e prosegue.
#

set -uo pipefail

echo ""
echo "--- Verifica servizio shortcut GNOME ---"

if pgrep -x gsd-media-keys &>/dev/null; then
    echo "gsd-media-keys: OK (in esecuzione)"
else
    echo "gsd-media-keys non è in esecuzione. Tentativo di avvio..."
    if systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target 2>/dev/null; then
        echo "gsd-media-keys: avviato tramite systemd"
    else
        # Cerca il binario dinamicamente (il path varia tra distro)
        GSD_BIN=""
        if command -v gsd-media-keys &>/dev/null; then
            GSD_BIN="$(command -v gsd-media-keys)"
        else
            for candidate in \
                /usr/libexec/gsd-media-keys \
                /usr/lib/gnome-settings-daemon/gsd-media-keys \
                /usr/lib/gsd-media-keys; do
                if [ -x "$candidate" ]; then
                    GSD_BIN="$candidate"
                    break
                fi
            done
        fi

        if [ -n "$GSD_BIN" ]; then
            "$GSD_BIN" &>/dev/null &
            sleep 1
            if pgrep -x gsd-media-keys &>/dev/null; then
                echo "gsd-media-keys: avviato manualmente ($GSD_BIN)"
            else
                echo "ATTENZIONE: impossibile avviare gsd-media-keys."
                echo "Lo shortcut potrebbe non funzionare. Prova a riavviare la sessione GNOME."
            fi
        else
            echo "ATTENZIONE: gsd-media-keys non trovato nel sistema."
            echo "Lo shortcut potrebbe non funzionare. Prova a riavviare la sessione GNOME."
        fi
    fi
fi
