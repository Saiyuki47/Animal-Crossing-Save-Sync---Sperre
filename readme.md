# AC-SaveSync

Ein kleines PowerShell-Tool mit grafischer Oberfläche, mit dem **zwei (oder mehr) Freunde
abwechselnd denselben Animal-Crossing-Spielstand im Dolphin-Emulator spielen können** –
ohne Spielstände von Hand hin- und herzuschicken.

Der gemeinsame Spielstand liegt in einem privaten Git-Repository (z. B. auf GitHub). Das
Skript kümmert sich vor und nach jeder Spielsitzung automatisch um alles: neuesten Stand
holen, den Platz „reservieren", Dolphin (samt Mods) starten, und beim Beenden den Stand
sichern und wieder hochladen. Zusätzlich sperrt es das gleichzeitige Spielen und schreibt
die Spielzeiten jedes Spielers in die Repo-README.

> Auch wenn im Namen „Animal Crossing" steckt: Das Tool funktioniert mit jedem
> Wii-/GameCube-Spiel in Dolphin, das mit einem Datei-basierten Spielstand arbeitet.

---

## Inhalt

- [Wie es funktioniert](#wie-es-funktioniert)
- [Voraussetzungen](#voraussetzungen)
- [Erste Einrichtung](#erste-einrichtung)
- [Die Oberfläche im Detail](#die-oberfläche-im-detail)
- [Täglicher Ablauf](#täglicher-ablauf)
- [Die Sperre (kein dauerhaftes Aussperren möglich)](#die-sperre)
- [Spielstände: Was wird kopiert?](#spielstände-was-wird-kopiert)
- [Spielzeit-Statistik](#spielzeit-statistik)
- [Rübenkurs](#rübenkurs)
- [Wo liegt die Konfiguration?](#wo-liegt-die-konfiguration)
- [Fehlerbehebung](#fehlerbehebung)
- [Grenzen & Hinweise](#grenzen--hinweise)
- [Tests](#tests)
- [Lizenz](#lizenz)

---

## Wie es funktioniert

Das Grundprinzip ist bewusst simpel: **Es gibt immer nur einen echten Spielstand**, und der
liegt im Git-Repo. Euer lokaler Dolphin-Ordner ist nur eine Arbeitskopie.

Bei jedem Start und Ende läuft grob das hier ab:

**Beim Starten:**
1. Neuesten Stand aus dem Repo holen.
2. Prüfen, ob gerade jemand spielt (Sperre). Wenn ja → Abbruch mit Hinweis.
3. Sonst: Sperre auf den eigenen Namen setzen und hochladen.
4. Spielstand aus dem Repo in den Dolphin-Save-Ordner schreiben.
5. Dolphin (bzw. deine Mod-Verknüpfung) starten.

**Während des Spielens** (alle paar Sekunden, standardmäßig jede Minute – „Herzschlag"):
- Spielstand + Spielzeit sichern und hochladen, Sperre auffrischen. So geht bei einem Absturz
  höchstens die Zeit seit dem letzten Herzschlag verloren. Speichert das Spiel gerade, wartet
  der Herzschlag ein paar Sekunden, damit keine halb geschriebene Datei im Repo landet.

**Beim Beenden von Dolphin:**
1. Spielstand aus dem Dolphin-Ordner zurück ins Repo spiegeln.
2. Spielzeit-Statistik aktualisieren.
3. Sperre freigeben, alles committen und hochladen.

---

## Voraussetzungen

- **Windows** mit PowerShell (5.1 oder neuer – bei Windows 10/11 bereits vorhanden).
- **Git** installiert und im PATH. Test in PowerShell: `git --version`.
- **Dolphin-Emulator** und das Spiel liegen bereit.
- Ein **gemeinsames privates Git-Repo** (z. B. GitHub), auf das beide Zugriff haben.
- **Gespeicherte Git-Zugangsdaten**, damit das Skript ohne Passwort-Abfrage pushen kann:
  - bei HTTPS: der Git Credential Manager (wird mit Git für Windows mitinstalliert),
  - oder ein hinterlegter SSH-Schlüssel.
- Beide Mitspieler benutzen dasselbe Skript, aber mit **unterschiedlichem Spielernamen**.

---

## Erste Einrichtung

Es gibt eine „erste Person", die das Repo mit ihrem Spielstand anlegt, und die „zweite Person",
die es nur klont. Beides geht bequem über den Knopf **„Repo einrichten…"**.

### Schritt 0 – Skript starten

**Der bequeme Weg:** Unter [Releases](../../releases) die Datei **`AC-SaveSync.cmd`**
herunterladen und **doppelklicken**. Fertig. Diese Datei enthält das komplette
Skript und startet PowerShell selbst – eine separate `.ps1` braucht ihr nicht.
Beim ersten Start fragt Windows einmal nach, ob die Datei aus dem Internet
ausgeführt werden darf; das ist normal (ggf. Rechtsklick → *Eigenschaften* →
*Zulassen* → *OK*).

**Wenn ihr das Repo geklont habt:** Rechtsklick auf `AC-SaveSync.ps1` →
**„Mit PowerShell ausführen"**. Alternativ in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\AC-SaveSync.ps1
```

Die `.cmd` lässt sich jederzeit selbst bauen:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Build-Cmd.ps1
```

**Zum Symbol:** Eine `.cmd`-Datei kann kein eigenes Symbol tragen – Windows legt das
für alle Dateien dieser Art gemeinsam über die Dateizuordnung fest. Das Programm bietet
deshalb beim ersten Start an, eine **Verknüpfung mit Symbol auf dem Desktop** anzulegen
(später jederzeit über **„Erweitert…"**). Fenster und Taskleiste tragen das Symbol
ohnehin.

Das Symbol kommt aus `icon.ico` im Projektordner. Zum Austauschen einfach diese Datei
ersetzen und danach ausführen:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Set-Icon.ps1
```

Das schreibt `assets/ac-savesync.ico` (verlustfrei, aber PNG-komprimiert – aus 360 KB
werden 46 KB) und trägt es gleich ins Skript ein.

### Schritt 1 – Der Assistent

Beim **allerersten Start** führt euch ein Assistent in vier Schritten durch das Nötigste:
Begrüßung samt Prüfung, ob Git installiert ist (mit Download-Link, falls nicht), euer Name,
Dolphin und Spielstand-Ordner (beides schon vorausgefüllt) und zum Schluss der gemeinsame
Ordner. Wer die Adresse des gemeinsamen Repos schon hat, fügt sie dort ein und klickt
**„Jetzt holen"** – dann ist alles fertig und die Abschnitte unten sind nicht mehr nötig.

Wer das Repo erst noch anlegen muss, lässt den letzten Schritt leer und macht danach wie
unten beschrieben weiter. Der Assistent erscheint nur einmal; alles lässt sich später im
Hauptfenster ändern.

### Schritt 2 – Der gemeinsame Ordner

Klickt im Hauptfenster auf **„Repo einrichten…"**. Das Fenster fragt zuerst, **wer ihr seid**,
und zeigt danach nur noch die Schritte, die für euch gelten. Ihr müsst also nicht raten,
welcher Knopf für wen ist.

**„Ich bin der Erste – ich lege ihn an"** (einer von euch beiden):

1. **„github.com/new öffnen"** – dort ein Repo anlegen, auf **Private** stellen und
   **keinen Haken** bei „Add a README file" setzen (der Ordner muss leer sein).
   Habt ihr die **GitHub CLI** (`gh`) installiert und angemeldet, erledigt
   **„Automatisch anlegen"** das für euch.
2. Die Adresse des neuen Repos einfügen und den Ordner auf eurem PC wählen.
3. **„Einrichten und hochladen"** – legt das lokale Repo an, verbindet es und lädt euren
   Spielstand hoch (dafür muss der **Save-Ordner** eingetragen sein). Danach
   **„Adresse kopieren"** und dem Mitspieler schicken.

**„Mein Mitspieler hat ihn schon – ich hole ihn mir"** (der andere):

1. Die Adresse einfügen, die ihr bekommen habt.
2. Einen leeren oder neuen Ordner auf eurem PC wählen.
3. **„Jetzt holen"** – fertig.

> Achtung für die zweite Person: Es wird der Spielstand des Ersten geholt. Ein eigener
> Spielstand auf diesem PC wird dabei **nicht** hochgeladen. Beim ersten „Spielen starten“
> wird er aber gesichert, bevor er dem gemeinsamen Stand weicht (`%APPDATA%\AC-SaveSync\ersetzt\`).

---

## Die Oberfläche im Detail

### Eingabefelder

| Feld                  | Bedeutung                                                                                                                             |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| **Dolphin.exe**       | Pfad zur `Dolphin.exe`. Wird ignoriert, wenn du bei „Spiel" eine `.lnk`-Verknüpfung angibst (dann kommt Dolphin aus der Verknüpfung). |
| **Repo-Ordner**       | Der lokale Ordner des geklonten Git-Repos (der gemeinsame Spielstand).                                                                |
| **Spiel** (optional)  | Was gestartet werden soll (siehe unten). Leer = Dolphins normale Oberfläche öffnet sich.                                              |
| **Save-Ordner**       | Der Ordner, in dem Dolphin die Speicherdaten **dieses Spiels** ablegt.                                                                |
| **Dein Name**         | Dein Spielername – für Sperre und Spielzeit-Statistik. Muss sich vom Mitspieler unterscheiden.                                        |

**Dolphin.exe** und **Save-Ordner** werden beim ersten Start automatisch gesucht und
vorausgefüllt – beim Save-Ordner wird gezielt der Animal-Crossing-Ordner erkannt.

Änderungen werden **automatisch gespeichert**, einen Speichern-Knopf gibt es nicht mehr.

Unter **„Erweitert…"** liegen die selten gebrauchten Werte:

| Feld                  | Bedeutung                                                                                      |
| --------------------- | ---------------------------------------------------------------------------------------------- |
| **Spielfotos-Ordner** | Der Ordner, in dem Dolphin die Fotos aus dem Spiel ablegt (z. B. `…\Load\WiiSDSync`). Nach dem Spielen werden neue Fotos daraus in den gemeinsamen Ordner **kopiert** – die Originale bleiben, wo sie sind. Schon geteilte und im Album gelöschte Fotos kommen nicht noch einmal. Sind es mehr als 30 neue Fotos (oder über 100 MB) auf einmal, fragt das Programm vorher. Deinen Windows-Ordner „Bilder“, Desktop, Dokumente, Downloads, OneDrive, den Benutzerordner und ganze Laufwerke lehnt es ab. Leer = aus. |
| **Branch**            | Git-Branch, meist `main`.                                                                      |
| **Sperre gilt (Min)** | Nach so vielen Minuten ohne Herzschlag gilt deine Sperre als abgelaufen (Standard 5). Der Wert steht in der Sperre selbst – dein Mitspieler richtet sich danach, auch wenn er selbst etwas anderes eingestellt hat. |
| **Herzschlag (Sek)**  | Abstand, in dem während des Spielens gesichert und die Sperre aufgefrischt wird (Standard 60). Höchstens ein Drittel von „Sperre gilt" – ein längerer Wert wird automatisch begrenzt. |

**Zum Feld „Spiel":** Das Skript erkennt automatisch, was du angibst:
- eine **Spiel-/Preset-Datei** (`.iso`, `.wbfs`, `.rvz`, `.gcm`, `.ciso`, `.json`) →
  wird an Dolphin übergeben (`-e "…"`),
- eine **Verknüpfung** (`.lnk`) → wird aufgelöst und Dolphin genau mit deren Argumenten
  gestartet (ideal, wenn deine Verknüpfung ein Mod-Preset lädt),
- ein **Programm** (`.exe`, `.bat`, `.cmd`) → wird direkt ausgeführt.

**Zum Feld „Save-Ordner":** Gib den Ordner an, der **genau die Speicherdaten dieses einen
Spiels** enthält – bei Dolphin typischerweise:

```
...\Dolphin-x64\Wii\title\00010000\<Spiel-ID>\
```

Am besten den Ordner **eine Ebene über `data`** wählen (also den, in dem `data` und `content`
nebeneinander liegen), dann ist garantiert alles dabei. **Nicht** den kompletten Wii-NAND
angeben – sonst würden auch die Spielstände anderer Spiele mitsynchronisiert. Sieht der
eingetragene Ordner danach aus (z. B. `Wii`, `title`, `00010000` oder ein Ordner mit mehreren
Spielen darin), warnt das Programm vor dem Hochladen und im **Selbsttest**. Der Ordner `GC`
wird bewusst nicht beanstandet – bei GameCube-Spielen liegen dort die Memory-Card-Dateien.

### Knöpfe

| Knopf                          | Funktion                                                                                         |
| ------------------------------ | ------------------------------------------------------------------------------------------------ |
| **Spielen starten**            | Holt den Stand, setzt die Sperre, schreibt den Save in den Dolphin-Ordner und startet das Spiel. |
| **Spielen beenden**            | Beendet Dolphin aus dem Programm heraus und schließt die Sitzung ab: sichern, hochladen, Sperre freigeben. **Vorher im Spiel speichern!** Nur während einer laufenden Sitzung anklickbar. |
| **Status prüfen**              | Aktualisiert die Anzeige: frei, du spielst, jemand anderes spielt, oder abgelaufene Sperre. Läuft beim Programmstart automatisch einmal. |
| **Fotos ansehen**              | Zeigt die Bilder aus dem gemeinsamen Ordner direkt im Programm – neueste zuerst, mit Name und Aufnahmezeit. Blättern per Knopf oder Pfeiltasten, dazu Diashow, Speichern und Löschen. |
| **Spielzeit**                  | Wer hat wie lange gespielt – gesamt, Woche für Woche und die Rekorde (längste Sitzung, Spieltage am Stück). Mehr dazu unter [Spielzeit-Statistik](#spielzeit-statistik). |
| **Rübenkurs**                  | Rübenpreise der Woche gemeinsam eintragen. Zeigt, welches Kursmuster wahrscheinlich läuft, welche Preise noch möglich sind, ob ihr verkaufen oder warten solltet, und euren Gewinn. Mehr dazu unter [Rübenkurs](#rübenkurs). |
| **Früherer Spielstand**        | Holt einen älteren Spielstand zurück. Der jetzige bleibt dabei erhalten. Die Rettung, wenn im Spiel etwas schiefgegangen ist. |
| **Selbsttest**                 | Prüft alles Nötige der Reihe nach (Git, deine Angaben, Dolphin, Save-Ordner, gemeinsamer Ordner, Verbindung zum Server) und sagt zu jedem Problem, was zu tun ist. Erster Anlaufpunkt, wenn etwas nicht klappt. |
| **Sperre erzwingen freigeben** | Notausgang: entfernt eine hängende Sperre (nur benutzen, wenn sicher niemand spielt).            |
| **Erweitert…**                 | Selten gebrauchte Einstellungen: Spielfotos-Ordner, Branch, Sperre, Herzschlag. Dort liegt auch **„Verknüpfung auf dem Desktop anlegen"**. |
| **Repo einrichten…**           | Öffnet den Einrichtungs-Dialog (anlegen / verbinden / klonen).                                   |

„Spielen starten" ist gesperrt, solange etwas Wichtiges fehlt. Fahre mit der Maus über den
Knopf, dann steht dort, **was** fehlt.

### Wenn etwas schiefgeht

- **Das Fenster friert nicht ein.** Hochladen, Abgleichen und Kopieren laufen im Hintergrund.
  Dauert etwas länger als einen Augenblick, erscheint neben „Protokoll:" eine Leiste, die sagt,
  was gerade passiert (z. B. „Lade auf den Server hoch … (12 s)"). Solange sie läuft, nimmt das
  Programm keine Klicks an, damit nichts doppelt ausgelöst wird. Schließt du das Fenster in dieser
  Zeit, wartet es, bis der Vorgang fertig ist, und schließt sich dann selbst. Antwortet der
  Server gar nicht mehr, bricht das Programm nach einigen Minuten ab und sagt, woran es liegt.
- **Die Anzeige hält sich selbst aktuell.** Solange ihr nicht spielt, sieht das Programm alle
  drei Minuten nach, ob der andere angefangen oder aufgehört hat.
- **Reißt beim Spielen die Verbindung ab**, meldet sich das Programm deutlich: Es kann dann
  nichts mehr hochladen, und nach „Sperre gilt (Min)" darf der andere übernehmen. Damit du
  es auch im Vollbild mitbekommst, gibt es einen Warnton, und der Knopf in der Taskleiste
  blinkt. Wichtige Meldungen während des Spielens (etwa „Sperre verloren“) erscheinen über
  Dolphin.
- **Das Programm läuft nur einmal.** Ein zweiter Doppelklick holt das schon offene Fenster
  nach vorn, statt ein zweites zu öffnen – zwei würden sich beim Spielstand in die Quere kommen.
- **Nicht hochgeladener Fortschritt wird nicht mehr stillschweigend verworfen.** Liegt beim
  Abgleich noch etwas auf eurem PC – etwa nach einem Absturz –, fragt das Programm nach. Die
  Frage nennt auch noch nicht hochgeladene Fotos. Die gehen selbst bei „Stand vom Server holen“
  nicht verloren: Sie bleiben im gemeinsamen Ordner und werden beim nächsten Mal hochgeladen.
- **Kein halber Spielstand im Repo.** Lässt sich der Spielstand vor dem Spielen nicht in den
  Dolphin-Ordner schreiben, startet Dolphin gar nicht erst. Lässt er sich nach dem Spielen nicht
  sichern (z. B. weil Dolphin die Dateien noch festhält), fragt das Programm nach; die Sperre
  bleibt so lange bei dir, bis der Stand wirklich oben ist.
- **Verlorene Sperre wird sofort gemeldet.** Übernimmt dein Mitspieler die Sperre, weil eine
  Weile nichts von dir ankam, oder wird sie von Hand freigegeben, merkt das Programm es beim
  nächsten Herzschlag und sagt es dir deutlich. Ab dann lädt es nichts mehr hoch; beim Beenden
  landet eine Kopie deines Spielstands in `%APPDATA%\AC-SaveSync\gerettet\`. Sprecht euch
  dann ab, wessen Stand weitergilt.
- **Während der andere spielt,** lassen sich weder ein früherer Spielstand zurückholen noch
  Fotos löschen – beides würde sonst seine Sitzung vom Server abschneiden.
- **Ein Protokoll jedes Programmlaufs** liegt unter `%APPDATA%\AC-SaveSync\logs\`. Die letzten
  zehn bleiben erhalten, ältere werden automatisch gelöscht. Bewusst außerhalb des gemeinsamen
  Ordners, damit es nicht beim Mitspieler landet.

### Updates

Das Programm sieht **beim Start selbst nach**, ob es eine neuere Fassung gibt. Wenn ja,
fragt es kurz nach – ein Klick genügt, dann lädt es sich die neue Version, ersetzt sich
selbst und startet neu. Herunterladen von Hand ist nicht mehr nötig.

Wer zwischendurch nachsehen will: **„Erweitert…" → „Nach Updates suchen"**. Dort steht
auch, welche Version gerade läuft (ebenso im Fenstertitel).

Vor dem Ersetzen wird die heruntergeladene Datei geprüft – Größe, Aufbau und ob der
enthaltene Code fehlerfrei ist. Fällt eine dieser Prüfungen durch, bleibt die vorhandene
Fassung unangetastet. Die alte Datei wird zusätzlich als Sicherungskopie abgelegt
(`%APPDATA%\AC-SaveSync\update\`).

Ohne Internet passiert beim Start nichts Sichtbares – die Prüfung wird still übersprungen.

### Darstellung

Das Fenster passt sich der Bildschirmskalierung an: Bei 150 % wird alles größer und
bleibt scharf, statt wie ein Foto hochgezogen zu werden. Maßgeblich ist der Hauptbildschirm.
Auf einem zweiten Bildschirm mit anderer Skalierung stimmt die Größe ebenfalls – dort passt
Windows das Fenster an, die Schrift wirkt dann etwas weicher.

Wer es unabhängig davon größer oder kleiner will, kann den Faktor selbst vorgeben –
dazu vor dem Start die Umgebungsvariable `ACSS_UI_SCALE` setzen (erlaubt sind 0,5 bis 4):

```powershell
$env:ACSS_UI_SCALE = "1.5"
```

### Statusanzeige (Farben)

- **Grün** – frei, du kannst spielen.
- **Blau** – du hältst gerade die Sperre.
- **Rot** – jemand anderes spielt gerade.
- **Gelb** – abgelaufene Sperre, kann übernommen werden.

### Protokoll

Das große Textfeld unten zeigt im Klartext, was das Skript tut. Bei Problemen ist das die
erste Stelle zum Nachschauen.

---

## Täglicher Ablauf

1. Skript starten. Der Status wird dabei automatisch geprüft – ihr seht also
   sofort, ob gerade jemand spielt.
2. **„Status prüfen"** nur, wenn ihr die Anzeige zwischendurch aktualisieren wollt.
3. **„Spielen starten"** – Dolphin öffnet sich mit dem aktuellen gemeinsamen Stand.
4. Ganz normal spielen und im Spiel speichern.
5. Im Spiel speichern, dann entweder Dolphin schließen **oder** im Programm auf
   **„Spielen beenden"** drücken. Beides führt zum selben Ergebnis: Das Skript
   sichert automatisch, lädt hoch und gibt die Sperre frei.

Mehr ist im Alltag nicht nötig.

---

## Die Sperre

Damit nie zwei Leute gleichzeitig denselben Stand bespielen (und sich gegenseitig
überschreiben), legt das Skript beim Start eine Sperr-Datei (`PLAYING.lock`) im Repo an – mit
deinem Namen, **zwei** Zeitstempeln und deiner Sperrdauer:

- **Sitzungsbeginn** – bleibt die ganze Sitzung stehen. Nur dafür da, „spielt seit …" anzuzeigen.
- **Letzter Herzschlag** – wird laufend erneuert und entscheidet, ob die Sperre abgelaufen ist.
- **Sperrdauer** – dein Wert für „Sperre gilt (Min)". Für beide gilt die Dauer dessen, der
  spielt: Nach ihr richtet sich sein Herzschlag. Stellt nur einer von euch den Wert um, kann
  die Sperre des anderen so nicht zwischen zwei Herzschlägen als abgelaufen gelten.

**Ein dauerhaftes Aussperren ist ausgeschlossen**, gleich dreifach abgesichert:

- **Automatischer Ablauf:** Der Zeitstempel wird während des Spielens per Herzschlag
  aufgefrischt. Stürzt der PC ab, stoppt der Herzschlag – und nach „Sperre gilt (Min)" gilt die
  Sperre als tot. Wer danach auf „Spielen starten" klickt, wird gefragt, ob er sie übernehmen
  will – „abgelaufen" kann auch nur ein kurzer Netzausfall beim anderen sein.
- **Uhrzeit:** Ob eine Sperre abgelaufen ist, hängt an den Uhren beider PCs. Das Programm
  vergleicht beim Start die eigene Uhr mit GitHub und warnt, wenn sie spürbar falsch geht
  (ebenso im **Selbsttest**).
- **Aufräumen beim Beenden:** Schließt sich Dolphin normal, wird die Sperre sofort freigegeben.
- **Notausgang:** Der Knopf **„Sperre erzwingen freigeben"** entfernt sie von Hand.

Selbst wenn du das Fenster mitten in einer Sitzung schließt, wirst du gewarnt und die Sperre
läuft spätestens nach der eingestellten Zeit von allein ab.

---

## Spielstände: Was wird kopiert?

Der gemeinsame Spielstand liegt im Repo im Unterordner **`save/`**. Zwischen diesem Ordner und
deinem lokalen **Save-Ordner** kopiert das Skript automatisch:

- **Beim Start:** `save/` (aus dem Repo) → dein Dolphin-Save-Ordner.
  Es wird nur überschrieben, **nichts Fremdes gelöscht**.
- **Beim Beenden / Herzschlag:** dein Dolphin-Save-Ordner → `save/` (ins Repo), exakt gespiegelt.

**Sicherheitsnetze:**

- Liegt im Repo noch **kein** Spielstand (allererster Start), bleibt dein vorhandener
  Dolphin-Save unangetastet und wird stattdessen ins Repo hochgeladen.
- Ist dein Dolphin-Save-Ordner leer, wird der Repo-Stand **nicht** überschrieben.
- Bevor der Stand aus dem Repo deinen Dolphin-Ordner überschreibt, wird der bisherige Inhalt
  kopiert – nach `%APPDATA%\AC-SaveSync\ersetzt\`, die letzten zehn Kopien bleiben. Sind beide
  Stände gleich, entfällt die Kopie. So ist auch die eigene Stadt der zweiten Person noch da,
  die beim ersten Start dem gemeinsamen Stand weicht.
- Wurde deine letzte Sitzung nicht sauber beendet (Programm geschlossen oder abgestürzt,
  während Dolphin lief), fragt „Spielen starten“, welcher Stand gelten soll. Der im
  Dolphin-Ordner ist dann meist der neuere – etwa wenn du danach noch weitergespielt hast.

So „impft" die erste Person das Repo mit ihrem Spielstand, und ab dann arbeiten beide mit
demselben Stand.

---

## Spielzeit-Statistik

Das Skript schreibt die Spielzeiten in die **README des Repos** – auf GitHub als Tabelle
sichtbar. Gespeichert wird pro Spieler die Gesamtzeit, die Anzahl der Sitzungen und wann
zuletzt gespielt wurde:

| Spieler | Gesamt | Sitzungen | Zuletzt gespielt |
| ------- | ------ | --------- | ---------------- |
| Anna    | 4h 12m | 7         | 2026-07-30 20:15 |
| Max     | 3h 48m | 6         | 2026-07-29 21:02 |

Die Zeit wird auch bei jedem Herzschlag mitgerechnet, geht bei einem Absturz also fast nicht
verloren. Der Sitzungszähler erhöht sich nur beim sauberen Beenden.

Mehr zeigt der Knopf **„Spielzeit"** im Programm, auf drei Reitern:

- **Gesamt** – je Spieler Gesamtzeit, Sitzungen, längste Sitzung, Schnitt pro Sitzung und wann
  zuletzt gespielt.
- **Wochen** – die letzten acht Wochen (Kalenderwochen, Montag bis Sonntag) mit der Zeit je
  Spieler und einem Balken für die ganze Woche. Alle Balken haben denselben Maßstab und sind so
  direkt vergleichbar. Darunter steht der Schnitt pro Woche – gerechnet ab der Woche der ersten
  Sitzung und ohne die laufende Woche, damit er nicht zu niedrig ausfällt.
- **Rekorde** – längste Sitzung, meiste Spielzeit an einem Tag, längste Serie an Spieltagen am
  Stück und die Serie, die gerade läuft.

Diese Werte rechnet das Programm aus dem Git-Verlauf des gemeinsamen Ordners nach – aus den
Einträgen, die es beim Spielen ohnehin schreibt (Sperre, Herzschlag, Sitzungsende). Sie sind
also auch für ältere Sitzungen da, ohne dass etwas zusätzlich gespeichert wird. Bei einem
Absturz zählt die Sitzung bis zum letzten Herzschlag; ein Spieltag ist jeder Tag, an dem eine
Sitzung lief (auch über Mitternacht hinweg).

> Diese README (die du gerade liest) ist die Anleitung für das Tool. Die **README im Repo** ist
> etwas anderes: Sie wird vom Skript automatisch mit der Spielzeit-Tabelle erzeugt.

---

## Rübenkurs

Sonntags bis 12 Uhr verkauft Sigrid Rüben für 90 bis 110 Sternis. Von Montag bis Samstag kauft
Nook sie zurück – mit einem Preis vormittags und einem ab 12 Uhr. Am Sonntag darauf sind nicht
verkaufte Rüben verfault. Der Knopf **„Rübenkurs“** hilft, den besten Moment zu erwischen.

**Eintragen – jederzeit, auch während der andere spielt:**

- Sigrids Preis vom Sonntag, wie viele Rüben du gekauft hast und die Preise, die Nook zahlt. Es
  muss nicht alles ausgefüllt sein; jeder Preis macht die Einschätzung genauer.
- Ihr spielt dieselbe Stadt, also gilt für euch beide derselbe Kurs. Was einer einträgt, sieht
  der andere – auch Tippfehler des anderen dürfen korrigiert werden. Fährst du mit der Maus über
  ein Feld, steht dort, wer den Wert eingetragen hat.
- **„Speichern“** lädt die Einträge sofort hoch. Dabei landen nur die Rübenpreise auf dem
  Server; Sperre und Spielstand bleiben unberührt. Tragt ihr gleichzeitig etwas ein, werden
  beide Stände zusammengeführt – pro Feld zählt der neuere Eintrag.
- Ohne Internet bleiben die Einträge auf deinem PC und werden beim nächsten Mal (Rübenkurs
  öffnen oder „Status prüfen“) nachgeschickt.
- Mit **„<“** und **„>“** blätterst du zu früheren Wochen.

**Was das Fenster zeigt:**

- **Einschätzung:** wie wahrscheinlich jedes der vier Kursmuster ist – *Schwankend*,
  *Große Spitze* (bis zum Sechsfachen des Kaufpreises), *Fallend* und *Kleine Spitze*. Welches
  Muster kommt, hängt auch vom Muster der Vorwoche ab. Das Programm erkennt es aus den Preisen
  der Vorwoche; du kannst es aber auch von Hand wählen.
- **Spannen:** grau neben jedem leeren Feld, welche Preise dort noch möglich sind.
- **Empfehlung:** zum Beispiel „Jetzt verkaufen“, „Warten“ (mit der Wahrscheinlichkeit für
  einen höheren Preis und bis zu welchem Betrag) oder den Hinweis, wann eine große Spitze
  noch kommen kann.
- **Gewinn:** beim aktuellen Preis für jeden Spieler, der seine Rüben eingetragen hat, und
  zusammen.

Die laufende Woche erscheint außerdem in der **README des Repos** – so seht ihr den Kurs
auch auf GitHub.

> **Wie sicher ist das?** Die Regeln der vier Muster stammen aus dem ausgelesenen Code von
> *Animal Crossing: New Horizons*. Alles, was über *Let's Go to the City* bekannt ist, passt dazu
> (Kaufpreis 90–110, zwei Preise am Tag, vier Muster, höchstens 660 Sternis), und für *New Leaf*,
> das laut Community dieselbe Rübenlogik nutzt, passen aufgezeichnete Wochen. Offiziell
> bestätigt ist das für *Let's Go to the City* aber nicht. Passen eure Preise zu keinem Muster,
> sagt das Fenster das deutlich (meist ist es ein Tippfehler).

---

## Wo liegt die Konfiguration?

Deine Einstellungen werden in

```
%APPDATA%\AC-SaveSync\acsync-config.json
```

gespeichert – im (standardmäßig ausgeblendeten) Windows-Benutzerprofil, also **getrennt vom
Skript**. Neben der `.ps1` selbst liegt nichts. Öffnen kannst du den Ordner, indem du
`%APPDATA%\AC-SaveSync` in die Explorer-Adressleiste oder in „Ausführen" (Win+R) eingibst.

Die Konfig ist pro Benutzer/PC – du und dein Mitspieler habt also jeweils eure eigene lokale
Konfiguration, was auch so gewollt ist (unterschiedliche Namen, Pfade usw.).

---

## Fehlerbehebung

**„Die ausgewählte Datei … existiert nicht" beim Start**
Prüfe die Pfade in „Dolphin.exe" und „Spiel". Bei einer Mod-Verknüpfung gib die `.lnk` an –
das Skript löst sie selbst auf.

**Push schlägt fehl / hängt**
Meist fehlen die Git-Zugangsdaten. Klone das Repo einmal von Hand (dann speichert der Git
Credential Manager die Daten) oder richte einen SSH-Schlüssel ein. Das Skript fragt bewusst
nicht interaktiv nach Passwörtern, damit es nicht hängen bleibt.

**„GESPERRT" obwohl niemand spielt**
Wahrscheinlich ist eine Sitzung abgestürzt. Warte, bis die Sperre abläuft (siehe „Sperre gilt"),
oder nutze **„Sperre erzwingen freigeben"**.

**Spielstand wird nicht übernommen**
Prüfe, ob der „Save-Ordner" wirklich auf den Ordner **dieses** Spiels zeigt. Spiele einmal,
speichere im Spiel und schau, in welchem Ordner sich die Dateien geändert haben.

**Immer zuerst ins Protokoll schauen** – dort steht im Klartext, was passiert ist.

---

## Grenzen & Hinweise

- Das Tool ist für **abwechselndes** Spielen gedacht (einer nach dem anderen), nicht für
  gleichzeitiges Spielen im selben Stand.
- Der Herzschlag erzeugt regelmäßig kleine Git-Commits. Stört dich das, stelle „Herzschlag"
  höher (z. B. 120 Sek) und „Sperre gilt" auf mindestens das Dreifache (hier 6 Minuten).
  Das darf jeder für sich tun – die Sperrdauer steht in der Sperre, der andere richtet sich danach.
- Startet ihr Dolphin über einen Starter (`.bat`, Mod-Launcher, Verknüpfung darauf), der sich
  selbst gleich wieder beendet, beobachtet das Programm danach das laufende Dolphin. Die Sitzung
  endet erst, wenn einige Sekunden lang kein Dolphin mehr läuft. Nebenwirkung: Ist nebenher noch
  ein zweites Dolphin offen, bleibt die Sitzung offen, bis auch das geschlossen ist.
- Für Online-Besuche in Echtzeit (sich gegenseitig in der Stadt sehen) ist dieses Tool **nicht**
  gedacht – dafür bräuchtet ihr die Online-Funktion des Spiels (z. B. über Wiimmfi).

---

## Tests

Unter `tests/` liegen automatische Tests. Sie laufen bei jedem Push auf GitHub unter
**Windows PowerShell 5.1** (siehe *Actions* → *Tests*) und lassen sich auch selbst starten:

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Start-Lint.ps1         # Prüfung des Codes
powershell -ExecutionPolicy Bypass -File .\tests\Start-Tests.ps1        # Funktionen
powershell -ExecutionPolicy Bypass -File .\tests\Test-Oberflaeche.ps1   # echtes Programm
```

- **Start-Lint.ps1** prüft alle Skripte mit [PSScriptAnalyzer](https://github.com/PowerShell/PSScriptAnalyzer)
  auf typische Fehler. Die Regeln stehen in `PSScriptAnalyzerSettings.psd1`; fehlt das Modul,
  wird es für den aktuellen Benutzer installiert.
- **Start-Tests.ps1** prüft die Funktionen einzeln: Sperre, Spielstand, Ende-Erkennung, Pfade,
  Umlaute, Hintergrund-Aufrufe, Spielzeit-Statistik, Rübenkurs, Update-Installation, Fotos,
  Selbsttest und Bedienung (Meldungen, Schließen während eines Vorgangs, nur einmal starten). Für den Rübenkurs werden tausende Wochen nach den Regeln der vier Muster
  ausgewürfelt; die Einschätzung muss dabei immer das wahre Muster enthalten und die echten
  Preise immer in der angezeigten Spanne haben.
  Mit `-Filter Update` laufen nur die Tests aus `Update.Tests.ps1`.
- **Test-Oberflaeche.ps1** startet das echte Programm, klickt „Spielen starten", spielt eine
  Sitzung mit einem Ersatz-Dolphin durch, öffnet die Spielzeit und trägt im Rübenkurs Preise ein. Der Test-Server ist dabei
  absichtlich langsam, damit geprüft werden kann, dass das Fenster währenddessen reagiert. Von
  jedem Schritt entsteht ein Bildschirmfoto.

Alles läuft in einem eigenen Temp-Ordner mit einem lokalen Test-Server – euer Repo, eure
Einstellungen und euer Spielstand werden nicht angefasst. Gebraucht wird nur Git.

**Releases nur mit grünen Tests:** Wird ein Versions-Tag gepusht, laufen zuerst alle drei
Prüfungen unter Windows. Erst wenn sie grün sind, wird die `AC-SaveSync.cmd` gebaut und
veröffentlicht – schlägt etwas fehl, gibt es kein Release und damit auch kein kaputtes Update.

---

## Lizenz

[MIT](LICENSE) – benutzen, ändern und weitergeben ist erlaubt, solange der Copyright-Hinweis
erhalten bleibt. Ohne Gewähr und ohne Haftung.

Das Symbol (`icon.ico`) ist an *Animal Crossing* angelehnt. Die Marke und die Bildsprache
gehören Nintendo; die MIT-Lizenz gilt für den Code dieses Projekts, nicht dafür.
