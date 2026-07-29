# Piano: cli-image-paste v2.0 — Wayland, multi-DE, pipeline immagine

**Slug:** `001-wayland-multi-de-pipeline`
**Creato:** 2026-07-29
**Stato:** approvato in attesa di implementazione
**Versione target:** 2.0.0 (breaking change sul modello di installazione)

## Obiettivo

Portare `paste-image` da utility single-file X11/GNOME a strumento multi-sessione (X11 + Wayland) e multi-desktop, con pipeline di trasformazione immagine, output adattivo per coding assistant e configurazione utente persistente.

Il vincolo strutturale non sono le feature: sono i limiti di 300 righe per file e 30 per funzione applicati a Bash, che impongono la modularizzazione e cambiano il modello di installazione.

## Definition of Done

La macchina di sviluppo (Ubuntu, GNOME, X11) non può provare tutti gli ambienti target. Il livello di verifica è parte della DoD, non una nota a margine.

- **L1 — unit puro:** la funzione decisionale viene sorgiata dal test e la sua stringa di output asserita. Nessun processo esterno, gira in CI.
- **L2 — integrazione con mock:** binari finti su `PATH` (`wl-paste`, `wtype`, `magick`, `spectacle`, `grim`, `satty`) più ambiente forzato (`XDG_SESSION_TYPE`, `XDG_CURRENT_DESKTOP`). Gira in CI.
- **L3 — manuale su hardware reale:** checklist in `docs/MANUAL_TESTING.md`. Ciò che resta non verificato viene dichiarato, non nascosto.

Sblocco per L3: **sway gira annidato dentro X11** (`WLR_BACKENDS=x11 sway`), quindi `wl-paste`, `wtype`, `grim` e `slurp` reali sono provabili sulla macchina di sviluppo senza VM. GNOME Wayland è provabile con logout e cambio sessione al login. Solo KDE richiede una VM o un tester esterno.

### Fondamenta
- [ ] Ogni sorgente in `lib/` sotto 300 righe, ogni funzione sotto 30. Il runner fallisce se un file sfora (gate eseguibile, L1).
- [ ] `PASTE_IMAGE_OUTPUT_DIR=/tmp/x paste-image` scrive in `/tmp/x`. Nessun test usa più `sed` sul sorgente (L2).
- [ ] Sorgiare qualunque `lib/*.sh` non crea file, non scrive log, non esce: i moduli definiscono solo funzioni e costanti (L1, test dedicato).
- [ ] `scripts/build.sh` produce `dist/paste-image` funzionante e riproducibile: due build consecutive danno file identici (L1).
- [ ] `~/.config/paste-image/config` con `MAX_LONG_SIDE=800` produce immagini a lato lungo 800. Reinstallare non cancella il file (L2 + L3).
- [ ] Upgrade da v1: se lo script installato ha costanti modificate, `install.sh` propone la migrazione nel config file e la applica (L2 con fixture).
- [ ] Precedenza dimostrata da test: default < config file < variabile d'ambiente < flag CLI (L1).

### P0 — Wayland, multi-DE, formati
- [ ] Con `XDG_SESSION_TYPE=wayland` lo script invoca `wl-paste`, mai `xclip`. Con `x11` il contrario. Verificato leggendo `MOCK_CALL_LOG` (L2).
- [ ] `delivery_select_backend` restituisce: `xdotool` per x11; `clipboard` per wayland+GNOME; `wtype` per wayland+sway/Hyprland con wtype presente; `ydotool` solo se richiesto esplicitamente in config; `clipboard` quando nulla è disponibile (L1, tabella di casi).
- [ ] Su GNOME Wayland reale: premendo lo shortcut il path finisce negli appunti e la notifica dice esplicitamente di premere Ctrl+V (L3).
- [ ] Clipboard con `image/webp` e ImageMagick presente produce un PNG valido riconosciuto da `file`. Senza ImageMagick la notifica nomina formato e pacchetto, exit 1 (L2).
- [ ] GIF animata: estratto il primo frame, output PNG singolo (L2 sugli argomenti passati a `magick`, L3 con ImageMagick reale).
- [ ] Copiando un file da Nautilus (`x-special/gnome-copied-files`) o Dolphin (`text/uri-list`): viene digitato il path esistente e **nessun** nuovo file compare in `OUTPUT_DIR` (L2 + L3).
- [ ] `text/uri-list` con URL non-`file://` non viene trattato come file (L1).
- [ ] Percent-encoding decodificato prima della validazione; path con newline, CR, control char C0/C1 o override bidirezionali Unicode viene **rifiutato**, non digitato (L1, tabella di casi ostili).
- [ ] `install.sh` su KDE scrive il gruppo `[paste-image.desktop]` in `~/.config/kglobalshortcutsrc` e crea il `.desktop`. Se `kglobalaccel` non risponde stampa le istruzioni manuali senza fallire (L2 con fixture). Il funzionamento reale dello shortcut su KDE resta **L3 delegato, dichiarato non verificato in questo ciclo**.
- [ ] `install.sh` su sway/Hyprland/i3 non tenta scritture: stampa la riga di config esatta con path assoluto. `paste-image --print-shortcut sway|hyprland|i3` la riproduce (L1 + L2).

### P1 — Differenziazione
- [ ] Immagine 4000x3000 con `MAX_LONG_SIDE=1568` produce 1568x1176. Immagine 800x600 resta invariata e `magick` non viene invocato (L2, L3 con `identify`).
- [ ] I metadati EXIF vengono rimossi dall'output (L3 con `exiftool`).
- [ ] Con `claude` in foreground l'output è il path nudo, con `aider` è `/add <path>`, con `gemini` è `@<path>`. Processo sconosciuto o detection impossibile produce il path nudo (L1 sulla mappa, L2 sul rilevamento).
- [ ] `--format` vince su detection e config. Un template con più di un `%s`, con control char o oltre 200 caratteri viene rifiutato al caricamento del config (L1).
- [ ] `paste-image --last` ridigita il path dell'ultima immagine, `--last 3` la terzultima. File non più esistente produce notifica ed exit 1. Storico potato a 50 voci (L2).
- [ ] `--screenshot` invoca il tool giusto per ambiente e consegna il path catturato. Selezione annullata: nessun file creato, exit 0 con notifica (L2 + L3 su GNOME e su sway annidato).
- [ ] `--annotate` passa il file per satty/swappy. Utente che annulla ottiene l'originale con notifica (L2).
- [ ] Ordine della pipeline `convert → resize → annotate` non configurabile e coperto da test (L1).

### P2 — Igiene e distribuzione
- [ ] `--clipboard` mette il path negli appunti senza simulare tastiera. Su X11 il contenuto sopravvive all'uscita del processo (L3).
- [ ] `make install PREFIX=/usr DESTDIR=/tmp/pkg` popola l'albero corretto senza toccare `$HOME` (L2).
- [ ] `.deb` installabile e rimovibile senza residui, PKGBUILD supera `namcap`, `nix build` produce un eseguibile funzionante (L3).
- [ ] `bash install.sh` seguito da `bash uninstall.sh` lascia il sistema pulito, con la sola eccezione voluta del config utente.
- [ ] Il runner stampa il conteggio dei test saltati: nessun verde ottenuto con skip taciuti.

## Assunzioni

- Bash 4.4+. Ubuntu 22.04+, Fedora 38+, Arch corrente.
- Convenzioni invariate: commenti e messaggi utente in italiano, docs bilingui, sezioni `# --- N. Titolo ---`, `set -euo pipefail`, ShellCheck zero warning.
- Tutte le nuove dipendenze sono **opzionali**: la loro assenza degrada la feature con un messaggio utile. Restano obbligatori solo un backend di lettura clipboard e uno di consegna.
- Target di conversione unico: PNG.
- 1568px come lato lungo di default è il punto di ottimo per il tokenizer di immagini di Claude, resta configurabile.
- La versione diventa 2.0.0: il modello di installazione cambia, è un breaking change per chi ha personalizzato lo script installato.

### Bloccanti dichiarati

- **B1 (spike, apre la Fase 0):** `wl-copy` mantiene la selezione tramite un processo che si stacca dal chiamante. Va verificato che sopravviva alla terminazione dello script quando questo è lanciato da un keybinding `gsd-media-keys` (il process group potrebbe essere terminato). Se non sopravvive serve `wl-copy --foreground` con `setsid` oppure `wl-clipboard-persist`. È il singolo punto che può invalidare la modalità di consegna primaria su GNOME Wayland.
- **B2 (spike, stesso blocco):** `xdotool type` sintetizza un keysym azionabile per LF/CR? La risposta cambia la severità del rischio S1 ma **non** la mitigazione, che va implementata comunque.
- **B3 (decisione utente, sub-task 5.8):** il rename tocca remote GitHub, badge CI, URL nei README bilingui e nel link donazioni. Serve conferma esplicita su quale nome vince fra `paste-image` e `cli-image-paste`. Nulla si tocca prima.

## Decisioni architetturali

### ADR-001 — Due porte separate, non un backend unico

Lo script attuale confonde due assi ortogonali: **leggere** la clipboard e **consegnare** il path. Su GNOME Wayland il primo funziona benissimo (`wl-paste`), solo il secondo è rotto. Un unico backend X11-vs-Wayland modellerebbe male il problema e moltiplicherebbe i rami condizionali a ogni punto d'uso.

Due porte indipendenti, ciascuna con la propria selezione:

- `lib/20_clipboard.sh` — `clipboard_detect_image_mime()`, `clipboard_read_image <mime> <dest>`, `clipboard_write_text <text>`. Implementazioni `_clipboard_x11_*` e `_clipboard_wl_*`.
- `lib/30_delivery.sh` — `delivery_send_path <path>`, `delivery_hint()`. Implementazioni `_delivery_xdotool_*`, `_delivery_wtype_*`, `_delivery_ydotool_*`, `_delivery_clipboard_*`.

`delivery_hint()` non è cosmetico: è ciò che impedisce a un `if modo == clipboard` di ricomparire dentro `notify()`. La modalità possiede il proprio testo.

**Focus e finestra attiva non sono nell'interfaccia.** `getactivewindow` e `windowfocus` esistono solo su X11 e solo per la consegna via xdotool. Se fossero operazioni della porta, ogni implementazione Wayland avrebbe stub no-op, cioè stati illegali rappresentabili. Restano variabili private di `_delivery_xdotool_send`.

**Dispatch con `case` esplicito, non name-mangling.** `"_clipboard_${IMPL}_read"` è respinto: ShellCheck perde ogni capacità di verifica e `grep` non trova più il chiamante.

**Su GNOME Wayland la consegna via clipboard è primaria, non un fallback.** Un fallback si scopre fallendo, e `wtype` fallisce *dopo* che il file è stato creato e la clipboard consumata, con un errore che l'utente vede come "non è successo niente". `ydotool` non viene mai probato automaticamente: entra in catena solo se scritto nel config.

Tabella delle catene di consegna, dati e non codice, in `lib/10_env_detect.sh`:

| Sessione | Desktop | Catena |
|---|---|---|
| x11 | qualunque | `xdotool`, `clipboard` |
| wayland | GNOME, Unity | `clipboard` |
| wayland | sway, Hyprland, river, wlroots | `wtype`, `clipboard` |
| wayland | KDE, altri | `wtype`, `clipboard` |
| assente, tty | — | `clipboard` |

**Rilevamento a runtime, cache solo del negativo appreso.** Leggere le variabili d'ambiente e usare `command -v` costa meno di un millisecondo, contro i due fork di `xclip` e i 100 ms di `TYPING_DELAY` già presenti: non c'è niente da risparmiare e cachare comprerebbe staleness gratis. Si cacha un solo fatto: quando `wtype` fallisce davvero, una riga in `${XDG_STATE_HOME}/paste-image/capabilities`. La chiave contiene `<session_type>:<desktop>:<versione>`, quindi cambiare sessione cambia la chiave e non serve TTL. `--reset-capabilities` per l'aggiornamento del compositore.

**Due trappole che questa decisione crea e che vanno chiuse contestualmente:**

1. **Collisione di shortcut.** Il default attuale `<Control><Shift>v` è anche l'incolla del terminale. Con consegna via clipboard l'utente premerebbe lo stesso chord per invocare il tool e per incollare: la seconda pressione ri-esegue paste-image, che ora trova testo e notifica "non contiene un'immagine". Su sessione Wayland l'installer deve proporre un default diverso (`<Super>v`), quindi `install.sh` deve usare lo stesso `lib/10_env_detect.sh` dello script principale.
2. **La consegna via clipboard distrugge la sorgente.** Scrivere il path negli appunti sovrascrive l'immagine e rende il retry impossibile. Questo trasforma il ring buffer da nice-to-have a mitigazione di una conseguenza diretta di questo ADR.

### ADR-002 — Sorgenti modulari, artefatto singolo generato a build time

Tre opzioni: monolite oltre i 300 righe; `lib/*.sh` sorgiati a runtime da `~/.local/lib/`; sorgenti modulari con concatenazione in `dist/paste-image` a build time.

**Scelta: la terza.** Il criterio decisivo non è estetico. Sourcing a runtime e build time hanno lo stesso beneficio sul sorgente, ma il sourcing a runtime *degrada la proprietà che rende questo tool adottabile*, cioè un singolo file senza residui, mentre la build la preserva. Uno step di build è un costo pagato una volta da chi sviluppa; N file installati sono un costo pagato per sempre da ogni utente che disinstalla. In più, con moduli installati una disinstallazione parziale o un rename lasciano orfani che vengono sorgiati alla prossima esecuzione: un modulo vecchio che sopravvive è peggio di uno mancante, perché fallisce in modo incoerente e silenzioso.

Contro-argomento del planner, registrato e accettato come costo: il file installato diverge dal sorgente, quindi il debug sulla macchina utente avviene su codice generato. Mitigato dal banner in testa all'artefatto e dall'ordine dei moduli visibile nei numeri di prefisso.

Layout:

```
lib/00_header.sh      shebang, set -euo pipefail, VERSION, costanti
lib/10_env_detect.sh  sessione, desktop, tabella catene, capabilities cache
lib/15_config.sh      parser config utente + override da env
lib/20_clipboard.sh   porta sorgente clipboard + impl x11/wl
lib/25_source.sh      sorgenti alternative: screenshot, file, ring buffer
lib/30_delivery.sh    porta consegna + 4 impl
lib/40_transform.sh   pipeline di trasformazione
lib/50_store.sh       ring buffer, cleanup, logging
lib/90_main.sh        parsing argomenti, orchestrazione, unico modulo con codice top-level
```

Regole di modulo, sono ciò che rende la concatenazione sicura:

1. Solo `00_header.sh` ha shebang e `set -euo pipefail`. Gli altri iniziano con `# shellcheck shell=bash`.
2. Nessun modulo tranne `90_main.sh` esegue codice a source time: solo definizioni di funzione e costanti `readonly`. Precondizione perché un test possa sorgiare un modulo senza effetti collaterali.
3. Nessun `exit` fuori da `90_main.sh`. Le funzioni ritornano exit code, la decisione di uscire è dell'orchestratore.
4. Prefisso `_` per le funzioni private, nome nudo per l'interfaccia pubblica.

`scripts/build.sh` concatena in ordine numerico in `dist/paste-image` con banner "file generato, non editare" e nessun timestamp, così un diff fra due build è significativo. `dist/` non va committato: è in `.gitignore`, allegato alla GitHub Release, e `install.sh` lo costruisce se manca.

Regressione reale accettata: chi oggi fa `curl` del file `paste-image` da main non può più, perché su main non esiste più un file eseguibile. Va documentato nel README e mitigato dall'asset di release.

### ADR-003 — Sorgente, trasformazione, consegna come tre stadi

Le quattro feature "screenshot, conversione, resize, annotazione" sono tre cose diverse:

- **screenshot** non è una trasformazione, è una **sorgente alternativa** alla clipboard, come lo sono un path da CLI e una voce del ring buffer;
- **conversione e resize** sono trasformazioni pure file → file;
- **annotazione** è una trasformazione ma interattiva e bloccante, con proprietà distinte: durata illimitata, ruba il focus, l'utente può annullare.

```
SOURCE  ->  TRANSFORM*  ->  [STORE]  ->  DELIVERY
```

Nominare gli stadi impedisce che "screenshot" venga infilato come step di pipeline e che il ring buffer venga infilato come trasformazione.

**Contratto di uno step:** `_step_<nome> <in> <out>` con exit code, più `_step_<nome>_requires` che stampa binario e pacchetto suggerito. Lo step non conosce la pipeline, non alloca temporanei, non notifica, non decide se saltare sé stesso. Il driver `transform_run <in>` alloca i temporanei, fa lo swap del file corrente a ogni step riuscito e stampa il path finale.

**La politica di degradazione dipende da come lo step è entrato in catena, non dallo step:**

| Origine | Dipendenza mancante o step fallito | Perché |
|---|---|---|
| **richiesto** (`--annotate` da riga di comando) | errore esplicito, exit non-zero, notifica con comando di installazione | ignorare un flag appena scritto dall'utente è il peggior esito possibile |
| **implicito** (resize da policy in config) | salta, notifica il degrado una volta, prosegue col file precedente | è un miglioramento accessorio, non la ragione dell'invocazione |

Unica eccezione, va nominata: la **conversione da MIME non supportato**. Se la clipboard contiene `image/bmp`, senza ImageMagick non c'è nessun file utile da consegnare. Non è degradazione, è fallimento della sorgente: va gestita nello stadio SOURCE, con un errore che dice cosa installare.

**Invariante del driver:** alla fine di `transform_run` esiste sempre un path valido. Nessun percorso, incluso il fallimento di ogni step, può produrre l'assenza di un file quando la sorgente ne ha prodotto uno.

**Ordine `convert → resize → annotate`, non configurabile.** `convert` per primo perché gli altri tool potrebbero non leggere il formato esotico. `resize` prima di `annotate` perché annotare e poi rimpicciolire rende illeggibili le annotazioni, e il contrario produce un artefatto rotto che l'utente non può prevedere. `annotate` per ultimo perché è l'unico interattivo: tutto ciò che è automatico deve essere finito quando l'utente prende il controllo. Costante `readonly TRANSFORM_ORDER=(convert resize annotate)`, la config può solo abilitare o disabilitare le voci.

**Lo step interattivo impone due invarianti di sequenza:**

1. La finestra di destinazione va catturata **prima** della pipeline. Oggi la cattura è già in cima allo script: la posizione è giusta per caso e va protetta con un commento esplicito, perché è l'unico momento in cui la finestra focalizzata è ancora il terminale. Se `satty` apre una finestra, ogni cattura successiva prende l'annotatore.
2. `TYPING_DELAY=0.1` non basta dopo uno step interattivo. Chiudere un annotatore e restituire il focus può richiedere molto più di 100 ms e il ritardo non è stimabile: è una race che passa in sviluppo e fallisce su macchina carica, digitando il path nella finestra sbagliata. `_delivery_xdotool_send` deve **attendere la condizione** (polling di `getactivewindow` finché coincide con il target, con timeout ed errore chiaro), non dormire un tempo fisso. Lo sleep costante resta accettabile solo nel percorso senza step interattivi.

## Disambiguazioni risolte

| # | Questione | Scelta | Motivo |
|---|---|---|---|
| D1 | Come si supera il limite di 300 righe | Build-time concat (ADR-002) | Preserva l'installazione a file singolo e la disinstallazione senza residui |
| D2 | Formato del config file | Parser con whitelist di chiavi, mai `source` | `source` di un file di config è esecuzione di codice arbitrario a ogni pressione dello shortcut, incoerente con un progetto che pubblica un SECURITY.md |
| D3 | `text/uri-list` contro `image/png` quando la clipboard ha entrambi | Vince il file esistente, con `PREFER_EXISTING_FILE=0` per tornare indietro | È il caso d'uso della feature, e duplicare un file da 8 MB già su disco è lo spreco da evitare. Solo URI `file://` verso file regolari esistenti |
| D4 | Comportamento su GNOME Wayland | Clipboard primaria con notifica esplicativa, più suggerimento una-tantum su ydotool nel log | Il fallback silenzioso è un fallimento mascherato; l'errore che chiede ydotool rende il tool inutilizzabile per la fetta più grande della base utenti |
| D5 | Fallback della detection di formato | Path nudo di fabbrica, `DEFAULT_FORMAT` per chi usa sempre lo stesso agente | Il path nudo è sempre incollabile e non corrompe il prompt. Su Wayland la detection non è possibile, quindi questo ramo è il default reale |

## Rischi di sicurezza e mitigazioni

Esito della review preventiva. Ogni voce è tracciata a un sub-task.

| # | Superficie | Severità | Scenario | Mitigazione | Sub-task |
|---|---|---|---|---|---|
| S1 | Template di formato nel config digitato nel terminale | **Critical** | Preset di configurazione condiviso su gist o dotfiles repo contenente `template="/add %s\nrm -rf ~"`. L'utente lo copia fidandosi della fonte, e da quel momento **ogni** paste esegue il payload. Persistente, a differenza di S2 che è one-shot. Condividere snippet di config è pratica comune fra sviluppatori: il vettore di ingegneria sociale è credibile | Whitelist di caratteri stretta sul valore (alfanumerico più `/@.-_ %`), rifiuto di control char, esattamente una occorrenza di `%s`, cap di 200 caratteri. Sostituzione con `${template//%s/$path}`, **mai** `printf "$template" "$path"` che userebbe input esterno come format string | 0.4, 4.3 |
| S2 | Path da `uri-list` digitato nel terminale | **High** | File con newline nel nome (legale su Linux) estratto da uno zip o da un repo clonato, copiato via file manager pensando sia uno screenshot. Il tool digita il path in un prompt shell idle: il newline equivale a premere Invio a metà stringa ed esegue ciò che precede. Il tool non preme Invio, quindi `;` e backtick da soli restano inerti: il vettore reale è **solo** newline e CR. Rischio secondario: override bidirezionali Unicode fanno apparire innocuo un path diverso da quello reale, vanificando il controllo visivo dell'utente prima di premere Invio | Percent-decode **prima** della validazione, poi whitelist: path assoluto, niente C0/C1, niente U+202A-U+202E e U+2066-U+2069. Path che non passa viene rifiutato e notificato, non digitato. Schema diverso da `file://` rifiutato esplicitamente | 2.3, 1.5 |
| S3 | ImageMagick su input non fidato | **High** | ImageTragick (CVE-2016-3714), decompression bomb, SVG con riferimenti esterni. Nota di realismo: "tasto destro, copia immagine" da browser **non** è il vettore primario, perché i browser ri-codificano in bitmap PNG passando per un decoder sandboxato. Il vettore reale è lo stesso di S2: un file `.svg` o `.tiff` ricevuto e copiato via file manager, che la conversione poi processa | `policy.xml` dedicato via `MAGICK_CONFIGURE_PATH` con `rights="none"` su `MSL,MVG,TEXT,SHOW,WIN,PLT,EPHEMERAL,URL,HTTPS,FTP`: non fidarsi della policy di sistema, spesso assente o permissiva. Limiti su CLI come difesa in profondità: `-limit memory 256MiB -limit map 512MiB -limit disk 1GiB -limit time 30`. SVG instradato su `rsvg-convert` invece del delegate generico. Invocazione con argv array, mai stringa shell interpolata | 2.4, 4.1 |
| S4 | ydotool e `/dev/uinput` | **High** (postura, non bug) | Chiunque nel gruppo può sintetizzare tastiera per **qualsiasi** applicazione della sessione, inclusi prompt sudo e master password dei password manager. Bypassa l'isolamento input che è il principale miglioramento di Wayland su X11 | Opt-in e mai probato automaticamente è sufficiente a livello di codice. Serve rafforzare la **documentazione**: dichiarare il blast radius reale, non un generico "potrebbe ridurre la sicurezza"; verificare i permessi del socket di `ydotoold` nelle istruzioni; preferire la variante con socket scoped alla UID rispetto al pattern "aggiungi l'utente al gruppo input" copiato ovunque online | 1.3, 1.7 |
| S5 | Nomi dei file intermedi della pipeline | **Medium** | Derivare il nome intermedio per concatenazione (`"${FILE%.png}.webp"`) reintroduce esattamente la race e il symlink attack che `mktemp` era stato adottato per eliminare | Ogni file intermedio ha il proprio `mktemp`, mai un nome derivato per manipolazione di stringa. Array dei temporanei più singolo `trap 'rm -f "${TMP_FILES[@]}"' EXIT` centralizzato, invece di `rm -f` puntuale per ogni ramo d'errore | 4.1 |
| S6 | Retention amplificata dalla pipeline | **Medium** (privacy) | La pipeline moltiplica le copie dello stesso contenuto potenzialmente sensibile: originale, convertito, ridimensionato, annotato. Uno screenshot di un password manager resta in `/tmp` per 7 giorni in quattro copie | Gli intermedi non servono oltre la fine della pipeline: cancellati subito a successo, non lasciati scadere insieme al risultato finale, che è l'unico a cui la grace period ha senso | 4.1 |
| S7 | Permessi di log e output dir | **Low** (pre-esistente, aggravato) | `mkdir -p` senza modalità esplicita dipende dall'umask ereditato: con umask 022 la directory è 755 e i log 644, leggibili da altri utenti locali. La nuova capabilities cache alza la sensibilità di ciò che sta lì | `umask 077` a inizio script, oppure `chmod 700` e `600` espliciti dopo la creazione | 0.3 |
| S8 | Sovrascrittura della clipboard | **Medium**, non è un vettore d'attacco | Data loss, non vulnerabilità: nessun attaccante ottiene qualcosa. L'utente ha appena copiato una password, preme lo shortcut per abitudine, la password viene sostituita silenziosamente | Notifica che menzioni la sovrascrittura. Valutare la selection PRIMARY invece di CLIPBOARD, che è la mitigazione col miglior rapporto costo-beneficio. Il ripristino automatico dopo timeout è **sconsigliato**: non c'è modo affidabile di sapere se l'utente ha già incollato, e introduce race per un rischio auto-inflitto | 1.4 |

Esplicitamente classificato come trascurabile: un'applicazione locale malevola che imposta la clipboard presuppone già esecuzione di codice come l'utente, quindi il guadagno per l'attaccante è marginale. Non merita mitigazione dedicata.

## Fasi e sub-task

Dettaglio in `tasks.md`. Ogni fase chiude con test verdi, ShellCheck pulito e almeno un commit.

| Fase | Contenuto | Stima base |
|---|---|---|
| 0 | Fondamenta: spike, build, moduli, config, disaccoppiamento test | 11h |
| 1 | Sessione e consegna: rilevamento, quattro backend, validazione path | 7h 15m |
| 2 | Contenuto clipboard: astrazione, priorità target, uri-list, conversione | 7h 15m |
| 3 | Shortcut multi-DE: KDE, window manager, dispatcher | 8h 15m |
| 4 | Pipeline P1: resize, formato adattivo, ring buffer, screenshot, annotazione | 11h 45m |
| 5 | Distribuzione e naming: Makefile, deb, AUR, Nix, docs, rename | 8h |
| | **Totale base** | **53h 30m** |

Buffer espliciti, non nascosti nelle stime: imprevisti tecnici +20% (10h 40m), primo-della-specie su ambienti non riproducibili localmente +10% (5h 20m). **Totale con buffer circa 70h, 8-11 giorni lavorativi.**

Prioritizzazione se il tempo è inferiore:

- **Must have** (Fasi 0, 1, 2): il tool smette di essere inutilizzabile su Wayland e accetta i formati moderni. Circa 30h.
- **Should have** (Fase 3): registrazione shortcut fuori da GNOME. Circa 10h in più.
- **Could have** (Fase 4): differenziazione competitiva. Circa 15h in più.
- **Won't have per ora** (Fase 5): packaging e rename, sensati solo dopo che le feature si sono stabilizzate.

## Ordine di esecuzione

1. **Spike B1 e B2 prima di ogni riga di codice.** B1 può invalidare la modalità di consegna primaria su GNOME Wayland.
2. **ADR-002 a parità di funzionalità**, con `PASTE_IMAGE_OUTPUT_DIR` che sostituisce il `sed` dei test. È un refactor a comportamento invariato con la suite esistente come rete: farlo prima significa che tutte le feature successive nascono nella struttura giusta.
3. **ADR-001**, la feature con più valore per utente, inclusa la modifica del default di shortcut su Wayland.
4. **ADR-003** incrementalmente, uno step per volta, partendo da `convert`, l'unico che risolve un fallimento reale odierno.

## Criteri di successo

1. `bash tests/run_tests.sh` verde: ShellCheck zero warning su `lib/*.sh`, `scripts/build.sh`, `install.sh`, `uninstall.sh`, `tests/*.sh` e sull'artefatto costruito; tutte le suite passate; gate delle 300 righe superato; zero skip taciuti.
2. Nessun sorgente supera 300 righe, nessuna funzione supera 30.
3. Ogni funzione pura elencata nella DoD ha un test L1 per tabella di casi, non solo sul percorso felice.
4. Tutte le mitigazioni da S1 a S8 hanno un test che le esercita con input ostile.
5. `bash install.sh` seguito da `bash uninstall.sh` lascia il sistema pulito, tranne il config utente.
6. Su sway annidato in X11: cattura area, lettura clipboard Wayland e typing via `wtype` funzionano end-to-end.
7. Su GNOME Wayland reale: il fallback a clipboard consegna il path e la notifica lo comunica in modo comprensibile.
8. `docs/MANUAL_TESTING.md` compilato con l'esito di ogni casella e i punti non verificati marcati come tali, nominati nel CHANGELOG.
9. Un utente v1 che aggiorna non perde la configurazione e non deve leggere il codice per capire cosa è cambiato.

## Handoff

- Fasi 0-4: `tdd-guide`, test-first.
- Fase 5 (packaging, Makefile, CI): `devops-engineer`.
- Sub-task 5.8 (rename): `git-assistant`, solo dopo conferma esplicita su B3.
- Documentazione bilingue di ogni fase: `doc-writer`.
- Gate: `code-reviewer` a fine di ogni fase; `security-reviewer` obbligatorio a chiusura della Fase 0 (parser di config, S1) e della Fase 2 (path da sorgente esterna, S2 e S3).
