#!/usr/bin/env bash
#
# build-deb.sh — Costruisce il pacchetto .deb binario
#
# Non c'è un albero debian/ con debhelper perché l'obiettivo è un file
# scaricabile dalla pagina delle release, non l'inclusione nell'archivio
# Debian. dpkg-deb sullo staging che il Makefile sa già produrre evita di
# descrivere l'installazione una seconda volta, che è esattamente ciò che il
# Makefile esiste per impedire.
#
# Uso: bash packaging/debian/build-deb.sh [directory di output]
#

set -euo pipefail

_SELF="${BASH_SOURCE[0]}"
_SELF_DIR="${_SELF%/*}"
[ "$_SELF_DIR" = "$_SELF" ] && _SELF_DIR="."
PROJECT_DIR="$(cd "$_SELF_DIR/../.." && pwd)"
PACKAGING_DIR="$PROJECT_DIR/packaging/debian"

OUTPUT_DIR="${1:-$PROJECT_DIR/dist}"
PACKAGE_NAME="cli-image-paste"

# Globale e non locale a main(): il trap che la cancella viene eseguito al
# livello superiore, dove una variabile locale è già uscita di scope. Con
# set -u questo si manifesta come un errore all'uscita e uno staging che
# resta su disco, cioè il contrario di quello che il trap doveva garantire.
STAGE_DIR=""
cleanup_stage() {
    [ -n "$STAGE_DIR" ] && rm -rf "$STAGE_DIR"
}

# La versione ha una sola fonte, la costante dell'artefatto. Un secondo posto
# in cui scriverla è un secondo posto in cui dimenticarsi di aggiornarla, e un
# pacchetto che dichiara una versione diversa da quella che installa manda
# fuori strada chi apre una segnalazione.
read_version() {
    local version
    version=$(sed -n 's/^VERSION="\([^"]*\)".*/\1/p' "$PROJECT_DIR/lib/00_header.sh")

    if [ -z "$version" ]; then
        echo "ERRORE: VERSION non trovata in lib/00_header.sh" >&2
        return 1
    fi

    echo "$version"
}

# Il campo Installed-Size è in kibibyte ed è atteso dai gestori di pacchetti
# per stimare lo spazio: senza, apt mostra zero e l'utente non sa cosa sta
# installando.
installed_size_kib() {
    local stage="$1"
    du -ks "$stage" | cut -f1
}

write_control() {
    local stage="$1" version="$2"
    local control_dir="$stage/DEBIAN"

    mkdir -p "$control_dir"
    sed "s/@VERSION@/$version/" "$PACKAGING_DIR/control.in" > "$control_dir/control"
    printf 'Installed-Size: %s\n' "$(installed_size_kib "$stage")" >> "$control_dir/control"
}

require_dpkg_deb() {
    if ! command -v dpkg-deb &>/dev/null; then
        echo "ERRORE: dpkg-deb non disponibile, impossibile costruire il pacchetto." >&2
        echo "Su Debian e derivate: sudo apt install dpkg-dev" >&2
        return 1
    fi
}

main() {
    local version output

    require_dpkg_deb

    version=$(read_version)

    # Lo staging contiene una copia completa dell'albero installato: lasciarlo
    # in giro a ogni build riempie /tmp senza che nessuno se ne accorga.
    STAGE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/cli-image-paste-deb-XXXXXX")
    trap cleanup_stage EXIT

    # mktemp crea sempre a 0700, e quel modo finisce nell'archivio come
    # permesso della directory radice del pacchetto. Un .deb che spedisce una
    # radice non leggibile è un pacchetto che chiede a dpkg di stringere i
    # permessi di una directory di sistema.
    chmod 755 "$STAGE_DIR"

    make -C "$PROJECT_DIR" install PREFIX=/usr DESTDIR="$STAGE_DIR" >/dev/null

    write_control "$STAGE_DIR" "$version"

    mkdir -p "$OUTPUT_DIR"
    output="$OUTPUT_DIR/${PACKAGE_NAME}_${version}_all.deb"

    # --root-owner-group: senza, i file dentro il pacchetto appartengono
    # all'utente che ha lanciato la build, che su una macchina di CI è un
    # utente che sul sistema di destinazione non esiste.
    dpkg-deb --build --root-owner-group "$STAGE_DIR" "$output" >/dev/null

    echo "Pacchetto costruito: $output"
}

main
