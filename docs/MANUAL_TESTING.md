> **Language:** English | [Italiano](MANUAL_TESTING.it.md)

# Manual Testing

The automated suite covers what can be verified on one machine. Some behaviour
depends on a display server, a compositor or a desktop that a single
development box cannot provide, and this file records what was actually
verified, how, and what remains open.

Anything not verified is listed as such. A gap that is written down can be
closed by someone with the right hardware; a gap that is implied to be covered
cannot.

## Verification levels

| Level | Meaning | Where it runs |
|---|---|---|
| L1 | A pure function is sourced and its output asserted | Anywhere, including CI |
| L2 | Fake binaries on `PATH` plus a forced environment | Anywhere, including CI |
| L3 | Real hardware, real tools, real session | By hand |

L1 and L2 are the automated suite: `bash tests/run_tests.sh`.

## Running a nested compositor

Most Wayland checks do not need a second machine. sway runs nested, headless,
without opening windows on your session:

```bash
WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 sway -c /path/to/config
```

Add `--unsupported-gpu` if the machine has proprietary Nvidia drivers, which
sway otherwise refuses to start on.

The config file just needs one line, `exec /path/to/your-test-script`, and the
script should end with `swaymsg exit` so the compositor tears down when the
test finishes.

## Verified

Recorded 2026-07-30. Environment: Ubuntu, GNOME, X11 host; sway 1.9 nested
headless; wl-clipboard 2.2.1; ImageMagick 6.9.12.

| Case | Level | Result |
|---|---|---|
| `xdotool type` synthesises `Return` for CR, `Linefeed` for LF | L3 | Confirmed, via `xev` on an isolated Xvfb display. This is what makes path validation mandatory rather than defensive |
| `xclip` keeps the selection after the caller exits | L3 | Yes, and in a different process group, so it survives the group being killed |
| `wl-copy` stays in the caller's process group | L3 | Yes. Killing it loses the clipboard, which is why `setsid` is used |
| `setsid wl-copy` survives the caller's group being killed | L3 | Yes |
| PNG from the clipboard, sway session | L3 | File saved, path delivered |
| WebP from the clipboard | L3 | Converted to PNG, recorded in the log |
| File copied from a file manager | L3 | Existing path used, no copy created |
| GNOME Wayland delivery | L3 | Path in the clipboard, notification explains to press Ctrl+V |
| `wtype` on sway | L3 | Invoked successfully |
| `grim` area capture via `--screenshot` | L3 | 200x150 area captured, valid PNG |
| Resize 4000x3000 to 1568x1176 | L3 | Correct dimensions, single file on disk, no intermediates left |
| `make install` with `PREFIX` and `DESTDIR` | L2 | Correct tree, `$HOME` untouched |

## Not verified

| Case | Why | What would close it |
|---|---|---|
| The shortcut actually firing on **KDE Plasma** | No machine available | Run `bash install.sh` on KDE, press the shortcut. The file contents written to `kglobalshortcutsrc` are covered by L2 tests; whether kglobalaccel picks them up is not |
| **GNOME Wayland as a login session** | Tested by forcing environment variables inside nested sway | Log out, pick the Wayland session, install, press the shortcut. In particular: whether `gsd-media-keys` terminates the process group of the script it launches, which is the case `setsid` defends against |
| **Hyprland, i3, river** | Only the generated config line is covered by L1 tests | Paste the line printed by `--print-shortcut`, reload, press it |
| `ydotool` delivery | Requires a daemon with `/dev/uinput` access, deliberately not set up | Set `TYPING_BACKEND=ydotool` with the daemon running |
| `satty` and `swappy` annotation | Neither installed on the development machine | `paste-image --annotate` with one of them present |
| `spectacle`, `flameshot`, `maim`, `scrot` capture | Not installed; only tool selection is covered by L1 | `paste-image --screenshot` with each present |
| **AVIF conversion** | ImageMagick 6 on the development machine has no AVIF delegate | Same test as WebP, on a system with ImageMagick 7 |
| Fedora, Arch, openSUSE | Only Debian and Ubuntu package names were exercised | Run the installer and check the package names it proposes |

## Reporting

If one of the unverified cases fails for you, `paste-image --doctor` prints the
detected environment, the chosen delivery backend and the available tools.
Attaching that output makes the difference between a report that can be
answered and one that cannot.
