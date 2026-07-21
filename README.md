# GTA Berlin – Minimum Prototype

Ein Godot-Prototyp gemäß `Concept.md`. Die editierbare Karte `scenes/BerlinMap.tscn`
bildet Berliner Stadtblöcke mit texturierten Gründerzeitfassaden, Straßen, Innenhöfen,
Stadtmobiliar und Landmarken ab. Die NPCs verwenden das riggte Modell `Assets/HumanV2.glb`.
Eine prozedurale Außenzone erweitert die befahrbare Karte auf 1,4 × 1,4 Kilometer – mit
Ringstraße, Ausfallstraßen, Gehwegen, Außenbezirken, Beleuchtung und Randbarrieren.
Das Auto besitzt eine prozedurale Lacktextur und eine mehrteilige Karosserie. Pistole,
Sturmgewehr und Raketenwerfer besitzen eigene First-Person-Modelle. Die Fahrphysik
berücksichtigt Beschleunigung, Reibung, Steigung und Bodenneigung. Schüsse verwenden
Magazine, Reservemunition, Nachladezeiten, waffenspezifische Streuung, Rückstoß,
Feuerraten, Distanzabfall und Kopftreffer; Mündungsfeuer, Hülsen, Leuchtspur und Einschlag
machen die Treffer nachvollziehbar. Prozedurale 3D-Sounds begleiten Schüsse,
Raketenstarts, Explosionen und brennende Fahrzeuge.

Mission 1 ist als vollständiger Vertical Slice spielbar: Mit einem Aktenkoffer fährt der
Spieler ins Regierungsviertel, verschafft sich Zugang zum Bundestag und übergibt die
Sendung am Empfang. Das dafür erzeugte Bundestag-Areal besitzt den realen
Reichstags-Grundriss von 138 × 98 Metern, eine maßstäbliche Glaskuppel, ein begehbares
Inneres, einen bewachten Haupteingang und einen versteckten Servicegang.

## Start

```bash
./run.sh
```

Alternativ `project.godot` im Godot-Editor öffnen und **F6/F5** drücken.

## Steuerung

- **WASD** – laufen bzw. fahren
- **Maus** – umsehen
- **Leertaste** – springen
- **E** – nahe am roten Auto ein-/aussteigen
- **1** – Pistole aus-/einrüsten
- **2** – Raketenwerfer aus-/einrüsten
- **3** – Sturmgewehr aus-/einrüsten
- **Linksklick** – schießen; das Sturmgewehr feuert im Automatikmodus bei gehaltenem Klick
- **R** – aktuelle Waffe nachladen
- **B** – Sturmgewehr zwischen Automatik und Einzelfeuer umschalten
- **Enter** – freie Eingabe im Wachmann-Dialog absenden
- **R** – nach Missionsabschluss oder Fahrzeugausfall die Mission neu starten
- **Esc** – Maus freigeben

## Mission 1: Sonderzustellung

1. Mit dem Aktenkoffer in das rote Auto steigen.
2. Dem gelben Wegpunkt bis zum Bundestag im Regierungsviertel folgen.
3. Einen von zwei Zugängen wählen:
   - Den Wachmann über eine freie Texteingabe überzeugen. Die lokale Dialogauswertung
     reagiert auf Auftrag, Nachweise, Kooperation, Dringlichkeit und den Gesprächston;
     es gibt keine vorgegebenen Antwortoptionen oder einzelne Pflichtformulierung.
   - Die markierte Kiste mit **WASD** aus ihren Schleifspuren schieben und dadurch den
     verborgenen Servicegang freilegen.
4. Im Inneren am Empfang mit **E** den Aktenkoffer übergeben.

Der Dialog funktioniert vollständig offline. Seine Auswertung ist in
`scripts/persuasion_evaluator.gd` gekapselt und kann später durch einen LLM-Dienst
ersetzt werden, ohne den Missionsablauf umzubauen.

## Tests

```bash
godot3 --no-window --audio-driver Dummy --path . --script tests/test_persuasion_evaluator.gd
godot3 --no-window --audio-driver Dummy --path . --script tests/test_mission_one.gd
godot3 --no-window --audio-driver Dummy --path . --script tests/test_combat_systems.gd
```

Der erste Test prüft mehrere friedliche Überzeugungswege, Drohungen, Verneinungen und
erneute Versuche. Der zweite prüft beide Missionsrouten, die Übergabe sowie Benzin,
Fahrzeugschaden und Fahndungsanstieg. Der dritte prüft Waffenmodelle, Gewehrtreffer,
Magazine, Nachladen, Spielerschaden, Torso-Zielpunkt, Sound und Fahrzeugzerstörung. Der
Missionstest kontrolliert zusätzlich Kartengröße und die freie Reichstag-Baufläche.

## Fahrzeug und Fahndung

- Das Missionsauto verbraucht beim Fahren Benzin.
- Harte Kollisionen und Waffentreffer beschädigen Fahrzeuge. Bei 0 % explodieren sie,
  werden zu einem verkohlten Wrack und brennen mit Licht-, Rauch- und Soundeffekt.
- Bei einem Fahrzeugausfall kann die Mission mit **R** neu begonnen werden.
- Straftaten erhöhen die sichtbare Fahndungsstufe. Gebäudeschäden lösen neben dem
  Feuerwehreinsatz auch einen Polizeieinsatz aus.

## Einsatzsysteme

- Treffer auf Zivilisten alarmieren zwei detaillierte, kollidierende Polizeiwagen. Beamte
  tragen Einsatzweste, Ausrüstungsgürtel, Funkgerät, Kappe und sichtbare Dienstpistole.
  Sie steigen aus, verfolgen den Spieler und treffen bei freier Schusslinie den Körper des
  Spielers beziehungsweise das besetzte Auto; der Zielpunkt liegt sichtbar am unteren
  Torso und Deckung unterbricht den Trefferstrahl.
- Spielerauto, Polizeiwagen und Feuerwehrfahrzeuge sind durch Kugeln, Raketen,
  Explosionsschaden und Kollisionen zerstörbar.
- Bei 0 HP kippt der Spieler rückwärts um. Eine vollständige Schwarzblende verdeckt den
  anschließenden Respawn und gibt die Steuerung erst nach dem Einblenden wieder frei.
- Bazooka-Treffer zerstören Gebäude. Das Gebäude wird durch ein kollidierendes Trümmerfeld
  mit Brandstellen ersetzt und ein Feuerwehrfahrzeug rückt über die nächste Straße an.
- Die Feuerwehr steigt am Einsatzort aus und löscht den Brand nach kurzer Zeit.

Benötigt wird **Godot 3.6.x**. `run.sh` verwendet zuerst die optionale lokale Kopie unter
`.tools/godot/` und fällt anschließend auf ein systemweit installiertes `godot3` zurück.
Nicht direkt benötigte `.blend`-Quelldateien liegen im von Godot ignorierten Ordner
`SourceAssets/`. Die verwendeten Szenen und Texturen werden direkt vom Spiel geladen.
# Godot_Gta_Berlin
