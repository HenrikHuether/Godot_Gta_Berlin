# GTA Berlin – Minimum Prototype

Ein kleiner, vollständig aus primitiven 3D-Formen erzeugter Godot-Prototyp gemäß `Concept.md`.
Das Auto besitzt eine prozedurale Lacktextur und eine mehrteilige Karosserie; NPCs haben eine
menschliche Silhouette, und beim Ausrüsten erscheint ein First-Person-Pistolenmodell.
Die rund 220 × 220 Meter große Stadt liegt auf prozeduralem Hügelland. Straßen folgen dem
Höhenprofil, die Fahrphysik berücksichtigt Beschleunigung, Reibung, Steigung und Bodenneigung.
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
- **Linksklick** – schießen (NPCs brauchen zwei Treffer)
- **Esc** – Maus freigeben

Installiert wurde **Godot 3.6.2** systemweit aus den offiziellen Ubuntu-Paketquellen. Eine lokale
Kopie unter `.tools/godot/` dient als projektspezifischer Fallback; ihre Binärdateien und
Bibliotheken sind über `.gitignore` vom Repository ausgeschlossen.
