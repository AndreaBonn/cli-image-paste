# paste-image

Incolla immagini dalla clipboard direttamente nel terminale, pronte per essere inviate a qualsiasi coding assistant CLI.

Premi uno shortcut da tastiera: l'immagine viene salvata come file temporaneo e il path viene digitato automaticamente nel terminale attivo.

## Perché

I coding assistant CLI come [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Aider](https://aider.chat), [Gemini CLI](https://github.com/google-gemini/gemini-cli) e altri accettano immagini come input, ma non offrono un modo nativo per incollarle dalla clipboard del sistema. Questo tool colma il gap: copia un'immagine, premi lo shortcut, e il path del file viene digitato nel terminale pronto per l'invio.

Funziona con qualsiasi tool CLI che accetta path di file come input.

## Requisiti di sistema

| Requisito               | Dettaglio                                               |
| ----------------------- | ------------------------------------------------------- |
| **OS**                  | Ubuntu (o altra distribuzione Linux con GNOME)          |
| **Display server**      | X11 (non Wayland)                                       |
| **Desktop environment** | GNOME (per la configurazione automatica dello shortcut) |

**Formati immagine supportati:** PNG, JPEG.

## Installazione

```bash
git clone <repository-url>
cd paste-images-cli
bash install.sh
```

L'installer si occupa di tutto:

1. Installa le dipendenze mancanti (`xclip`, `xdotool`, `libnotify-bin`)
2. Copia lo script in `~/.local/bin/`
3. Configura il PATH se non include `~/.local/bin`
4. Configura lo shortcut globale GNOME (default: `Ctrl+Shift+V`)
5. Verifica che il servizio `gsd-media-keys` sia attivo (lo riavvia se necessario)

## Come funziona

1. **Copia un'immagine** negli appunti (screenshot, immagine da browser, ecc.)
2. **Porta il focus** sul terminale dove gira il coding assistant
3. **Premi lo shortcut** (default: `Ctrl+Shift+V`)
4. Lo script salva l'immagine dalla clipboard in `/tmp/paste_image_<timestamp>.png`
5. Il path del file viene digitato automaticamente nel terminale tramite `xdotool`
6. **Premi Invio** per inviare l'immagine al coding assistant

## Cambiare lo shortcut

Durante l'installazione puoi scegliere un shortcut personalizzato. Dopo l'installazione puoi modificarlo con:

```bash
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/paste-image/ binding "<Control><Alt>v"
```

Formato dei tasti modificatori: `<Control>`, `<Shift>`, `<Alt>`, `<Super>`.

Puoi anche modificarlo da **Impostazioni > Tastiera > Scorciatoie > Scorciatoie personalizzate**.

> **Nota:** `Ctrl+Shift+V` è anche il "paste" standard dei terminali Linux. Se questo crea conflitti, scegli un altro shortcut (es. `<Control><Alt>v`).

## Disinstallazione

```bash
bash uninstall.sh
```

Rimuove lo script e lo shortcut GNOME. Le dipendenze di sistema non vengono rimosse (potrebbero essere usate da altri programmi). I file temporanei in `/tmp/paste_image_*` più vecchi di 7 giorni vengono rimossi automaticamente ad ogni invocazione dello script; quelli più recenti vengono rimossi al riavvio del sistema.

## Troubleshooting

### Il path non appare nel terminale

- Verifica che il terminale abbia il focus quando premi lo shortcut
- Verifica che X11 sia in uso: `echo $XDG_SESSION_TYPE` deve restituire `x11`
- Prova a eseguire `paste-image` manualmente dal terminale per vedere eventuali errori

### Notifica "Nessuna immagine negli appunti"

- Assicurati di aver copiato un'immagine (non testo)
- Alcune applicazioni non copiano immagini nella clipboard di sistema

### Lo shortcut non funziona ma il lancio manuale sì

Il servizio GNOME che gestisce gli shortcut custom (`gsd-media-keys`) potrebbe non essere in esecuzione. Verifica e riavvialo:

```bash
# Verifica se è attivo
pgrep -x gsd-media-keys

# Se non restituisce nulla, riavvialo
systemctl --user start org.gnome.SettingsDaemon.MediaKeys.target
```

Se il problema persiste:

- Verifica che lo shortcut sia registrato: `gsettings get org.gnome.settings-daemon.plugins.media-keys custom-keybindings`
- Verifica che non ci siano conflitti con altri shortcut del sistema

### Dipendenze mancanti

```bash
sudo apt install xclip xdotool libnotify-bin
```

## Struttura del progetto

```
paste-images-cli/
├── paste-image        # Script principale
├── install.sh         # Script di installazione
├── uninstall.sh       # Script di disinstallazione
├── README.md          # Questo file
├── .gitignore         # File esclusi dal version control
├── .shellcheckrc      # Configurazione ShellCheck (linter bash)
├── tests/             # Test suite
│   ├── run_tests.sh       # Runner dei test
│   ├── test_framework.sh  # Framework di test custom
│   ├── test_paste_image.sh
│   ├── test_install.sh
│   └── test_uninstall.sh
└── docs/              # Documentazione aggiuntiva
```

## Limitazioni

- **Solo X11:** non compatibile con Wayland (servirebbe `wl-paste` + `ydotool`)
- **Solo GNOME:** la configurazione automatica dello shortcut usa `gsettings`
- **Il terminale deve avere il focus** al momento della pressione dello shortcut
- Supporta solo immagini **PNG** e **JPEG** nella clipboard
