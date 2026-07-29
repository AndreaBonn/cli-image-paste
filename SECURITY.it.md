> **Lingua:** Italiano | [English](SECURITY.md)
>
> **Vedi anche:** [README (IT)](README.it.md) · [README (EN)](README.md)

# Politica di Sicurezza

## Versioni Supportate

| Versione | Supportata         |
| -------- | ------------------ |
| latest   | :white_check_mark: |

## Segnalare una Vulnerabilità

Se scopri una vulnerabilità di sicurezza in cli-image-paste, ti chiediamo di segnalarla in modo responsabile.

**Non aprire una issue pubblica su GitHub per vulnerabilità di sicurezza.**

Invece, invia un'email al maintainer con:

1. Una descrizione della vulnerabilità
2. I passaggi per riprodurre il problema
3. L'impatto potenziale
4. Un suggerimento per la correzione (opzionale)

Puoi aspettarti una risposta iniziale entro 72 ore. Lavoreremo con te per comprendere il problema e coordinare una correzione prima di qualsiasi divulgazione pubblica.

## Considerazioni sulla Sicurezza

Questo tool interagisce con diversi componenti a livello di sistema. Gli utenti dovrebbero essere consapevoli di quanto segue:

### Accesso agli Appunti

- Il tool legge i dati immagine dalla clipboard X11 usando `xclip`
- Il contenuto degli appunti viene salvato come file temporanei in `/tmp`
- I file temporanei vengono automaticamente eliminati dopo 7 giorni

### Simulazione della Tastiera

- `xdotool` viene usato per digitare il percorso del file nella finestra del terminale attivo
- Il tool registra e ripristina il focus della finestra durante l'operazione
- Viene digitato solo il percorso del file generato — nessun altro input viene simulato

### Cosa viene digitato nel terminale

Tutto ciò che viene digitato in un terminale è input di shell. È stato
verificato empiricamente: `xdotool type` sintetizza il keysym `Return` per un
carriage return e `Linefeed` per un line feed, quindi un carattere di controllo
dentro un percorso equivale a premere Invio nel prompt a cui il tool sta
mirando.

- Ogni stringa destinata al terminale passa prima dalla validazione: percorso
  assoluto, nessun carattere di controllo C0/C1, nessun override o isolate
  bidirezionale Unicode (che non eseguono nulla ma mentono su ciò che si legge)
- Un percorso che non passa la validazione viene rifiutato, non digitato
- I percorsi presi da `text/uri-list` o `x-special/gnome-copied-files` vengono
  decodificati **prima** della validazione, perché `%0D` diventa un carriage
  return solo dopo
- Viene accettato solo lo schema `file://`

### File di configurazione

- Il file viene **letto e analizzato, mai eseguito**. Sorgiare un file di
  configurazione sarebbe esecuzione di codice arbitrario a ogni pressione
  della scorciatoia
- Solo le chiavi in whitelist vengono accettate; chiavi ignote e valori non
  validi finiscono nel log e vengono scartati, mai applicati in silenzio
- Il template di formato dell'output ha la validazione più stretta: whitelist
  di caratteri, esattamente un `%s`, limite di lunghezza. A differenza di un
  percorso, che arriva una volta sola, un template ostile viene digitato a
  ogni singola invocazione e persiste
- La sostituzione è un rimpiazzo letterale di stringa, mai `printf` con il
  template come stringa di formato

### Conversione delle immagini

Il contenuto degli appunti può essere ostile, e ImageMagick ha una storia di
delegate che eseguono comandi (CVE-2016-3714) e di coder che leggono file
arbitrari.

- Viene usata una policy restrittiva dedicata tramite `MAGICK_CONFIGURE_PATH`,
  non quella di sistema, che su alcune distribuzioni è assente e su altre
  permissiva. I delegate sono disabilitati, insieme ai coder MSL, MVG,
  EPHEMERAL, URL, HTTP(S), FTP, TEXT, SHOW, WIN e PLT
- I limiti di risorsa vengono passati sulla riga di comando come difesa in
  profondità contro le decompression bomb
- Gli SVG sono rasterizzati con `rsvg-convert`, uno strumento a scopo singolo,
  invece del delegate generico
- Gli argomenti sono passati come lista, mai interpolati in una stringa di shell

### Digitazione su Wayland

`ydotool` sa digitare su qualunque compositore, ed è disponibile solo per
configurazione esplicita. Non viene mai scelto automaticamente.

Richiede un daemon con accesso a `/dev/uinput`. Chi riesce a raggiungere quel
daemon può iniettare tasti in **qualunque** applicazione della sessione,
compresi i prompt di sudo e le finestre dei gestori di password: questo annulla
l'isolamento dell'input, che è il principale miglioramento di sicurezza di
Wayland rispetto a X11. Se lo attivi, verifica che il suo socket sia
accessibile al solo proprietario, e preferisci un daemon per utente
all'aggiunta del tuo account a un gruppo di sistema.

### Gestione dei file temporanei

- I file sono creati con `mktemp`, in modo atomico, per prevenire race condition
- I permessi sono impostati a `600` (lettura e scrittura solo per il proprietario)
- `umask 077` è impostata esplicitamente invece di affidarsi al valore
  ereditato, che è comunemente 022 e lascerebbe la directory di stato leggibile
  da tutti
- Ogni file intermedio della pipeline ha il proprio `mktemp`, mai un nome
  derivato dall'originale per manipolazione di stringa, e viene rimosso appena
  non serve più invece di scadere insieme al risultato. La pipeline moltiplica
  le copie di contenuto che può essere lo screenshot di un gestore di password

### Consegna tramite appunti

Su GNOME Wayland il percorso viene scritto negli appunti testuali, e questo
**sovrascrive quello che c'era**. È perdita di dati, non una vulnerabilità, ma
vale la pena saperlo: se avevi copiato una password, non c'è più. La notifica
lo dichiara esplicitamente.

### Installazione

- L'installer potrebbe richiedere `sudo` per installare le dipendenze di sistema tramite il gestore pacchetti
- Lo script principale viene installato in `~/.local/bin/` (spazio utente, non richiede root)
- Le scorciatoie da tastiera GNOME vengono configurate tramite `gsettings` (spazio utente)

### Logging

- I log sono salvati in `~/.local/state/paste-image/` con permessi solo per l'utente
- I log contengono percorsi file e timestamp — nessun contenuto degli appunti viene registrato
- La rotazione dei log è applicata per prevenire una crescita illimitata (max 500 righe, mantiene ultime 250)
- Scritture sicure contro race condition tramite `flock` prevengono corruzione log in scenari concorrenti

## Buone Pratiche per gli Utenti

- Rivedi lo script prima dell'installazione: `cat install.sh` e `cat paste-image`
- Mantieni aggiornate le dipendenze di sistema
- Usa un gestore di appunti dedicato se gestisci frequentemente dati sensibili
- Il tool funziona solo sotto X11 — Wayland non è supportato
- I file temporanei vengono automaticamente eliminati dopo 7 giorni
- Controlla periodicamente i log: `cat ~/.local/state/paste-image/paste_image.log`
- Esegui la suite di test per verificare l'integrità: `bash tests/run_tests.sh`
