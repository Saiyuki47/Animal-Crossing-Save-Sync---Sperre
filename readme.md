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
- [Wo liegt die Konfiguration?](#wo-liegt-die-konfiguration)
- [Fehlerbehebung](#fehlerbehebung)
- [Grenzen & Hinweise](#grenzen--hinweise)

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
  höchstens die Zeit seit dem letzten Herzschlag verloren.

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
ohnehin. Das Motiv ist selbst gezeichnet (`tools/New-Icon.ps1`), es steckt kein
Material aus dem Spiel darin.

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
   Spielstand hoch. Danach **„Adresse kopieren"** und dem Mitspieler schicken.

**„Mein Mitspieler hat ihn schon – ich hole ihn mir"** (der andere):

1. Die Adresse einfügen, die ihr bekommen habt.
2. Einen leeren oder neuen Ordner auf eurem PC wählen.
3. **„Jetzt holen"** – fertig.

> Achtung für die zweite Person: Es wird der Spielstand des Ersten geholt. Ein eigener
> Spielstand auf diesem PC wird dabei **nicht** hochgeladen.

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
| **Bilder-Ordner**     | Screenshots/Fotos, die nach dem Spielen ins Repo verschoben werden. Leer = aus.                |
| **Branch**            | Git-Branch, meist `main`.                                                                      |
| **Sperre gilt (Min)** | Nach so vielen Minuten ohne Herzschlag gilt eine Sperre als abgelaufen (Standard 5).           |
| **Herzschlag (Sek)**  | Abstand, in dem während des Spielens gesichert und die Sperre aufgefrischt wird (Standard 60). |

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
angeben – sonst würden auch die Spielstände anderer Spiele mitsynchronisiert.

### Knöpfe

| Knopf                          | Funktion                                                                                         |
| ------------------------------ | ------------------------------------------------------------------------------------------------ |
| **Spielen starten**            | Holt den Stand, setzt die Sperre, schreibt den Save in den Dolphin-Ordner und startet das Spiel. |
| **Spielen beenden**            | Beendet Dolphin aus dem Programm heraus und schließt die Sitzung ab: sichern, hochladen, Sperre freigeben. **Vorher im Spiel speichern!** Nur während einer laufenden Sitzung anklickbar. |
| **Status prüfen**              | Aktualisiert die Anzeige: frei, du spielst, jemand anderes spielt, oder abgelaufene Sperre. Läuft beim Programmstart automatisch einmal. |
| **Selbsttest**                 | Prüft alles Nötige der Reihe nach (Git, deine Angaben, Dolphin, Save-Ordner, gemeinsamer Ordner, Verbindung zum Server) und sagt zu jedem Problem, was zu tun ist. Erster Anlaufpunkt, wenn etwas nicht klappt. |
| **Sperre erzwingen freigeben** | Notausgang: entfernt eine hängende Sperre (nur benutzen, wenn sicher niemand spielt).            |
| **Erweitert…**                 | Selten gebrauchte Einstellungen: Bilder-Ordner, Branch, Sperre, Herzschlag. Dort liegt auch **„Verknüpfung auf dem Desktop anlegen"**. |
| **Repo einrichten…**           | Öffnet den Einrichtungs-Dialog (anlegen / verbinden / klonen).                                   |

„Spielen starten" ist gesperrt, solange etwas Wichtiges fehlt. Fahre mit der Maus über den
Knopf, dann steht dort, **was** fehlt.

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
deinem Namen und einem Zeitstempel.

**Ein dauerhaftes Aussperren ist ausgeschlossen**, gleich dreifach abgesichert:

- **Automatischer Ablauf:** Der Zeitstempel wird während des Spielens per Herzschlag
  aufgefrischt. Stürzt der PC ab, stoppt der Herzschlag – und nach „Sperre gilt (Min)" gilt die
  Sperre als tot und wird beim nächsten Start automatisch übernommen.
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

> Diese README (die du gerade liest) ist die Anleitung für das Tool. Die **README im Repo** ist
> etwas anderes: Sie wird vom Skript automatisch mit der Spielzeit-Tabelle erzeugt.

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
  höher (z. B. 120 Sek) und „Sperre gilt" entsprechend auf 5–6 Minuten.
- Manche Dolphin-Installer starten die App über einen Zwischenstarter; in seltenen Fällen wird
  das Beenden dann nicht sofort erkannt. Als Sicherheitsnetz greift die automatisch ablaufende
  Sperre.
- Für Online-Besuche in Echtzeit (sich gegenseitig in der Stadt sehen) ist dieses Tool **nicht**
  gedacht – dafür bräuchtet ihr die Online-Funktion des Spiels (z. B. über Wiimmfi).