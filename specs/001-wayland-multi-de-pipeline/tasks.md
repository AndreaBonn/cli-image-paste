# Task: cli-image-paste v2.0

Slug: `001-wayland-multi-de-pipeline` · Piano: [plan.md](plan.md)

Legenda requisito: `F<n>` = feature del backlog originale, `S<n>` = mitigazione di sicurezza, `B<n>` = bloccante, `DoD` = criterio di Definition of Done.

## Stato al 2026-07-29

| Fase | Stato | Dettaglio |
|---|---|---|
| 0 | **completa** | 0.1-0.11 fatti. Gate `code-reviewer` e `security-reviewer` superati, rilievi applicati. L'aggiornamento di `docs/ARCHITECTURE.*` è spostato a 5.3 (nota sotto). |
| 1 | **completa** | `lib/10_env_detect.sh`, `lib/30_delivery.sh`, quattro backend, validazione del path, sezione Wayland nei README bilingui con avviso ydotool. |
| 2 | **completa** | `lib/20_clipboard.sh` e `lib/40_transform.sh` integrati in `90_main.sh`: backend appunti xclip/wl-paste, priorità dei target, file dal file manager senza duplicazione, conversione WebP/GIF/TIFF/BMP/AVIF/SVG con policy ImageMagick dedicata. Docs aggiornate. |
| 3 | **completa** | `lib/60_shortcut.sh` con conversioni pure verso KDE, sway, i3 e Hyprland; `install.sh` è un dispatcher che stampa la riga di config sui window manager e non fallisce più su desktop ignoti; default `<Super>v` su Wayland; flag `--print-shortcut`; dipendenze in `scripts/install-deps.sh`, ora dipendenti dalla sessione. Include 3.3 (scrittura di `kglobalshortcutsrc` con backup e senza duplicare gruppi), 3.5 (rimozione simmetrica) e 3.7 (matrice desktop nei README). Il funzionamento reale su KDE resta non verificato per assenza di hardware, ed è dichiarato nel README. |
| 4 | **in corso** | Fatti 4.1 e 4.2 (resize con rimozione dell'originale nostro e non di quello dell'utente, pulizia degli intermedi per pattern), 4.7 e 4.8 (screenshot come sorgente alternativa, verificato con grim reale su sway). Fatti anche 4.3 e 4.4 (formato adattivo per agente, con discesa nell'albero dei processi). Mancano 4.5 (ring buffer `--last`), 4.9 (annotazione), 4.11 (`--help` e `--doctor`). |
| 5 | non iniziata | Distribuzione, `docs/ARCHITECTURE.*`, `MANUAL_TESTING.md`, naming. |

Suite: 18 file di test, 212 casi, ShellCheck pulito su 45 file, gate dimensionale e di purezza dei moduli attivi.

Bloccanti: **B1 risolto** il 2026-07-29 con misurazione su sway reale. `wl-copy` resta nel process group del chiamante e uccidendolo la selezione va perduta, quindi la consegna via appunti usa `setsid`; `xclip` su X11 si stacca già da solo. **B2 risolto**: `xdotool` sintetizza `Return` per un CR e `Linefeed` per un LF, quindi il rischio S2 è reale e non teorico. **B3 risolto**: il repo resta `cli-image-paste`. Verifica L3 end-to-end su Wayland eseguita, esiti in `doc_progetto/spike-wayland.md`. Resta non verificato KDE, per assenza di hardware.

## Fase 0 — Fondamenta (11h)

| ID | Task | Stima | Dipende da | Requisito | Rischio |
|---|---|---|---|---|---|
| 0.1 | Spike: `wl-copy` sopravvive alla morte dello script lanciato da keybinding gsd? `xdotool type` sintetizza un keysym azionabile per LF/CR? Formato esatto di `x-special/gnome-copied-files`. `magick` contro `convert`. Esito in `doc_progetto/spike-wayland.md` | 75m | — | B1, B2 | alto |
| 0.2 | `scripts/build.sh`: concatenazione di `lib/*.sh` in ordine numerico in `dist/paste-image`, banner "file generato", build riproducibile senza timestamp. `dist/` in `.gitignore` | 60m | — | DoD, ADR-002 | medio |
| 0.3 | `lib/00_header.sh` e `lib/50_store.sh`: estrarre `log()`, `notify()`, rilevamento metodo di notifica, `umask 077` a inizio script. Comportamento invariato | 60m | 0.2 | S7 | basso |
| 0.4 | `lib/15_config.sh`: `config_defaults()`, parser whitelist `config_load()`, precedenza default < file < env < flag, validazione per tipo. Il template di formato ha la sua validazione stretta (whitelist caratteri, un solo `%s`, cap 200) | 105m | 0.3 | F10, S1 | alto |
| 0.5 | Migrazione da v1: rilevare uno script installato con costanti modificate, proporre la scrittura in `~/.config/paste-image/config` | 45m | 0.4 | F10, DoD | medio |
| 0.6 | Rimuovere `prepare_script()` e la `sed` da `tests/test_paste_image.sh`, sostituire con `PASTE_IMAGE_OUTPUT_DIR`. Nuovi helper `source_lib`, `set_session_env`, `make_fake_image` in `test_framework.sh` | 60m | 0.4 | DoD | alto |
| 0.7 | `install.sh` e `uninstall.sh`: build dell'artefatto se assente, copia file singolo invariata, rimozione che preserva il config utente e cancella la capabilities cache | 75m | 0.2 | DoD | medio |
| 0.8 | `tests/test_lib_config.sh`: precedenza, chiave ignota, valore non valido, migrazione v1, tabella di template ostili (newline, doppio `%s`, control char, oltre 200 char) | 90m | 0.4, 0.6 | S1 | basso |
| 0.9 | `tests/test_no_side_effects.sh`: sorgiare ogni modulo in una tmpdir non crea file, non scrive, non esce | 30m | 0.3 | ADR-002 | basso |
| 0.10 | Gate in `run_tests.sh`: fallisce oltre 300 righe per sorgente, ShellCheck esteso a `lib/*.sh` e all'artefatto, conteggio degli skip. Stessi target in `ci.yml` | 45m | 0.2 | DoD | basso |
| 0.11 | `CLAUDE.md` di progetto (assente oggi): stack, convenzioni, regola "i moduli definiscono solo funzioni", come si builda e si testa | 45m | 0.7 | — | basso |

Nota di sequenza: l'aggiornamento di `docs/ARCHITECTURE.md` e `.it.md`, inizialmente parte di 0.11, è spostato al sub-task 5.3. La struttura dei moduli cambia ancora in modo sostanziale nelle Fasi 2, 3 e 4 (sorgenti alternative, pipeline di trasformazione, registrazione shortcut): documentarla adesso significherebbe riscrivere gli stessi diagrammi due volte. `CLAUDE.md` copre nel frattempo le convenzioni operative, che invece servono subito.

Commit: dopo 0.3 (estrazione a comportamento invariato), dopo 0.6 (test disaccoppiati), dopo 0.11 (fondamenta complete).
Gate: `security-reviewer` sul parser di config prima di chiudere la fase.

## Fase 1 — Sessione e consegna (7h 15m)

| ID | Task | Stima | Dipende da | Requisito | Rischio |
|---|---|---|---|---|---|
| 1.1 | `lib/10_env_detect.sh`: `session_type()`, `session_desktop()` normalizzato, tabella delle catene di consegna, capabilities cache con chiave `<sessione>:<desktop>:<versione>` e `--reset-capabilities`. Override per i test | 60m | 0.4 | F1, ADR-001 | medio |
| 1.2 | `delivery_select_backend(sessione, desktop, tool_disponibili)` **pura**, con tabella e override `TYPING_BACKEND` da config | 60m | 1.1, 0.1 | F1 | alto |
| 1.3 | Implementazioni `_delivery_xdotool_send` (attesa su condizione, non sleep fisso), `_delivery_wtype_send`, `_delivery_ydotool_send` con verifica del socket del daemon. Ognuna sotto 30 righe | 75m | 1.2 | F1, S4, ADR-003 | medio |
| 1.4 | `_delivery_clipboard_send` con flag `--clipboard`: `wl-copy` su Wayland, `xclip` staccato su X11, notifica che dichiara la sovrascrittura della clipboard, valutazione della selection PRIMARY | 75m | 1.2 | F11, S8 | alto |
| 1.5 | `path_is_safe()` **pura**: rifiuta control char C0/C1, override bidirezionali Unicode, path non assoluto. Invocata prima di ogni consegna. Degradazione con messaggio utile quando un tool opzionale manca | 45m | 1.3 | S2 | medio |
| 1.6 | `tests/test_lib_delivery.sh`: L1 sulla tabella (8 casi), L1 su `path_is_safe` con tabella di input ostili, L2 sui backend con mock | 90m | 1.4, 1.5 | S2, DoD | basso |
| 1.7 | Sezione Wayland nei README bilingui: tabella di supporto per compositore, limite GNOME dichiarato apertamente, avviso ydotool con blast radius reale e permessi del socket | 45m | 1.6 | S4 | basso |

Commit: dopo 1.3 (typing multi-backend), dopo 1.7 (Wayland completo).

## Fase 2 — Contenuto della clipboard (7h 15m)

| ID | Task | Stima | Dipende da | Requisito | Rischio |
|---|---|---|---|---|---|
| 2.1 | `lib/20_clipboard.sh`: `clipboard_detect_image_mime()`, `clipboard_read_image()`, `clipboard_write_text()` con implementazioni xclip e wl-paste | 60m | 1.1 | F1 | medio |
| 2.2 | `clipboard_pick_target(targets)` **pura**: ordine uri-list > png > jpeg > convertibili > nessuno, con `PREFER_EXISTING_FILE` | 60m | 2.1 | F4, D3 | medio |
| 2.3 | `uri_decode()` e `clipboard_file_from_uri()` pure: solo schema `file://`, percent-decode **prima** della validazione, `path_is_safe()` obbligatoria, verifica file regolare esistente. Gestione di `x-special/gnome-copied-files` (prima riga `copy`/`cut`) e `text/uri-list` (righe `#`, terminatori CRLF) | 90m | 2.2, 1.5 | F4, S2 | alto |
| 2.4 | `lib/40_transform.sh`, step `convert`: rilevamento `magick`/`convert`, `policy.xml` dedicato via `MAGICK_CONFIGURE_PATH`, limiti risorsa su CLI, primo frame per GIF, SVG instradato su `rsvg-convert`, invocazione con argv array. Messaggio distinto fra "ImageMagick assente" e "non sa rasterizzare SVG" | 105m | 2.2 | F3, S3 | alto |
| 2.5 | `tests/test_lib_clipboard.sh` (L1 su parsing, priorità, uri ostili) e `tests/test_lib_transform.sh` (asserzioni sugli argomenti passati a `magick`, presenza dei limiti e della policy) | 90m | 2.4 | S2, S3 | basso |
| 2.6 | Docs bilingui: formati supportati, comportamento con file copiati dal file manager | 30m | 2.5 | F3, F4 | basso |

Commit: dopo 2.3 (file dal file manager), dopo 2.6 (conversione formati).
Gate: `security-reviewer` su S2 e S3 prima di chiudere la fase.

## Fase 3 — Shortcut multi-DE (8h 15m)

| ID | Task | Stima | Dipende da | Requisito | Rischio |
|---|---|---|---|---|---|
| 3.1 | `lib/shortcut.sh`: formato canonico GTK già in uso, convertitori puri `shortcut_gtk_to_kde`, `_to_sway`, `_to_hypr`, `_to_i3`, più `shortcut_validate_gtk` spostata da `install.sh` | 75m | 0.2 | F2 | medio |
| 3.2 | Spostare la logica GNOME in `shortcut_install_gnome()` senza cambiarne il comportamento. `install.sh` diventa un dispatcher su `session_desktop()` e propone `<Super>v` come default su Wayland | 60m | 3.1, 1.1 | F2, ADR-001 | basso |
| 3.3 | `shortcut_install_kde()`: `.desktop` in `~/.local/share/applications`, voce in `kglobalshortcutsrc`, backup prima della scrittura, ricarica via `kglobalaccel` con fallback alle istruzioni manuali | 120m | 3.1 | F2 | alto |
| 3.4 | `shortcut_print_wm(wm, path)` per sway, Hyprland, i3, più il flag `--print-shortcut <wm>`. Ambiente non riconosciuto stampa istruzioni generiche | 60m | 3.1 | F2 | basso |
| 3.5 | Rimozione simmetrica in `uninstall.sh` per KDE. Per i window manager stampa la riga da eliminare a mano | 60m | 3.3 | F2, DoD | medio |
| 3.6 | `tests/test_lib_shortcut.sh` (L1 sui convertitori) e aggiornamento di `test_install.sh` con fixture `kglobalshortcutsrc` | 90m | 3.5 | F2 | medio |
| 3.7 | Docs bilingui: matrice desktop per metodo di registrazione | 45m | 3.6 | F2 | basso |

Commit: dopo 3.2 (GNOME estratto, invariato), dopo 3.7 (multi-DE completo).

## Fase 4 — Pipeline P1 (11h 45m)

| ID | Task | Stima | Dipende da | Requisito | Rischio |
|---|---|---|---|---|---|
| 4.1 | Driver `transform_run` con `mktemp` per ogni intermedio, `trap` centralizzato sull'array dei temporanei, cancellazione immediata degli intermedi a successo, `TRANSFORM_ORDER` readonly. Step `resize`: `image_needs_resize()` pura, `-strip`, `MAX_LONG_SIDE=1568`, `0` disabilita, flag `--no-resize` | 105m | 2.4 | F6, S5, S6, ADR-003 | medio |
| 4.2 | `tests/test_lib_transform.sh` esteso: soglia di resize, immagine già piccola (nessuna invocazione), rimozione metadati, cleanup degli intermedi su fallimento di uno step, politica richiesto contro implicito | 75m | 4.1 | S5, S6 | basso |
| 4.3 | `lib/format.sh`: `format_template_for(processo)` pura, `format_render()` con sostituzione letterale (mai `printf` con template come format string), `format_detect_process()` che scende nell'albero dei processi fino alla foglia | 90m | 1.1, 0.4 | F7, S1 | medio |
| 4.4 | Test formato: i tre agenti, processo sconosciuto, detection impossibile su Wayland, precedenza di `--format`, template ostile respinto | 60m | 4.3 | F7, S1 | basso |
| 4.5 | `lib/50_store.sh` esteso: `history_append`, `history_get(n)`, potatura a 50 voci, stesso idioma `flock` del log. Flag `--last [N]` | 75m | 0.3 | F8, ADR-001 | basso |
| 4.6 | Test storico: append, indice N, file cancellato, potatura, accesso concorrente | 45m | 4.5 | F8 | medio |
| 4.7 | `lib/25_source.sh`: `source_produce()` con `_source_clipboard`, `_source_screenshot` (`gnome-screenshot` > `spectacle` > `grim`+`slurp` > `flameshot` > `maim`+`slop` > `scrot`), `_source_file`, `_source_history`. Flag `--screenshot` | 105m | 1.1, 4.1 | F5, ADR-003 | medio |
| 4.8 | Test screenshot: selezione tool per ambiente, annullamento della selezione, nessun tool disponibile | 45m | 4.7 | F5 | basso |
| 4.9 | Step `annotate` per satty e swappy, flag `--annotate`, fallback all'originale se l'utente annulla, notifica di degrado una volta per sessione e non a ogni esecuzione | 60m | 4.7 | F9, ADR-003 | basso |
| 4.10 | Test annotazione, incluso il percorso interattivo che richiede l'attesa su condizione nella consegna | 45m | 4.9, 1.3 | F9 | medio |
| 4.11 | `--help` completo, `--doctor` che stampa sessione, desktop e catena scelta per le issue, docs bilingui delle feature P1 | 60m | 4.10 | F5-F9 | basso |

Commit: uno per feature (4.2, 4.4, 4.6, 4.8, 4.11).

## Fase 5 — Distribuzione e naming (8h)

| ID | Task | Stima | Dipende da | Requisito | Rischio |
|---|---|---|---|---|---|
| 5.1 | `Makefile` con `install`, `uninstall`, `test`, `lint`, `build`, supporto `PREFIX` e `DESTDIR`. `install.sh` lo usa internamente | 60m | 0.7 | F12 | medio |
| 5.2 | Riscrittura dei README bilingui: nuove feature, matrice di supporto, config file, nota sulla regressione del `curl` diretto | 90m | 4.11 | F12 | basso |
| 5.3 | `docs/MANUAL_TESTING.md` e `.it.md`: matrice ambiente per feature, elenco dei punti L3, istruzioni per sway annidato | 60m | 4.11 | DoD | basso |
| 5.4 | Pacchetto `.deb` in `packaging/debian/` e workflow CI che lo costruisce e lo allega alla release insieme a `dist/paste-image` | 90m | 5.1 | F12 | medio |
| 5.5 | `PKGBUILD` per AUR | 60m | 5.1 | F12 | medio |
| 5.6 | `flake.nix` con `packages.default` e `devShell` | 90m | 5.1 | F12 | alto |
| 5.7 | `CHANGELOG.md` per la 2.0.0 con nota di breaking change, bump `VERSION`, aggiornamento `SECURITY.md` bilingue (parser di config, validazione dei path, policy ImageMagick, avviso ydotool, rimozione metadati) | 60m | 5.2 | S1-S8 | basso |
| 5.8 | **Coerenza naming.** B3 risolto: vince `cli-image-paste`, il repo GitHub non cambia nome. Allineare la directory locale (`paste-images-cli` → `cli-image-paste`) e i riferimenti interni che usano la forma sbagliata (header dei test, banner del runner, `docs/`). Badge, URL e link donazioni restano invariati | 30m | 5.7 | F13 | basso |
