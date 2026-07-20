# GTA Berlin – Minimum Prototype

Ein Godot-Prototyp gemäß `Concept.md`. Die editierbare Karte `scenes/BerlinMap.tscn`
bildet Berliner Stadtblöcke mit texturierten Gründerzeitfassaden, Straßen, Innenhöfen,
Stadtmobiliar und Landmarken ab. Die NPCs verwenden das riggte Modell `Assets/HumanV2.glb`.
Das Auto besitzt eine prozedurale Lacktextur und eine mehrteilige Karosserie; beim Ausrüsten
erscheint ein First-Person-Pistolenmodell. Die Fahrphysik berücksichtigt Beschleunigung,
Reibung, Steigung und Bodenneigung.
Schüsse zeigen kurz Mündungsfeuer, Leuchtspur und Einschlag.

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
- **Esc** – Maus freigeben

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
