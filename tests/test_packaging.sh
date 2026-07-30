#!/usr/bin/env bash
#
# test_packaging.sh — Pacchetti di distribuzione
#
# La versione è dichiarata in tre posti che nessun linguaggio comune tiene
# insieme: la costante dell'artefatto, il PKGBUILD e la derivazione Nix. Un
# pacchetto che dichiara una versione diversa da quella che installa manda
# fuori strada chi apre una segnalazione, e la divergenza non si vede finché
# qualcuno non scarica il pacchetto sbagliato.
#
# La costruzione del .deb è verificata con un dpkg-deb finto che conserva lo
# staging: così le asserzioni guardano l'albero che verrebbe impacchettato
# anche dove dpkg-deb non esiste, e la suite non dipende dalla distribuzione
# su cui gira.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

BUILD_DEB="$PROJECT_DIR/packaging/debian/build-deb.sh"

artifact_version() {
    sed -n 's/^VERSION="\([^"]*\)".*/\1/p' "$PROJECT_DIR/lib/00_header.sh"
}

# Prepara un dpkg-deb finto che copia lo staging prima che il trap lo
# cancelli, e lancia la build. Stampa niente: le asserzioni leggono la copia.
run_deb_build() {
    export DEB_STAGING_COPY="$TEST_TMPDIR/staging_copy"
    export TMPDIR="$TEST_TMPDIR/tmproot"
    mkdir -p "$TMPDIR"

    # shellcheck disable=SC2016 # Apici singoli intenzionali: corpo del mock
    create_mock "dpkg-deb" 'cp -a "$3" "$DEB_STAGING_COPY"'

    bash "$BUILD_DEB" "$TEST_TMPDIR/out" >/dev/null 2>&1
}

# --- Coerenza della versione ---

test_pkgbuild_version_matches_artifact() {
    local declared
    declared=$(sed -n 's/^pkgver=\(.*\)$/\1/p' "$PROJECT_DIR/packaging/arch/PKGBUILD")

    assert_equals "$(artifact_version)" "$declared" \
        "pkgver del PKGBUILD allineato a VERSION"
}

test_nix_version_matches_artifact() {
    local declared
    declared=$(sed -n 's/^ *version = "\([^"]*\)";.*/\1/p' \
        "$PROJECT_DIR/packaging/nix/package.nix")

    assert_equals "$(artifact_version)" "$declared" \
        "version della derivazione Nix allineata a VERSION"
}

# Il control è un template: una versione scritta dentro verrebbe spedita
# invariata a ogni release successiva, senza che la build se ne accorga.
test_control_keeps_the_placeholder() {
    assert_file_contains "$PROJECT_DIR/packaging/debian/control.in" "@VERSION@" \
        "control.in dichiara il segnaposto e non una versione fissa"
}

# --- Costruzione del .deb ---

test_deb_without_dpkg_deb_says_so() {
    setup_restricted_path

    local output exit_code=0
    output=$(bash "$BUILD_DEB" "$TEST_TMPDIR/out" 2>&1) || exit_code=$?

    assert_exit_code "1" "$exit_code" "senza dpkg-deb la build fallisce"
    assert_contains "$output" "dpkg-deb" "nomina lo strumento mancante"
    assert_contains "$output" "dpkg-dev" "dice come installarlo"
}

test_deb_stages_the_executable_and_docs() {
    run_deb_build

    assert_file_exists "$DEB_STAGING_COPY/usr/bin/paste-image" \
        "l'eseguibile finisce in usr/bin"
    assert_file_exists "$DEB_STAGING_COPY/usr/share/doc/cli-image-paste/LICENSE" \
        "la licenza viene spedita con il pacchetto"
    assert_file_exists "$DEB_STAGING_COPY/usr/share/cli-image-paste/config.example" \
        "l'esempio di configurazione viene spedito"
}

# Un pacchetto la cui directory radice è 0700 chiede a dpkg di stringere i
# permessi di una directory di sistema. mktemp -d crea sempre così, quindi
# senza una correzione esplicita il difetto tornerebbe a ogni build.
test_deb_root_directory_is_traversable() {
    run_deb_build

    local mode
    mode=$(stat -c '%a' "$DEB_STAGING_COPY")

    assert_equals "755" "$mode" "radice dello staging attraversabile da tutti"
}

test_deb_control_comes_from_the_source_version() {
    run_deb_build

    local control="$DEB_STAGING_COPY/DEBIAN/control"
    assert_file_contains "$control" "Version: $(artifact_version)" \
        "il campo Version viene dal sorgente, non da una copia"
    assert_file_contains "$control" "Installed-Size:" \
        "dichiara la dimensione installata"
    assert_file_not_contains "$control" "@VERSION@" \
        "il segnaposto è stato sostituito"
}

# Un pacchetto costruito in CI porterebbe dentro l'utente di quella macchina,
# che sul sistema di destinazione non esiste.
test_deb_build_asks_for_root_ownership() {
    run_deb_build

    assert_mock_called_with "dpkg-deb" "--root-owner-group" \
        "dpkg-deb invocato con --root-owner-group"
    assert_mock_called_with "dpkg-deb" \
        "cli-image-paste_$(artifact_version)_all.deb" \
        "nome del pacchetto con versione e architettura"
}

# Lo staging è una copia completa dell'albero installato. Il trap che lo
# cancella gira al livello superiore, dove una variabile locale a main()
# sarebbe già fuori scope: è un errore che si vede solo guardando /tmp.
test_deb_build_leaves_no_staging_behind() {
    run_deb_build

    local leftovers
    leftovers=$(ls -A "$TMPDIR")

    assert_equals "" "$leftovers" "nessuno staging residuo in TMPDIR"
}

run_test "PKGBUILD: pkgver allineato" test_pkgbuild_version_matches_artifact
run_test "Nix: version allineata" test_nix_version_matches_artifact
run_test "control.in: segnaposto conservato" test_control_keeps_the_placeholder
run_test "deb: senza dpkg-deb lo dichiara" test_deb_without_dpkg_deb_says_so
run_test "deb: eseguibile e docs nello staging" test_deb_stages_the_executable_and_docs
run_test "deb: radice attraversabile" test_deb_root_directory_is_traversable
run_test "deb: versione dal sorgente" test_deb_control_comes_from_the_source_version
run_test "deb: proprietà root richiesta" test_deb_build_asks_for_root_ownership
run_test "deb: nessuno staging residuo" test_deb_build_leaves_no_staging_behind

print_summary "test_packaging.sh"
