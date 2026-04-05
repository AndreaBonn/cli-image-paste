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

### Gestione dei File Temporanei

- I file vengono creati usando `mktemp` con operazioni atomiche per prevenire race condition
- I permessi dei file sono impostati a `600` (lettura/scrittura solo per il proprietario)
- I pattern prevedibili nei nomi dei file sono mitigati dal suffisso casuale di `mktemp`
- Formato: `/tmp/paste_image_YYYYMMDD_HHMMSS_RANDOM.EXT` dove RANDOM è un suffisso di 6 caratteri

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
