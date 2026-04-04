> **Lingua:** Italiano | [English](README.md)
>
> **Vedi anche:** [Politica di Sicurezza (IT)](SECURITY.it.md) · [Security Policy (EN)](SECURITY.md)

# cli-image-paste

Incolla immagini dagli appunti direttamente nel terminale come percorsi file — pronto per qualsiasi assistente di coding da CLI.

Premi una scorciatoia da tastiera e l'immagine negli appunti viene salvata come file temporaneo, con il suo percorso digitato automaticamente nella finestra del terminale attivo.

## Perché

Gli assistenti di coding da CLI come [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Aider](https://aider.chat), [Gemini CLI](https://github.com/google-gemini/gemini-cli) e altri accettano file immagine come input, ma non hanno un modo nativo per incollare immagini dagli appunti di sistema. Questo tool colma quel vuoto: copia un'immagine, premi la scorciatoia e il percorso del file viene digitato nel terminale — pronto per l'invio.

Funziona con **qualsiasi tool CLI** che accetta percorsi file come input.

## Demo

```
# 1. Copia un'immagine (screenshot, immagine dal browser, ecc.)
# 2. Metti il focus sul terminale con il tuo assistente di coding
# 3. Premi Ctrl+Shift+V
# 4. Il percorso viene digitato automaticamente:

/tmp/paste_image_20260309_143022_a1b2c3.png
```

## Funzionalità

- Scorciatoia da tastiera globale GNOME (configurabile)
- Rilevamento automatico del tipo di immagine (PNG/JPEG)
- Creazione sicura e atomica dei file tramite `mktemp`
- Gestione del focus della finestra (ricorda quale terminale era attivo)
- Notifiche desktop per successi ed errori
- Pulizia automatica dei file temporanei più vecchi di 7 giorni
- Rotazione dei log con scritture sicure contro race condition
- Installazione dipendenze cross-distro (apt/dnf/pacman)

## Requisiti di Sistema

| Requisito                  | Dettaglio                                                      |
| -------------------------- | -------------------------------------------------------------- |
| **Sistema operativo**      | Linux (Ubuntu, Fedora, Arch o altra distro basata su GNOME)    |
| **Display server**         | X11 (Wayland non è supportato)                                 |
| **Ambiente desktop**       | GNOME (per la configurazione automatica della scorciatoia)     |
| **Shell**                  | Bash 4.0+                                                      |

**Formati immagine supportati:** PNG, JPEG.

## Installazione

```bash
git clone https://github.com/user/cli-image-paste.git
cd cli-image-paste
bash install.sh
```

L'installer gestisce tutto:

1. Rileva e installa le dipendenze mancanti (`xclip`, `xdotool`, `libnotify-bin`)
2. Copia lo script in `~/.local/bin/paste-image`
3. Aggiunge `~/.local/bin` al PATH se necessario
4. Configura una scorciatoia da tastiera globale GNOME (default: `Ctrl+Shift+V`)
5. Verifica che il servizio `gsd-media-keys` sia attivo

Ti verrà chiesto di scegliere una scorciatoia personalizzata o accettare quella predefinita.

### Dipendenze

| Dipendenza    | Scopo                                    | Pacchetto (apt) |
| ------------- | ---------------------------------------- | ---------------- |
| `xclip`       | Lettura immagini dalla clipboard X11     | `xclip`          |
| `xdotool`     | Simulazione input tastiera nel terminale | `xdotool`        |
| `notify-send` | Notifiche desktop                        | `libnotify-bin`  |
| `python3`     | Manipolazione configurazione JSON        | `python3`        |

Tutte le dipendenze vengono installate automaticamente durante il setup. Se preferisci l'installazione manuale:

```bash
# Ubuntu/Debian
sudo apt install xclip xdotool libnotify-bin

# Fedora
sudo dnf install xclip xdotool libnotify

# Arch
sudo pacman -S xclip xdotool libnotify
```

## Utilizzo

### Tramite scorciatoia da tastiera (consigliato)

1. **Copia un'immagine** negli appunti (screenshot, tasto destro > copia immagine, ecc.)
2. **Metti il focus sul terminale** dove è in esecuzione il tuo assistente di coding
3. **Premi la scorciatoia** (default: `Ctrl+Shift+V`)
4. L'immagine viene salvata e il suo percorso digitato nel terminale
5. **Premi Invio** per inviarla all'assistente di coding

### Invocazione manuale

```bash
paste-image            # Esegui lo script direttamente
paste-image --version  # Mostra la versione
paste-image -v         # Mostra la versione (forma breve)
```

## Configurazione

### Cambiare la scorciatoia da tastiera

Durante l'installazione puoi scegliere una scorciatoia personalizzata. Dopo l'installazione, modificala con:

```bash
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/paste-image/ binding "<Control><Alt>v"
```

Formato tasti modificatori: `<Control>`, `<Shift>`, `<Alt>`, `<Super>`.

Puoi anche cambiarla da **Impostazioni > Tastiera > Scorciatoie > Scorciatoie personalizzate**.

> **Nota:** `Ctrl+Shift+V` è la scorciatoia predefinita per incollare nella maggior parte dei terminali Linux. Se causa conflitti, scegli una scorciatoia diversa (es. `<Control><Alt>v`).

### Configurazione dello script

Le seguenti costanti possono essere modificate direttamente in `~/.local/bin/paste-image`:

| Costante         | Default | Descrizione                                      |
| ---------------- | ------- | ------------------------------------------------ |
| `MAX_LOG_LINES`  | `500`   | Soglia rotazione log (righe)                     |
| `NOTIFY_TIMEOUT` | `3000`  | Durata notifica (millisecondi)                   |
| `CLEANUP_DAYS`   | `7`     | Eliminazione automatica file temporanei (giorni) |
| `TYPING_DELAY`   | `0.1`   | Ritardo prima della digitazione (secondi)        |

### File di log

I log sono salvati in `~/.local/state/paste-image/paste_image.log` (oppure `$XDG_STATE_HOME/paste-image/` se impostato).

## Disinstallazione

```bash
bash uninstall.sh
```

Questo rimuove lo script e la scorciatoia da tastiera GNOME. Le dipendenze di sistema vengono intenzionalmente lasciate installate (potrebbero essere usate da altri programmi). I file temporanei in `/tmp/paste_image_*` più vecchi di 7 giorni vengono puliti automaticamente ad ogni invocazione; quelli più recenti vengono rimossi al riavvio del sistema.

## Risoluzione Problemi

### Il percorso non appare nel terminale

- Assicurati che il terminale abbia il focus quando premi la scorciatoia
- Verifica che X11 sia in uso: `echo $XDG_SESSION_TYPE` deve restituire `x11`
- Prova ad eseguire `paste-image` manualmente per vedere l'output di errore

### Notifica "No image in clipboard"

- Assicurati di aver copiato un'immagine vera (non testo o un file)
- Alcune applicazioni non copiano le immagini negli appunti di sistema

### La scorciatoia non funziona ma l'invocazione manuale sì

Il servizio GNOME che gestisce le scorciatoie personalizzate (`gsd-media-keys`) potrebbe non essere attivo:

```bash
# Controlla se è attivo
pgrep -x gsd-media-keys

# Se non restituisce nulla, riavvialo
systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target
```

Se il problema persiste:

- Verifica che la scorciatoia sia registrata: `gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings`
- Controlla conflitti con altre scorciatoie di sistema

### L'immagine viene salvata ma il percorso non viene digitato

- Aumenta `TYPING_DELAY` nella configurazione dello script (default: `0.1` secondi)
- Alcuni emulatori di terminale potrebbero aver bisogno di un ritardo maggiore per il corretto funzionamento di `xdotool`

## Struttura del Progetto

```
cli-image-paste/
├── paste-image          # Script principale
├── install.sh           # Script di installazione
├── uninstall.sh         # Script di disinstallazione
├── README.md            # Documentazione (inglese)
├── README.it.md         # Documentazione (italiano)
├── SECURITY.md          # Politica di sicurezza (inglese)
├── SECURITY.it.md       # Politica di sicurezza (italiano)
├── LICENSE              # Licenza MIT
├── .gitignore           # Regole di esclusione Git
├── .shellcheckrc        # Configurazione linter ShellCheck
├── tests/               # Suite di test
│   ├── run_tests.sh         # Runner dei test
│   ├── test_framework.sh    # Framework di test personalizzato
│   ├── test_paste_image.sh  # Test dello script principale
│   ├── test_install.sh      # Test dell'installazione
│   └── test_uninstall.sh    # Test della disinstallazione
└── docs/                # Documentazione
```

## Eseguire i Test

```bash
bash tests/run_tests.sh
```

La suite di test include 50+ casi di test che coprono lo script principale, i flussi di installazione e disinstallazione. I test usano utility di sistema mockate per un'esecuzione sicura.

Analisi statica con ShellCheck:

```bash
shellcheck paste-image install.sh uninstall.sh
```

## Limitazioni

- **Solo X11** — non compatibile con Wayland (richiederebbe `wl-paste` + `ydotool`)
- **Solo GNOME** — la configurazione automatica della scorciatoia usa `gsettings`
- **Il terminale deve avere il focus** quando si preme la scorciatoia
- Solo immagini **PNG** e **JPEG** sono supportate

## Contribuire

1. Fai un fork del repository
2. Crea un branch per la feature (`git checkout -b feature/la-mia-feature`)
3. Assicurati che tutti i test passino (`bash tests/run_tests.sh`)
4. Assicurati che ShellCheck passi (`shellcheck paste-image install.sh uninstall.sh`)
5. Fai commit delle modifiche e apri una pull request

## Sicurezza

Per informazioni sulle considerazioni di sicurezza e su come segnalare vulnerabilità, vedi [SECURITY.it.md](SECURITY.it.md).

## Licenza

Questo progetto è rilasciato sotto la [Licenza MIT](LICENSE).
