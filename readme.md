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

Rechtsklick auf `AC-SaveSync.ps1` → **„Mit PowerShell ausführen"**.
Alternativ in PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\AC-SaveSync.ps1
```

### Erste Person (bringt den Spielstand mit)

1. Auf **github.com** ein neues, **leeres, privates** Repo anlegen und dessen URL kopieren
   (z. B. `https://github.com/deinname/ac-save.git`).
2. Im Hauptfenster oben eintragen: **Repo-Ordner** (ein neuer, leerer Ordner auf der Platte),
   **Dein Name**, **Branch** (meist `main`), sowie **Save-Ordner** (siehe unten).
3. **„Repo einrichten…"** öffnen.
4. Knopf **1) Lokales Repo in diesem Ordner anlegen** – macht aus dem Ordner ein Git-Repo.
5. Die kopierte URL oben ins Feld **Remote-URL** einfügen.
6. Knopf **2) Mit Remote-URL verbinden und hochladen** – lädt alles hoch.

> Wenn du die **GitHub CLI** (`gh`) installiert und angemeldet hast, kannst du dir Schritt 1
> sparen: unten im Setup-Fenster einen Namen eintragen und
> **„GitHub-Repo per gh erstellen und pushen"** klicken. Das legt das Remote automatisch an.

### Zweite Person (klont nur)

1. Dieselbe **Remote-URL** ins Setup-Fenster eintragen.
2. Als **Repo-Ordner** einen leeren/neuen Ordner wählen.
3. Knopf **3) Vorhandenes Repo von URL klonen**.

Danach eigenen **Namen**, **Save-Ordner** und ggf. **Spiel** eintragen, **„Speichern"** klicken –
fertig.

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
| **Branch**            | Git-Branch, meist `main`.                                                                                                             |
| **Sperre gilt (Min)** | Nach so vielen Minuten ohne Herzschlag gilt eine Sperre als abgelaufen (Standard 5).                                                  |
| **Herzschlag (Sek)**  | Abstand, in dem während des Spielens gesichert und die Sperre aufgefrischt wird (Standard 60).                                        |

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
| **Status prüfen**              | Aktualisiert die Anzeige: frei, du spielst, jemand anderes spielt, oder abgelaufene Sperre.      |
| **Sperre erzwingen freigeben** | Notausgang: entfernt eine hängende Sperre (nur benutzen, wenn sicher niemand spielt).            |
| **Speichern**                  | Speichert die Einstellungen.                                                                     |
| **Repo einrichten…**           | Öffnet den Einrichtungs-Dialog (anlegen / verbinden / klonen).                                   |

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

1. Skript starten.
2. Optional **„Status prüfen"**, um zu sehen, ob gerade jemand spielt.
3. **„Spielen starten"** – Dolphin öffnet sich mit dem aktuellen gemeinsamen Stand.
4. Ganz normal spielen und im Spiel speichern.
5. Dolphin schließen. Das Skript sichert automatisch, lädt hoch und gibt die Sperre frei.

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