> **Language:** English | [Italiano](SECURITY.it.md)
>
> **See also:** [README (EN)](README.md) · [README (IT)](README.it.md)

# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| latest  | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in cli-image-paste, please report it responsibly.

**Do not open a public GitHub issue for security vulnerabilities.**

Instead, please send an email to the maintainer with:

1. A description of the vulnerability
2. Steps to reproduce the issue
3. The potential impact
4. Any suggested fix (optional)

You can expect an initial response within 72 hours. We will work with you to understand the issue and coordinate a fix before any public disclosure.

## Security Considerations

This tool interacts with several system-level components. Users should be aware of the following:

### Clipboard Access

- The tool reads image data from the X11 clipboard using `xclip`
- Clipboard contents are saved as temporary files in `/tmp`
- Temporary files are automatically cleaned up after 7 days

### Keystroke Simulation

- `xdotool` is used to type the file path into the active terminal window
- The tool records and restores window focus during operation
- Only the generated file path is typed — no other input is simulated

### What Is Typed Into Your Terminal

Everything typed into a terminal is shell input. This was verified
empirically: `xdotool type` synthesises the `Return` keysym for a carriage
return and `Linefeed` for a line feed, so a control character inside a path is
equivalent to pressing Enter at the prompt the tool is aiming at.

- Every string bound for the terminal is validated first: absolute path, no
  C0/C1 control characters, no Unicode bidirectional overrides or isolates
  (which do not execute anything but misrepresent what you are reading)
- A path that fails validation is refused, not typed
- Paths taken from `text/uri-list` or `x-special/gnome-copied-files` are
  percent-decoded **before** validation, since `%0D` only becomes a carriage
  return afterwards
- Only the `file://` scheme is accepted

### Configuration File

- The file is **parsed, never sourced**. Sourcing a config file would be
  arbitrary code execution on every shortcut press
- Only whitelisted keys are accepted; unknown keys and invalid values are
  logged and discarded, never applied silently
- The output format template has the strictest validation of all: character
  whitelist, exactly one `%s`, length cap. Unlike a path, which arrives once,
  a hostile template is typed on every single invocation and persists
- Substitution is a literal string replacement, never `printf` with the
  template as a format string

### Image Conversion

Clipboard content can be hostile, and ImageMagick has a history of delegates
that execute commands (CVE-2016-3714) and coders that read arbitrary files.

- A dedicated restrictive policy is used via `MAGICK_CONFIGURE_PATH`, rather
  than the system policy, which is absent on some distributions and permissive
  on others. Delegates are disabled, along with the MSL, MVG, EPHEMERAL, URL,
  HTTP(S), FTP, TEXT, SHOW, WIN and PLT coders
- Resource limits are passed on the command line as defence in depth against
  decompression bombs
- SVG is rasterised with `rsvg-convert`, a single-purpose tool, rather than the
  general delegate
- Arguments are passed as a list, never interpolated into a shell string

### Typing On Wayland

`ydotool` can type on any compositor, and is available by explicit
configuration only. It is never selected automatically.

It requires a daemon with access to `/dev/uinput`. Anyone able to reach that
daemon can synthesise keystrokes into **any** application in your session,
including sudo prompts and password manager windows, which defeats the input
isolation that is Wayland's main security improvement over X11. If you enable
it, check that its socket is owner-only, and prefer a per-user daemon over
adding your account to a system-wide input group.

### Temporary File Handling

- Files are created using `mktemp` with atomic operations to prevent race conditions
- File permissions are set to `600` (owner read/write only)
- `umask 077` is set explicitly rather than relying on the inherited value,
  which is commonly 022 and would leave the state directory world-readable
- Pipeline intermediates get their own `mktemp` each, never a name derived from
  the original by string manipulation, and are removed as soon as they are no
  longer needed rather than expiring with the result. The pipeline multiplies
  copies of content that may be a screenshot of a password manager

### Clipboard Delivery

On GNOME Wayland the path is written to the text clipboard, which **overwrites
whatever was there**. This is data loss, not a vulnerability, but it is worth
knowing: if you had a password copied, it is gone. The notification says so
explicitly.

### Installation

- The installer may request `sudo` to install system dependencies via your package manager
- The main script is installed to `~/.local/bin/` (user space, no root required)
- Shortcuts are configured in user space: `gsettings` on GNOME, `kglobalshortcutsrc` on KDE, printed instructions on window managers

### Logging

- Logs are stored in `~/.local/state/paste-image/` with user-only permissions
- Logs contain file paths and timestamps — no clipboard content is logged
- Log rotation is enforced to prevent unbounded growth (max 500 lines, keeps last 250)
- Race-condition-safe writes using `flock` prevent log corruption in concurrent scenarios

## Best Practices for Users

- Review the sources before installation: `cat install.sh` and `cat lib/*.sh`
- Keep your system dependencies updated
- Use a dedicated clipboard manager if you handle sensitive data frequently
- Temporary files are automatically cleaned after 7 days
- Check logs periodically: `cat ~/.local/state/paste-image/paste_image.log`
- Run the test suite to verify integrity: `bash tests/run_tests.sh`
