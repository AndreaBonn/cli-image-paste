> **Lingua:** Italiano | [English](ARCHITECTURE.md)

# Architettura

Diagrammi tecnici degli internals di cli-image-paste.

## Panoramica del Sistema

Tre script CLI interagiscono con strumenti X11, utility di sistema e configurazione GNOME per trasformare immagini dalla clipboard in percorsi file nel terminale.

```mermaid
%%{init: {'theme': 'default'}}%%
graph TD
  subgraph scripts["Script CLI"]
    direction LR
    paste_image["paste-image"]
    install["install.sh"]
    uninstall["uninstall.sh"]
  end

  subgraph x11["Strumenti X11"]
    direction LR
    xclip["xclip"]
    xdotool["xdotool"]
  end

  subgraph sys["Utilità di Sistema"]
    direction LR
    mktemp["mktemp"]
    flock["flock"]
    notify["notify-send / zenity"]
  end

  subgraph gnome_cfg["Configurazione GNOME"]
    direction LR
    gsettings["gsettings"]
    python3["python3"]
    systemctl["systemctl"]
    pkg_mgr["apt / dnf / pacman"]
  end

  subgraph store["Percorsi di Archiviazione"]
    direction LR
    local_bin["~/.local/bin"]
    tmp_dir["/tmp/paste_image_*"]
    state_dir["~/.local/state"]
  end

  paste_image --> x11
  paste_image --> sys
  paste_image -.-> tmp_dir
  paste_image -.-> state_dir

  install --> gnome_cfg
  install -.-> local_bin

  uninstall --> gsettings
  uninstall --> python3

  classDef core fill:#2563eb,stroke:#1d4ed8,color:#fff
  classDef data fill:#d97706,stroke:#b45309,color:#fff
  classDef ext fill:#6b7280,stroke:#4b5563,color:#fff
  classDef engine fill:#059669,stroke:#047857,color:#fff

  class paste_image,install,uninstall core
  class xclip,xdotool engine
  class mktemp,flock,notify,gsettings,python3,systemctl,pkg_mgr ext
  class local_bin,tmp_dir,state_dir data
```

**Legenda:** Blu = script del progetto, Verde = strumenti X11, Grigio = utility di sistema, Arancione = percorsi di archiviazione. Linee tratteggiate = I/O file, linee continue = dipendenza runtime.

## Flusso di Esecuzione

Esecuzione dello script `paste-image` dalla scorciatoia da tastiera alla digitazione del percorso nel terminale, incluso il path di errore quando non viene trovata un'immagine nella clipboard.

```mermaid
sequenceDiagram
  autonumber
  actor user as Utente
  participant gnome as GNOME
  participant script as paste-image
  participant xclip as xclip
  participant fs as File System
  participant xdotool as xdotool
  participant notif as notify-send

  user->>gnome: Premi Ctrl+Shift+V
  gnome->>script: Invoca paste-image
  script->>script: Verifica dipendenze
  script->>script: Salva ID finestra attiva
  script->>xclip: Leggi TARGETS clipboard
  xclip-->>script: Lista tipi MIME

  alt Nessuna immagine nella clipboard
    script->>notif: Mostra notifica errore
    notif-->>user: Nessuna immagine
  else PNG o JPEG rilevato
    script->>fs: mktemp file sicuro
    fs-->>script: /tmp/paste_image_*.png
    script->>xclip: Estrai dati immagine
    xclip-->>fs: Scrivi binario su file
    script->>script: Verifica file non vuoto
    script->>xdotool: Ripristina focus finestra
    script->>xdotool: Digita percorso file
    xdotool-->>user: Percorso appare nel terminale
    script->>notif: Notifica successo
  end
```

Dettagli implementativi chiave:
- **Step 4:** `xdotool getactivewindow` salva l'ID della finestra terminale prima di qualsiasi operazione clipboard
- **Step 8:** `mktemp` crea il file con permessi 0600 e suffisso casuale (nessun TOCTOU)
- **Step 13-14:** `xdotool windowfocus --sync` ripristina il focus, poi `xdotool type --clearmodifiers` digita il percorso

## Flusso di Installazione

L'albero decisionale di `install.sh` con rilevamento package manager, installazione dipendenze, configurazione scorciatoia, gestione conflitti e validazione array gsettings con rollback.

```mermaid
%%{init: {'theme': 'default'}}%%
graph TD
  start_node(["Avvia install.sh"]) --> detect_pkg{"Rileva package manager"}
  detect_pkg -->|"apt"| check_deps["Verifica dipendenze mancanti"]
  detect_pkg -->|"dnf"| check_deps
  detect_pkg -->|"pacman"| check_deps
  detect_pkg -->|"nessuno"| skip_pkg["Salta auto-install"]
  skip_pkg --> copy_script

  check_deps --> has_missing{"Dipendenze mancanti?"}
  has_missing -->|"No"| copy_script["Copia in ~/.local/bin"]
  has_missing -->|"Si"| prompt_user{"Utente accetta installazione?"}
  prompt_user -->|"Si"| install_deps["sudo installa pacchetti"]
  prompt_user -->|"No"| copy_script
  install_deps --> copy_script

  copy_script --> check_path{"~/.local/bin nel PATH?"}
  check_path -->|"Si"| config_shortcut["Configura scorciatoia"]
  check_path -->|"No"| add_path["Aggiungi a .bashrc / .zshrc"]
  add_path --> config_shortcut

  config_shortcut --> validate_fmt{"Formato GTK valido?"}
  validate_fmt -->|"No"| ask_shortcut["Chiedi scorciatoia valida"]
  ask_shortcut --> validate_fmt
  validate_fmt -->|"Si"| check_conflict{"Conflitto scorciatoia?"}
  check_conflict -->|"Si, sovrascrivi"| set_gsettings["Imposta gsettings"]
  check_conflict -->|"Nessun conflitto"| set_gsettings

  set_gsettings --> verify_array{"Array valido?"}
  verify_array -->|"Si"| start_service["Avvia gsd-media-keys"]
  verify_array -->|"Corrotto"| rollback["Rollback gsettings"]
  rollback --> start_service
  start_service --> done_node(["Installazione completata"])

  classDef core fill:#2563eb,stroke:#1d4ed8,color:#fff
  classDef data fill:#d97706,stroke:#b45309,color:#fff
  classDef ext fill:#6b7280,stroke:#4b5563,color:#fff
  classDef engine fill:#059669,stroke:#047857,color:#fff

  class start_node,done_node core
  class detect_pkg,has_missing,check_path,validate_fmt,check_conflict,verify_array,prompt_user data
  class install_deps,set_gsettings,start_service,rollback engine
  class copy_script,add_path,config_shortcut,check_deps,skip_pkg,ask_shortcut ext
```

**Legenda:** Blu = inizio/fine, Arancione = punti decisionali, Verde = operazioni di sistema, Grigio = step dello script.

Pattern difensivi notevoli:
- **Rollback:** se l'array `gsettings` risulta corrotto dopo la modifica, il valore precedente viene ripristinato
- **Idempotente:** eseguire `install.sh` due volte produce lo stesso risultato (check PATH, check gsettings)
- **Python3 per JSON:** gli array gsettings vengono parsati via Python3 per evitare problemi di glob expansion in bash

## Pipeline CI/CD

Tre workflow GitHub Actions attivati da eventi diversi.

```mermaid
%%{init: {'theme': 'default'}}%%
graph LR
  subgraph triggers["Trigger"]
    direction TB
    push_pr["Push / PR su main"]
    pr_only["PR su main"]
    release["Release pubblicata"]
  end

  subgraph ci_workflow["ci.yml"]
    direction TB
    shellcheck["ShellCheck lint"]
    test_suite["Suite di Test<br/>50+ test"]
  end

  subgraph review_workflow["ai-review.yml"]
    direction TB
    ai_review["Review AI del Codice"]
    providers["Groq / Gemini / OpenAI"]
  end

  subgraph changelog_workflow["ai-changelog.yml"]
    direction TB
    ai_changelog["Changelog Automatico"]
    changelog_providers["Groq / Gemini / OpenAI"]
  end

  push_pr --> shellcheck
  push_pr --> test_suite
  pr_only --> ai_review
  ai_review --> providers
  release --> ai_changelog
  ai_changelog --> changelog_providers

  classDef core fill:#2563eb,stroke:#1d4ed8,color:#fff
  classDef data fill:#d97706,stroke:#b45309,color:#fff
  classDef ext fill:#6b7280,stroke:#4b5563,color:#fff
  classDef engine fill:#059669,stroke:#047857,color:#fff

  class push_pr,pr_only,release data
  class shellcheck,test_suite core
  class ai_review,ai_changelog engine
  class providers,changelog_providers ext
```

**Legenda:** Arancione = eventi trigger, Blu = quality gate, Verde = automazione AI, Grigio = provider LLM.

I workflow di AI review e changelog usano una catena di fallback su tre provider LLM per resilienza.
