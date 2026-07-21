# GTA Berlin – Minimum Prototype

Ein Godot-Prototyp gemäß `Concept.md`. Die editierbare Karte `scenes/BerlinMap.tscn`
bildet Berliner Stadtblöcke mit texturierten Gründerzeitfassaden, Straßen, Innenhöfen,
Stadtmobiliar und Landmarken ab. Die NPCs verwenden das riggte Modell `Assets/HumanV2.glb`.
Das Auto besitzt eine prozedurale Lacktextur und eine mehrteilige Karosserie; beim Ausrüsten
erscheint ein First-Person-Pistolenmodell. Die Fahrphysik berücksichtigt Beschleunigung,
Reibung, Steigung und Bodenneigung.
Schüsse zeigen kurz Mündungsfeuer, Leuchtspur und Einschlag.

Mission 1 ist als vollständiger Vertical Slice spielbar: Mit einem Aktenkoffer fährt der
Spieler ins Regierungsviertel, verschafft sich Zugang zum Bundestag und übergibt die
Sendung am Empfang. Das dafür erzeugte Bundestag-Areal besitzt ein begehbares Inneres,
einen bewachten Haupteingang und einen versteckten Servicegang.

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
- **2** – Bazooka aus-/einrüsten
- **Linksklick** – schießen (NPCs brauchen zwei Treffer)
- **Enter** – freie Eingabe im Wachmann-Dialog absenden
- **R** – Mission nach Abschluss oder Fahrzeugausfall neu starten
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
```

Der erste Test prüft mehrere friedliche Überzeugungswege, Drohungen, Verneinungen und
erneute Versuche. Der zweite prüft beide Missionsrouten, die Übergabe sowie Benzin,
Fahrzeugschaden und Fahndungsanstieg.

## Fahrzeug und Fahndung

- Das Missionsauto verbraucht beim Fahren Benzin.
- Harte seitliche Kollisionen beschädigen das Fahrzeug; bei 0 % bleibt es liegen.
- Bei einem Fahrzeugausfall kann die Mission mit **R** neu begonnen werden.
- Straftaten erhöhen die sichtbare Fahndungsstufe. Gebäudeschäden lösen neben dem
  Feuerwehreinsatz auch einen Polizeieinsatz aus.

## Einsatzsysteme

- Treffer auf Zivilisten alarmieren zwei Polizeiwagen. Beamte steigen aus, verfolgen den
  Spieler und eröffnen das Feuer.
- Bazooka-Treffer zerstören Gebäude. Das Gebäude wird durch ein kollidierendes Trümmerfeld
  mit Brandstellen ersetzt und ein Feuerwehrfahrzeug rückt über die nächste Straße an.
- Die Feuerwehr steigt am Einsatzort aus und löscht den Brand nach kurzer Zeit.

Benötigt wird **Godot 3.6.x**. `run.sh` verwendet zuerst die optionale lokale Kopie unter
`.tools/godot/` und fällt anschließend auf ein systemweit installiertes `godot3` zurück.
Nicht direkt benötigte `.blend`-Quelldateien liegen im von Godot ignorierten Ordner
`SourceAssets/`. Die verwendeten Szenen und Texturen werden direkt vom Spiel geladen.
# Godot_Gta_Berlin
