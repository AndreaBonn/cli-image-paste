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

### Temporary File Handling

- Files are created using `mktemp` with atomic operations to prevent race conditions
- File permissions are set to `600` (owner read/write only)
- Predictable filename patterns are mitigated by the random suffix from `mktemp`

### Installation

- The installer may request `sudo` to install system dependencies via your package manager
- The main script is installed to `~/.local/bin/` (user space, no root required)
- GNOME keyboard shortcuts are configured via `gsettings` (user space)

### Logging

- Logs are stored in `~/.local/state/paste-image/` with user-only permissions
- Logs contain file paths and timestamps — no clipboard content is logged
- Log rotation is enforced to prevent unbounded growth

## Best Practices for Users

- Review the script before installation: `cat install.sh` and `cat paste-image`
- Keep your system dependencies updated
- Use a dedicated clipboard manager if you handle sensitive data frequently
- The tool only operates under X11 — Wayland is not supported
