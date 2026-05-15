> **Language:** English | [Italiano](ARCHITECTURE.it.md)

# Architecture

Technical diagrams for cli-image-paste internals.

## System Overview

Three CLI scripts interact with X11 tools, system utilities, and GNOME configuration to bridge clipboard images into terminal file paths.

```mermaid
%%{init: {'theme': 'default'}}%%
graph TD
  subgraph scripts["CLI Scripts"]
    direction LR
    paste_image["paste-image"]
    install["install.sh"]
    uninstall["uninstall.sh"]
  end

  subgraph x11["X11 Tools"]
    direction LR
    xclip["xclip"]
    xdotool["xdotool"]
  end

  subgraph sys["System Utilities"]
    direction LR
    mktemp["mktemp"]
    flock["flock"]
    notify["notify-send / zenity"]
  end

  subgraph gnome_cfg["GNOME Config"]
    direction LR
    gsettings["gsettings"]
    python3["python3"]
    systemctl["systemctl"]
    pkg_mgr["apt / dnf / pacman"]
  end

  subgraph store["Storage Paths"]
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

**Legend:** Blue = project scripts, Green = X11 tools, Grey = system utilities, Orange = storage paths. Dashed lines = file I/O, solid lines = runtime dependency.

## Runtime Flow

The `paste-image` script execution from keyboard shortcut to file path typed in terminal, including the error path when no image is found in the clipboard.

```mermaid
sequenceDiagram
  autonumber
  actor user as User
  participant gnome as GNOME
  participant script as paste-image
  participant xclip as xclip
  participant fs as File System
  participant xdotool as xdotool
  participant notif as notify-send

  user->>gnome: Press Ctrl+Shift+V
  gnome->>script: Invoke paste-image
  script->>script: Check dependencies
  script->>script: Save active window ID
  script->>xclip: Read clipboard TARGETS
  xclip-->>script: MIME types list

  alt No image in clipboard
    script->>notif: Show error notification
    notif-->>user: No image in clipboard
  else PNG or JPEG detected
    script->>fs: mktemp secure file
    fs-->>script: /tmp/paste_image_*.png
    script->>xclip: Extract image data
    xclip-->>fs: Write binary to file
    script->>script: Validate file not empty
    script->>xdotool: Restore window focus
    script->>xdotool: Type file path
    xdotool-->>user: Path appears in terminal
    script->>notif: Success notification
  end
```

Key implementation details:
- **Step 4:** `xdotool getactivewindow` saves the terminal window ID before any clipboard operation
- **Step 8:** `mktemp` creates the file with 0600 permissions and a random suffix (no TOCTOU)
- **Step 13-14:** `xdotool windowfocus --sync` restores focus, then `xdotool type --clearmodifiers` types the path

## Installation Flow

The `install.sh` decision tree with package manager detection, dependency installation, shortcut configuration, conflict handling, and gsettings array validation with rollback.

```mermaid
%%{init: {'theme': 'default'}}%%
graph TD
  start_node(["Start install.sh"]) --> detect_pkg{"Detect package manager"}
  detect_pkg -->|"apt"| check_deps["Check missing dependencies"]
  detect_pkg -->|"dnf"| check_deps
  detect_pkg -->|"pacman"| check_deps
  detect_pkg -->|"none"| skip_pkg["Skip auto-install"]
  skip_pkg --> copy_script

  check_deps --> has_missing{"Missing deps?"}
  has_missing -->|"No"| copy_script["Copy to ~/.local/bin"]
  has_missing -->|"Yes"| prompt_user{"User accepts install?"}
  prompt_user -->|"Yes"| install_deps["sudo install packages"]
  prompt_user -->|"No"| copy_script
  install_deps --> copy_script

  copy_script --> check_path{"~/.local/bin in PATH?"}
  check_path -->|"Yes"| config_shortcut["Configure shortcut"]
  check_path -->|"No"| add_path["Add to .bashrc / .zshrc"]
  add_path --> config_shortcut

  config_shortcut --> validate_fmt{"Valid GTK format?"}
  validate_fmt -->|"No"| ask_shortcut["Ask for valid shortcut"]
  ask_shortcut --> validate_fmt
  validate_fmt -->|"Yes"| check_conflict{"Shortcut conflict?"}
  check_conflict -->|"Yes, override"| set_gsettings["Set gsettings properties"]
  check_conflict -->|"No conflict"| set_gsettings

  set_gsettings --> verify_array{"Array valid?"}
  verify_array -->|"Yes"| start_service["Start gsd-media-keys"]
  verify_array -->|"Corrupted"| rollback["Rollback gsettings"]
  rollback --> start_service
  start_service --> done_node(["Installation complete"])

  classDef core fill:#2563eb,stroke:#1d4ed8,color:#fff
  classDef data fill:#d97706,stroke:#b45309,color:#fff
  classDef ext fill:#6b7280,stroke:#4b5563,color:#fff
  classDef engine fill:#059669,stroke:#047857,color:#fff

  class start_node,done_node core
  class detect_pkg,has_missing,check_path,validate_fmt,check_conflict,verify_array,prompt_user data
  class install_deps,set_gsettings,start_service,rollback engine
  class copy_script,add_path,config_shortcut,check_deps,skip_pkg,ask_shortcut ext
```

**Legend:** Blue = start/end, Orange = decision points, Green = system operations, Grey = script steps.

Notable defensive patterns:
- **Rollback:** if `gsettings` array becomes corrupted after modification, the previous value is restored
- **Idempotent:** running `install.sh` twice produces the same result (PATH check, gsettings check)
- **Python3 for JSON:** gsettings arrays are parsed via Python3 to avoid bash glob expansion issues

## CI/CD Pipeline

Three GitHub Actions workflows triggered by different events.

```mermaid
%%{init: {'theme': 'default'}}%%
graph LR
  subgraph triggers["Triggers"]
    direction TB
    push_pr["Push / PR to main"]
    pr_only["PR to main"]
    release["Release published"]
  end

  subgraph ci_workflow["ci.yml"]
    direction TB
    shellcheck["ShellCheck lint"]
    test_suite["Test Suite<br/>50+ tests"]
  end

  subgraph review_workflow["ai-review.yml"]
    direction TB
    ai_review["AI Code Review"]
    providers["Groq / Gemini / OpenAI"]
  end

  subgraph changelog_workflow["ai-changelog.yml"]
    direction TB
    ai_changelog["Auto Changelog"]
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

**Legend:** Orange = trigger events, Blue = quality gates, Green = AI-powered automation, Grey = LLM providers.

The AI review and changelog workflows use a fallback chain across three LLM providers for resilience.
