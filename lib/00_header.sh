#!/usr/bin/env bash
# Le costanti di questo modulo sono consumate dai moduli successivi dopo la
# concatenazione: analizzato in isolamento il file risulta a ShellCheck pieno
# di variabili inutilizzate. La verifica SC2034 resta attiva su tutti gli
# altri moduli, che vengono analizzati singolarmente.
# shellcheck disable=SC2034
#
# paste-image — Incolla immagini dalla clipboard nel terminale attivo
#
# Utilizzo: viene invocato tramite shortcut globale del desktop.
# Legge un'immagine dagli appunti, la salva come file temporaneo
# e digita il path nel terminale attivo.
#

set -euo pipefail

VERSION="2.0.0"

# I valori configurabili hanno i loro default in config_defaults(), nel
# modulo 15_config.sh, insieme al parser e alla validazione.

# I file creati contengono immagini potenzialmente sensibili (screenshot di
# password manager, dati personali). Non affidarsi all'umask ereditato, che
# con il valore comune 022 renderebbe log e directory leggibili da altri
# utenti locali.
umask 077
