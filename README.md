# DroidBridge

App nativa per macOS (SwiftUI) per sfogliare lo storage di un telefono Android e trasferire file da e verso il Mac.

## Requisiti

- macOS 13 o successivo
- Xcode oppure Command Line Tools (`xcode-select --install`)
- adb: `brew install android-platform-tools` (oppure le Platform-Tools di Google, con `adb` copiato in `/usr/local/bin`)
- Sul telefono: Opzioni sviluppatore → **Debug USB** attivo

## Compilare e avviare

```bash
git clone https://github.com/DaboPrint3DTech/droidbridge.git
cd droidbridge
chmod +x build.sh
./build.sh
open DroidBridge.app
```

In alternativa: `swift run` dalla cartella del progetto.

## Installare l'app (Launchpad, Dock, Spotlight)

`build.sh` crea `DroidBridge.app` nella cartella del progetto. Per averla nel Launchpad come le altre app, copiala in `/Applications`:

```bash
./build.sh
rm -rf /Applications/DroidBridge.app
ditto DroidBridge.app /Applications/DroidBridge.app
```

Dopo qualche secondo DroidBridge compare nel Launchpad; si trova anche con Spotlight (⌘-spazio, "DroidBridge"). Per tenerla nel Dock: aprila, clic destro sull'icona nel Dock → Opzioni → Mantieni nel Dock.

Se l'icona non compare subito, forza la registrazione dell'app:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/DroidBridge.app
```

**Aggiornare:** dopo ogni modifica al codice la copia in `/Applications` non cambia da sola. Rilancia i tre comandi sopra (compila, rimuovi la vecchia, copia la nuova).

**Disinstallare:** `rm -rf /Applications/DroidBridge.app` (le miniature in cache restano in `~/Library/Caches/DroidBridge`, cancellabili a mano).

L'app è firmata ad-hoc, quindi è pensata per il Mac su cui la compili. Se la copi su un altro Mac, al primo avvio macOS può bloccarla: clic destro sull'app → Apri, oppure Impostazioni di Sistema → Privacy e sicurezza → Apri comunque.

## Uso

1. Collega il telefono via USB e accetta la richiesta di debug USB.
2. Il dispositivo appare nella barra laterale.
3. Doppio clic su una cartella per aprirla. Doppio clic su un'immagine per vederla in galleria, su altri file per scaricarli in Download.
4. Trascina file nella finestra per inviarli al telefono; la barra degli strumenti permette di scaricare, creare cartelle ed eliminare, il menu contestuale (clic destro) di rinominare.

### Albero delle cartelle

Sotto il nome del telefono, nella barra laterale, c'è l'alberatura della memoria interna. Un clic su una cartella la apre nel pannello principale. La freccia a sinistra espande o chiude i rami: le sottocartelle vengono lette dal telefono solo quando servono. Navigando dal pannello principale (doppio clic, "cartella superiore"), l'albero si apre da solo fino alla cartella in cui ti trovi, che resta evidenziata.

### Informazioni sull'app

In fondo alla barra laterale c'è la voce "Informazioni su DroidBridge", disponibile anche dal menu dell'app. Mostra versione, creatore, versione e percorso di adb e il sistema operativo. I dati dell'app (creatore, anno, descrizione) sono tutti in `Sources/DroidBridge/AppInfo.swift`; la versione si cambia in `build.sh`.

### Logo e icona

Il logo (uno smartphone che si collega a un iMac) è in `Resources/AppIcon.png` (1024×1024) con il sorgente vettoriale `Resources/AppIcon.svg`. `build.sh` lo trasforma in `AppIcon.icns` e lo mette nel pacchetto, quindi compare nel Dock, nel Finder, nella finestra Informazioni e nella schermata "Collega il tuo telefono". Per cambiarlo basta sostituire `AppIcon.png` con un'altra immagine quadrata da 1024 px e rilanciare `./build.sh`. Con `swift run` l'app non è un pacchetto e mostra l'icona generica.

### Viste

Il selettore nella barra degli strumenti cambia vista:

- **Lista**: tabella con Nome, Dimensione, Tipo, Modificato. Le immagini hanno una piccola miniatura accanto al nome.
- **Griglia**: icone grandi con anteprima delle immagini. Lo slider in basso regola la dimensione. ⌘-clic aggiunge o toglie dalla selezione, ⇧-clic seleziona un intervallo.
- **Galleria**: immagine grande al centro, striscia di miniature sotto. Frecce ← → (o i pulsanti ai lati) per scorrere le immagini; clic su una miniatura per saltarci.

L'interruttore "Anteprime" in basso disattiva le miniature in lista e griglia.

### Filtro e ordinamento

- Il campo di ricerca nella barra degli strumenti filtra per nome.
- Il menu "Filtra per tipo" mostra solo cartelle, immagini, video, audio, documenti o altri file.
- In lista, un clic sull'intestazione di una colonna ordina per quella colonna, un secondo clic inverte il verso.
- Il menu "Ordina" fa lo stesso in tutte le viste e permette di tenere o no le cartelle per prime.
- Le azioni (scarica, elimina, rinomina) agiscono solo sugli elementi visibili: quello che è nascosto da un filtro non viene toccato.

### Anteprime e cache

Per fare un'anteprima l'app scarica l'immagine dal telefono, la ridimensiona e conserva solo la miniatura in `~/Library/Caches/DroidBridge`. Le anteprime si generano solo per ciò che è visibile sullo schermo. Dal menu in basso a destra (⋯) puoi svuotare la cache.

## Limiti

- Usa ADB, non MTP: serve il Debug USB attivo.
- Non monta il telefono come unità nel Finder.
- Il trascinamento dalla finestra al Finder non è implementato: usa "Scarica".
- Il progresso dei trasferimenti è indeterminato (spinner).
- Le anteprime ci sono solo per le immagini: per i video si vede l'icona.
- Cartelle con molte foto grandi richiedono tempo alla prima apertura, perché ogni foto va scaricata una volta per ricavarne la miniatura.
