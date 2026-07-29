#!/usr/bin/env bash
#
# test_shortcut_kde.sh — Registrazione della scorciatoia su KDE
#
# Il file kglobalshortcutsrc contiene le scorciatoie di ogni applicazione
# dell'utente: la verifica più importante è che il resto del file resti
# intatto. Il funzionamento reale su KDE non è verificabile qui, manca
# l'hardware: quello che questi test provano è il contenuto prodotto.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=test_framework.sh
source "$SCRIPT_DIR/test_framework.sh"

KDE_SCRIPT="$PROJECT_DIR/scripts/shortcut-kde.sh"

# Fixture: un file di scorciatoie con voci di altre applicazioni
write_existing_shortcuts() {
    mkdir -p "$FAKE_HOME/.config"
    cat > "$FAKE_HOME/.config/kglobalshortcutsrc" <<'EOF'
[ActivityManager]
_k_friendly_name=Attività
switch-to-activity=none,none,Passa all'attività

[kwin]
_k_friendly_name=KWin
Switch Window Down=Meta+Alt+Down,Meta+Alt+Down,Finestra sotto
Show Desktop=Meta+D,none,Mostra il desktop
EOF
}

shortcuts_file() {
    echo "$FAKE_HOME/.config/kglobalshortcutsrc"
}

run_kde() {
    XDG_CONFIG_HOME="$FAKE_HOME/.config" \
    XDG_DATA_HOME="$FAKE_HOME/.local/share" \
        bash "$KDE_SCRIPT" "$@" 2>&1
}

# --- Installazione ---

test_group_is_written() {
    write_existing_shortcuts
    run_kde install "<Control><Shift>v" "/home/utente/.local/bin/paste-image" >/dev/null

    local file
    file=$(shortcuts_file)
    assert_file_contains "$file" "[paste-image.desktop]" "gruppo creato"
    assert_file_contains "$file" "_launch=Ctrl+Shift+V,none,Paste Image" \
        "riga _launch con la scorciatoia convertita"
    assert_file_contains "$file" "_k_friendly_name=Paste Image" "nome leggibile"
}

# Il file contiene le scorciatoie di tutto il desktop: perderle sarebbe un
# danno sproporzionato rispetto alla funzione che stiamo aggiungendo.
test_other_applications_untouched() {
    write_existing_shortcuts
    run_kde install "<Super>v" "/opt/paste-image" >/dev/null

    local file
    file=$(shortcuts_file)
    assert_file_contains "$file" "[ActivityManager]" "gruppo di altra app conservato"
    assert_file_contains "$file" "[kwin]" "gruppo kwin conservato"
    assert_file_contains "$file" "Show Desktop=Meta+D,none,Mostra il desktop" \
        "riga di kwin intatta"
    assert_file_contains "$file" "switch-to-activity=none,none,Passa all'attività" \
        "riga con accenti intatta"
}

test_desktop_entry_created() {
    write_existing_shortcuts
    run_kde install "<Super>v" "/opt/paste-image" >/dev/null

    local entry="$FAKE_HOME/.local/share/applications/paste-image.desktop"
    assert_file_exists "$entry" "voce desktop creata"
    assert_file_contains "$entry" "Exec=/opt/paste-image" "comando corretto"
    assert_file_contains "$entry" "NoDisplay=true" "non compare nel menu applicazioni"
}

test_backup_is_taken() {
    write_existing_shortcuts
    run_kde install "<Super>v" "/opt/paste-image" >/dev/null

    assert_file_exists "$(shortcuts_file).paste-image-backup" "backup creato"
    assert_file_contains "$(shortcuts_file).paste-image-backup" "[kwin]" \
        "il backup contiene lo stato precedente"
}

# Reinstallare non deve accumulare gruppi duplicati: KDE leggerebbe il primo
# e la modifica sembrerebbe non avere effetto.
test_reinstall_does_not_duplicate() {
    write_existing_shortcuts
    run_kde install "<Super>v" "/opt/paste-image" >/dev/null
    run_kde install "<Control><Alt>v" "/opt/paste-image" >/dev/null

    local count
    count=$(grep -c '^\[paste-image.desktop\]$' "$(shortcuts_file)")
    assert_equals "1" "$count" "un solo gruppo dopo due installazioni"
    assert_file_contains "$(shortcuts_file)" "_launch=Ctrl+Alt+V" "vince la scorciatoia nuova"
    assert_file_not_contains "$(shortcuts_file)" "_launch=Meta+V" "quella vecchia è sparita"
}

test_missing_file_is_created() {
    mkdir -p "$FAKE_HOME/.config"
    run_kde install "<Super>v" "/opt/paste-image" >/dev/null
    assert_file_exists "$(shortcuts_file)" "file creato quando assente"
    assert_file_contains "$(shortcuts_file)" "[paste-image.desktop]" "gruppo presente"
}

test_invalid_shortcut_refused() {
    write_existing_shortcuts
    local exit_code=0
    run_kde install "Control+v" "/opt/paste-image" >/dev/null 2>&1 || exit_code=$?

    if [ "$exit_code" -eq 0 ]; then
        _test_fail "scorciatoia in formato non canonico accettata"
    fi
    assert_file_not_contains "$(shortcuts_file)" "paste-image" "nulla scritto nel file"
}

# --- Rimozione ---

test_remove_leaves_others_intact() {
    write_existing_shortcuts
    run_kde install "<Super>v" "/opt/paste-image" >/dev/null
    run_kde remove >/dev/null

    local file
    file=$(shortcuts_file)
    assert_file_not_contains "$file" "paste-image" "gruppo rimosso"
    assert_file_contains "$file" "[kwin]" "kwin conservato"
    assert_file_contains "$file" "[ActivityManager]" "ActivityManager conservato"
    assert_file_not_exists "$FAKE_HOME/.local/share/applications/paste-image.desktop" \
        "voce desktop rimossa"
    assert_file_not_exists "${file}.paste-image-backup" "backup ripulito"
}

test_remove_without_install_is_harmless() {
    write_existing_shortcuts
    local exit_code=0
    run_kde remove >/dev/null 2>&1 || exit_code=$?

    assert_exit_code "0" "$exit_code" "nessun errore senza installazione precedente"
    assert_file_contains "$(shortcuts_file)" "[kwin]" "file lasciato intatto"
}

test_remove_without_file_is_harmless() {
    local exit_code=0
    run_kde remove >/dev/null 2>&1 || exit_code=$?
    assert_exit_code "0" "$exit_code" "nessun errore senza file di scorciatoie"
}

# --- Ricarica del servizio ---

# Senza ricarica il file è scritto ma la scorciatoia resta inerte fino al
# prossimo accesso: se il servizio non risponde va detto, non taciuto.
test_missing_reload_tool_is_reported() {
    write_existing_shortcuts
    setup_restricted_path

    local output
    output=$(run_kde install "<Super>v" "/opt/paste-image")
    assert_contains "$output" "prossimo accesso" "spiega quando sarà attiva"
    assert_contains "$output" "Scorciatoie" "indica dove impostarla a mano"
}

run_test "Gruppo scritto nel file" test_group_is_written
run_test "Altre applicazioni intatte" test_other_applications_untouched
run_test "Voce desktop creata" test_desktop_entry_created
run_test "Backup del file" test_backup_is_taken
run_test "Reinstallazione non duplica" test_reinstall_does_not_duplicate
run_test "File assente viene creato" test_missing_file_is_created
run_test "Scorciatoia non valida rifiutata" test_invalid_shortcut_refused
run_test "Rimozione lascia intatto il resto" test_remove_leaves_others_intact
run_test "Rimozione senza installazione" test_remove_without_install_is_harmless
run_test "Rimozione senza file" test_remove_without_file_is_harmless
run_test "Ricarica non disponibile: lo dichiara" test_missing_reload_tool_is_reported

print_summary "test_shortcut_kde.sh"
