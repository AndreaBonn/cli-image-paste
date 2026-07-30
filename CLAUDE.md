# CLAUDE.md — cli-image-paste

Convenzioni tecniche del progetto. Da leggere prima di modificare il codice.

## Cos'è

Tool Bash che legge un'immagine dagli appunti, la salva come file temporaneo e consegna il path al terminale attivo, per darlo in pasto a un coding assistant CLI. Deve restare leggero, installabile senza privilegi e disinstallabile senza residui: sono queste proprietà a renderlo adottabile, non il numero di funzionalità.

## Stack

Bash 4.4+, nessuna dipendenza di runtime obbligatoria oltre a un backend di lettura appunti e uno di consegna. Tutte le altre (ImageMagick, tool di screenshot, annotatori) sono opzionali e devono degradare con un messaggio utile, mai bloccare.

## Struttura

```
lib/NN_nome.sh      sorgenti, concatenati in ordine numerico
scripts/build.sh    genera dist/paste-image
scripts/*.sh        script di supporto invocati da install.sh
dist/paste-image    artefatto generato, non versionato
tests/              suite + framework in tests/framework/
specs/<slug>/       piano e scomposizione dei task
```

**Il file eseguibile è generato, non scritto.** Ogni modifica va fatta nel modulo corrispondente in `lib/`, poi si ribuilda. `dist/` è in `.gitignore`: un artefatto stantio committato non è possibile.

## Regole di modulo

Sono ciò che rende sicura la concatenazione. Verificate da `tests/test_no_side_effects.sh`, che fallisce se vengono violate.

1. Solo `00_header.sh` contiene shebang e `set -euo pipefail`. Gli altri iniziano con `# shellcheck shell=bash`.
2. Nessun modulo tranne `90_main.sh` esegue codice al momento del source: **solo definizioni di funzione e costanti**. È la precondizione perché un test possa sorgiare un modulo per esercitarne le funzioni.
3. Nessun `exit` fuori da `90_main.sh`. Le funzioni ritornano un exit code, la decisione di uscire appartiene all'orchestratore.
4. Prefisso `_` per le funzioni private di un modulo, nome nudo per l'interfaccia pubblica.
5. L'ordine numerico del nome è l'ordine di dipendenza: Bash non ha import, meglio renderlo visibile nel nome che scoprirlo con un errore.

## Architettura

Le decisioni strutturali e le loro alternative scartate stanno in `specs/001-wayland-multi-de-pipeline/plan.md`. In sintesi:

- **Due porte separate**, non un backend unico: leggere gli appunti e consegnare il path sono assi ortogonali. Su GNOME Wayland il primo funziona e solo il secondo è rotto.
- **Tre stadi**: `SOURCE → TRANSFORM* → STORE → DELIVERY`. Lo screenshot è una sorgente alternativa, non una trasformazione. L'annotazione è una trasformazione interattiva.
- **Functional core, imperative shell**: ogni decisione (quale backend, quale MIME, quale template) è una funzione pura che riceve i suoi input come argomenti e stampa una stringa. L'I/O vive nell'orchestratore. È la sola ragione per cui il comportamento su desktop che non possediamo resta verificabile.

## Configurazione

`~/.config/paste-image/config`, oppure `$XDG_CONFIG_HOME/paste-image/config`.

Il file viene **parsato, mai sorgiato**. Un `source` di un file di configurazione è esecuzione di codice arbitrario a ogni pressione dello shortcut, incoerente con un progetto che pubblica un `SECURITY.md`. Solo le chiavi in whitelist vengono accettate e ognuna passa una validazione per tipo; chiavi ignote e valori non validi finiscono nel log, non vengono applicati in silenzio.

Precedenza: default < file < variabile d'ambiente `PASTE_IMAGE_<CHIAVE>` < flag da riga di comando.

## Sicurezza

Due invarianti da non violare, entrambi verificati empiricamente:

**Tutto ciò che viene digitato nel terminale è input di shell.** `xdotool type` sintetizza il keysym `Return` per un CR e `Linefeed` per un LF: un path o un template contenente quei caratteri esegue il comando nel prompt idle in attesa, che è esattamente lo scenario d'uso del tool. Ogni stringa destinata alla digitazione passa dalla validazione: niente caratteri di controllo C0/C1, niente override bidirezionali Unicode, path assoluto.

**Il template di formato è più pericoloso di un path.** Un path arriva una volta dagli appunti, un template ostile nel config viene digitato a ogni invocazione, per sempre. Validazione a whitelist di caratteri, esattamente un `%s`, lunghezza massima. La sostituzione usa `${template//%s/$path}`, **mai** `printf "$template" "$path"`, che tratterebbe input esterno come format string.

## Testing

```bash
bash tests/run_tests.sh          # build + gate + shellcheck + tutte le suite
bash tests/test_lib_config.sh    # singola suite
```

Il runner è il gate: build dell'artefatto, limite di 300 righe per sorgente che **fallisce** invece di avvisare, ShellCheck a zero warning su tutti i percorsi, poi le suite.

Livelli di verifica, perché la macchina di sviluppo non può provare tutti gli ambienti:

- **L1** — la funzione pura viene sorgiata dal test e la sua stringa di output asserita. Gira ovunque.
- **L2** — binari finti su `PATH` più ambiente forzato (`PASTE_IMAGE_SESSION_TYPE`, `PASTE_IMAGE_DESKTOP`). Gira in CI.
- **L3** — manuale su hardware reale. Ciò che resta non verificato va **dichiarato**, non nascosto.

Un test non eredita nulla dalla macchina che lo esegue: `setup_test_env` dirotta `HOME`, le directory XDG e le variabili di sessione dentro il fake home, quindi la sessione va **dichiarata** con `set_session_env` in ogni suite che esercita un percorso specifico di desktop. Un test che legge l'ambiente reale passa sotto X11 e fallisce su un runner headless, e ciò che scrive fuori dal fake home cambia l'esito delle suite successive. L'invariante è verificato da `tests/test_framework_isolation.sh`.

Regole: ogni funzione ha test sul comportamento atteso, non sull'assenza di crash. Un test che non ha mai visto il rosso non prova nulla: dopo averlo scritto, rompi intenzionalmente il codice e verifica che fallisca. Mai valori speciali nel codice di produzione per far passare un test.

## Convenzioni di scrittura

- Commenti e messaggi utente in **italiano**. Documentazione bilingue: `FILE.md` in inglese, `FILE.it.md` in italiano.
- Sezioni marcate con `# --- N. Titolo ---`.
- I commenti spiegano il **perché**, non il cosa. Il diff mostra già il cosa.
- Niente emoji decorative, niente em-dash, niente linguaggio entusiasta nei testi.
- Limiti: 300 righe per file, 30 per funzione, 4 parametri, 3 livelli di annidamento.

## Git

Branch `main` protetto. Conventional Commits in inglese, imperativo presente. Un commit per cambiamento logico. Nessuna attribuzione AI nei messaggi. Il push avviene solo su richiesta esplicita.
