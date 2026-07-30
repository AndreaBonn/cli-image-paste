> **Lingua:** Italiano | [English](MANUAL_TESTING.md)

# Test manuali

La suite automatica copre ciò che è verificabile su una sola macchina. Una
parte del comportamento dipende dal display server, dal compositore o dal
desktop, che una singola postazione di sviluppo non può fornire tutti: questo
file registra che cosa è stato verificato davvero, con quale metodo, e che
cosa resta aperto.

Ciò che non è stato verificato è elencato come tale. Una lacuna scritta può
essere chiusa da chi ha l'hardware giusto; una lacuna lasciata intendere come
coperta, no.

## Livelli di verifica

| Livello | Significato | Dove gira |
|---|---|---|
| L1 | Una funzione pura viene sorgiata e il suo output asserito | Ovunque, CI compresa |
| L2 | Binari finti su `PATH` più ambiente forzato | Ovunque, CI compresa |
| L3 | Hardware reale, strumenti reali, sessione reale | A mano |

L1 e L2 sono la suite automatica: `bash tests/run_tests.sh`.

## Compositore annidato

La maggior parte delle verifiche Wayland non richiede una seconda macchina.
sway gira annidato, headless, senza aprire finestre nella sessione in uso:

```bash
WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 sway -c /percorso/config
```

Aggiungi `--unsupported-gpu` se la macchina ha driver Nvidia proprietari, che
altrimenti impediscono a sway di partire.

Il file di configurazione ha bisogno di una sola riga, `exec
/percorso/script-di-prova`, e lo script deve terminare con `swaymsg exit` così
il compositore si smonta a fine test.

## Verificato

Registrato il 2026-07-30. Ambiente: Ubuntu, GNOME, host X11; sway 1.9
annidato headless; wl-clipboard 2.2.1; ImageMagick 6.9.12.

| Caso | Livello | Esito |
|---|---|---|
| `xdotool type` sintetizza `Return` per un CR e `Linefeed` per un LF | L3 | Confermato con `xev` su un display Xvfb isolato. È ciò che rende la validazione del path obbligatoria e non difensiva |
| `xclip` mantiene la selezione dopo l'uscita del chiamante | L3 | Sì, e in un process group diverso, quindi sopravvive anche a chi termina il gruppo |
| `wl-copy` resta nel process group del chiamante | L3 | Sì. Uccidendolo si perdono gli appunti, ed è la ragione di `setsid` |
| `setsid wl-copy` sopravvive alla morte del gruppo del chiamante | L3 | Sì |
| PNG dagli appunti, sessione sway | L3 | File salvato, path consegnato |
| WebP dagli appunti | L3 | Convertito in PNG, conversione registrata nel log |
| File copiato da un file manager | L3 | Usato il path esistente, nessuna copia creata |
| Consegna su GNOME Wayland | L3 | Path negli appunti, la notifica spiega di premere Ctrl+V |
| `wtype` su sway | L3 | Invocato con successo |
| Cattura area con `grim` via `--screenshot` | L3 | Area 200x150 catturata, PNG valido |
| Resize da 4000x3000 a 1568x1176 | L3 | Dimensioni corrette, un solo file su disco, nessun intermedio residuo |
| `make install` con `PREFIX` e `DESTDIR` | L2 | Albero corretto, `$HOME` non toccata |
| `make deb` costruisce il pacchetto | L3 | Costruito con dpkg-deb 1.22 e ispezionato: directory radice 0755, eseguibile, documentazione ed esempio di configurazione presenti, `Version` presa dalla costante del sorgente, nessuno staging residuo in `/tmp` |

## Non verificato

| Caso | Perché | Cosa lo chiuderebbe |
|---|---|---|
| Scorciatoia che scatta davvero su **KDE Plasma** | Nessuna macchina disponibile | Eseguire `bash install.sh` su KDE e premere la scorciatoia. Il contenuto scritto in `kglobalshortcutsrc` è coperto da test L2; che kglobalaccel lo raccolga, no |
| **GNOME Wayland come sessione di login** | Provato forzando le variabili d'ambiente dentro sway annidato | Uscire, scegliere la sessione Wayland, installare, premere la scorciatoia. In particolare: se `gsd-media-keys` termini il process group dello script che lancia, che è il caso contro cui difende `setsid` |
| **Hyprland, i3, river** | Solo la riga di configurazione generata è coperta da test L1 | Incollare la riga stampata da `--print-shortcut`, ricaricare, premerla |
| Consegna con `ydotool` | Richiede un daemon con accesso a `/dev/uinput`, deliberatamente non configurato | Impostare `TYPING_BACKEND=ydotool` con il daemon in esecuzione |
| Annotazione con `satty` e `swappy` | Nessuno dei due installato sulla macchina di sviluppo | `paste-image --annotate` con uno dei due presente |
| Cattura con `spectacle`, `flameshot`, `maim`, `scrot` | Non installati; solo la selezione dello strumento è coperta da L1 | `paste-image --screenshot` con ciascuno presente |
| Conversione **AVIF** | ImageMagick 6 sulla macchina di sviluppo non ha il delegate AVIF | Stessa prova del WebP, su un sistema con ImageMagick 7 |
| Fedora, Arch, openSUSE | Sono stati esercitati solo i nomi dei pacchetti Debian e Ubuntu | Eseguire l'installer e controllare i nomi dei pacchetti che propone |
| **Installazione** del `.deb` | Il pacchetto è stato costruito e ispezionato, mai installato: significherebbe scrivere in `/usr` sulla macchina di sviluppo | `sudo dpkg -i dist/cli-image-paste_*_all.deb`, poi `paste-image --doctor` |
| **PKGBUILD** | `makepkg` non è disponibile qui, quindi la suite controlla solo il campo della versione | `makepkg -si` in un chroot pulito, meglio se con `namcap` sul risultato |
| **flake.nix** | `nix` non è installato sulla macchina di sviluppo | `nix build .#default` e poi `./result/bin/paste-image --doctor`, che esercita anche il wrapper del PATH |

## Segnalazioni

Se uno dei casi non verificati fallisce, `paste-image --doctor` stampa
l'ambiente rilevato, il backend di consegna scelto e gli strumenti
disponibili. Allegare quell'output fa la differenza fra una segnalazione a cui
si può rispondere e una a cui non si può.
