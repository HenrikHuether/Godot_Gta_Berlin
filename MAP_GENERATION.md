# Berlin Map Generation Guide

## Übersicht des Prozesses

Der Map-Generation-Prozess in GTA Berlin besteht aus 4 Hauptschritten:

```
1. Blender-Datei (.blend)
   ↓
2. GLB-Export + Netzwerk-Graph-Export
   ↓
3. Godot Import (BerlinSegmentedMap.tscn)
   ↓
4. Runtime-Generierung (Straßen, Gehwege, Markierungen)
```

---

## 1. Blender-Phase (.blend)

Die Quelldata ist: `Berlin_Segmentiert_EinzelneHaeuser.blend`

### Wichtige Objekte in Blender:

| Objekt | Typ | Zweck |
|--------|-----|-------|
| **Building_* / Haus-Meshes** | Mesh | Renderbare Gebäude (5.340 Unique) |
| **Street** | Edge-Only Mesh | Straßenverlauf (wird exportiert zu JSON) |
| **Kanal** | Edge-Only Mesh | Kanäle/Wasserwege (wird exportiert zu JSON) |
| **Oberbahn** | Edge-Only Mesh | U-Bahn-Trassen (optional, derzeit nicht genutzt) |

### Wichtig beim Bearbeiten in Blender:

- **Street/Kanal/Oberbahn** sind **Edge-Only Meshes** (nur Kanten, keine Flächen)
  - Sie definieren die Graphen für Straßen und Wasserwege
  - Sie sollten **nicht** als Geometrie exportiert werden (GLB-Exporter ignoriert sie automatisch)
  - Sie müssen editierbar bleiben als Netzwerk-Definition
  
- **Koordinaten-System**: Blender verwendet Z-up, aber werden zu Y-up konvertiert
  
- **Street-Origin**: Der `Street`-Objekt-Ursprung ist der **World Anchor** für alle Godot-Koordinaten

---

## 2. Export-Phase (.blend → GLB + JSON)

### Schritt A: GLB-Export (Gebäude-Geometrie)

```bash
# Beispiel (in Blender oder Befehlszeile)
blender --background Berlin_Segmentiert_EinzelneHaeuser.blend \
  --python-expr "import bpy; bpy.ops.export_scene.gltf(filepath=r'/home/hhuether/Godot_Gta_Berlin/Assets/Maps/Berlin_Segmentiert_EinzelneHaeuser.glb', export_format='GLB')"
```

**Was wird exportiert:**
- ✅ Alle Building-Meshes (segmentiert in 256 Kacheln)
- ✅ Texturen und Materialien
- ❌ Street/Kanal/Oberbahn (Edge-Only → nicht exportiert)

**GLB-Import-Einstellungen in Godot:**
- Location: `Assets/Maps/Berlin_Segmentiert_EinzelneHaeuser.glb`
- Reimporter: `.glb.import` Datei anpassen bei Bedarf
- Ensure `reimport` wenn GLB geändert wird

### Schritt B: Netzwerk-Graph-Export (JSON)

```bash
cd ~/Godot_Gta_Berlin
blender --background ~/Godot_Gta_Berlin/Assets/Maps/Berlin_Segmentiert_EinzelneHaeuser.blend \
  --python tools/export_berlin_network.py -- \
  Assets/Maps/berlin_network.json
```

**Was wird generiert:**
```json
{
  "format_version": 1,
  "coordinate_system": "Godot Y-up, metres, relative to Street origin",
  "source_blend": "Berlin_Segmentiert_EinzelneHaeuser.blend",
  "source_anchor_godot": [x, y, z],
  "graphs": {
    "street": {
      "source_object": "Street",
      "vertices": [[x, y, z], ...],
      "edges": [[vertex_a, vertex_b], ...]
    },
    "kanal": {...},
    "oberbahn": {...}
  }
}
```

**Wichtig:**
- Script liegt unter: `tools/export_berlin_network.py`
- Koordinaten werden automatisch von Blender Z-up zu Godot Y-up konvertiert
- Alle Koordinaten sind **relativ zum Street-Ursprung** (Präzisions-Anchor)
- Edges definieren Straßenverbindungen (können z.B. in A*-Pathfinding genutzt werden)

---

## 3. Godot Import-Phase

### Szene: `scenes/BerlinSegmentedMap.tscn`

```
BerlinMap (Spatial)
├── Source (GLB-Import)
│   ├── Building_chunks_0_0, 0_1, ... (256 Kacheln)
│   └── (Haus-Meshes als MeshInstance)
├── Generator (BerlinSurfaceGenerator)
│   ├── RoadChunks
│   │   ├── RoadChunk_X_Z (gekachelt)
│   │   └── CollisionShape (Trimesh aus Mesh)
│   └── CanalChunks
│       └── WaterAreas + Meshes
└── GroundSurface (StaticBody)
    └── CollisionShape (kontinuierliche Ground-Box)
```

### Script: `scripts/berlin_segmented_map.gd`

Dieser Script lädt die GLB und konfiguriert sie:

1. **Aggregate-Gebäude splitten** → 76 verknüpfte Häuser in einzelne Meshes
2. **Gebäude deduplicieren** → 154 doppelte Exportvarianten entfernen
3. **Facade-Shader anwenden** → 4 Berliner Fassaden-Texturen per Welt-Projektion
4. **Ground-Surface konfigurieren** → Eine große kollidierende Box als Bodenfläche
5. **Generator aufrufen** → Surface Generator für Straßen/Wasser starten

### Wichtige Konstanten in `berlin_segmented_map.gd`:

```gdscript
const SOURCE_ANCHOR := Vector3(5809.403809, 0.0, 4220.549805)
const NETWORK_FILE := "res://Assets/Maps/berlin_network.json"
const WALK_SURFACE_ELEVATION := 0.0
const GROUND_COLLISION_DEPTH := 4.0
const LOCAL_MAP_BOUNDS := AABB(...)
```

---

## 4. Runtime Generation-Phase

### Script: `scripts/berlin_surface_generator.gd`

Generiert beim Start folgende Elemente aus der JSON-Graph:

#### Straßen-Generation:

```gdscript
const ROAD_WIDTH := 14.0
const ROAD_ELEVATION := 0.12          ← Höhe der Straße (überlappt nicht Ground)
const ROAD_UV_SCALE := 0.08           ← Textur-Wiederholung
const MAX_SEGMENT_LENGTH := 96.0      ← Max Längensegmente
const CHUNK_SIZE := 512.0             ← Szenen-Kachel-Größe
```

**Was wird generiert:**
- ✅ Asphalt-Meshes aus Street-Kanten (mit Textur)
- ✅ Gehwege auf beiden Seiten
- ✅ Granitbordsteine
- ✅ Fahrbahnmarkierungen (Mittellinien, Zebrastreifen)
- ✅ Trimesh-Kollisionen pro Straßen-Chunk
- ✅ AStar-Graph für NPC-Pathfinding

#### Wasser-Generation:

```gdscript
const CANAL_WIDTH := 48.0
const CANAL_ELEVATION := 0.035
const WATER_COLLISION_LAYER := 16
```

**Was wird generiert:**
- ✅ Wasser-Meshes aus Kanal-Kanten
- ✅ Area-Trigger für Wasser-Erkennung (z.B. Fahrzeug-Unfall)
- ✅ Tiefenboxen als Wasser-Trigger-Shapes

#### Elevation Heights:

```
y = 0.0   ← Ground-Surface Ebene (kontinuierliche Box)
y = 0.12  ← Straße-Oberfläche
y = 0.125 ← Fahrbahnmarkierungen
y > 0.2   ← Gebäude, Objekte, NPC
```

**Wichtig: Keine Überlappung!**
- Ground ist eine kontinuierliche Box unter allem
- Straße liegt 0.12 Einheiten höher
- Verhindert Z-Fighting und Collision Bugs

---

## Workflow: Map neu generieren

### Szenario: Du hast Straßen in Blender verändert

#### Option 1: Nur Straßen regenerieren (schneller)

1. Öffne `Berlin_Segmentiert_EinzelneHaeuser.blend` in Blender
2. Bearbeite `Street` und `Kanal` Edge-Meshes
3. Exportiere nur die JSON:
   ```bash
   blender --background Berlin_Segmentiert_EinzelneHaeuser.blend \
     --python tools/export_berlin_network.py -- \
     Assets/Maps/berlin_network.json
   ```
4. In Godot: Starte die Szene neu oder drücke F5
   - `BerlinSurfaceGenerator.build_from_file()` wird aufgerufen und nutzt neue JSON
   - Alte RoadChunks werden gelöscht, neue werden generiert

#### Option 2: Gebäude + Straßen regenerieren (vollständig)

1. Bearbeite in Blender sowohl Building-Meshes als auch Street/Kanal
2. Exportiere beide:
   ```bash
   # GLB für Gebäude
   blender --background ~/GTA_Berlin_Maps/Berlin/Berlin_Segmentiert_GebäudeEinzeln.blend \
     --python-expr "import bpy; bpy.ops.export_scene.gltf(filepath=r'/home/hhuether/Godot_Gta_Berlin/Assets/Maps/Berlin_Segmentiert_EinzelneHaeuser.glb', export_format='GLB')"
   
   # JSON für Straßen/Kanäle
   blender --background ~/GTA_Berlin_Maps/Berlin/Berlin_Segmentiert_GebäudeEinzeln.blend \
     --python tools/export_berlin_network.py -- \
     /home/hhuether/Godot_Gta_Berlin/Assets/Maps/berlin_network.json
   ```

3. In Godot:
   - Gehe zu `Assets/Maps/Berlin_Segmentiert_EinzelneHaeuser.glb.import`
   - Klicke "Reimport" (oben im Inspector)
   - Starte die Szene neu

---

## Debugging & Tipps

### Problem: Z-Fighting / Flackern auf der Straße

**Ursache:** Straße und Ground überlappen (falsche Elevation)

**Fix:** Höhe anpassen in `berlin_surface_generator.gd`:
```gdscript
const ROAD_ELEVATION := 0.12   # Anpassen bei Bedarf
const MARKING_ELEVATION := 0.125
```

Dann Szene neustarten.

### Problem: Straße ist unsichtbar

**Ursache:** 
- Material-Fehler
- Verkehrte Vertex-Reihenfolge (Back-face Culling)

**Debug:**
```gdscript
# In Godot Console / Play Mode
var gen = get_node("BerlinMap/Generator")
print(gen._diagnostics)
# Suche nach "road_triangle_count": 0
```

### Problem: Pathfinding funktioniert nicht

**Ursache:** AStar-Graph wird nicht gebaut

**Debug:**
```gdscript
var gen = get_node("BerlinMap/Generator")
print("AStar nodes: %d" % gen._road_astar.get_point_count())
```

### Problem: NPCs fahren falsch

**Ursache:** Street-Graph hat isolierte Komponenten oder Schleifen

**Fix in Blender:**
- Überprüfe, dass `Street` vollständig verbunden ist (ein zusammenhängendes Netzwerk)
- Keine doppelten Kanten
- Kein T-Kreuzungen ohne Vertex in der Mitte

---

## Performance-Optimierungen

### Gebäude-Level:
- Godot dedupliziert bei Import (154 Duplikate werden entfernt)
- 256 Kacheln mit LOD-Gruppen (wenn verfügbar)
- Shader-Varianten pro Fassade (4 Texturen) → reduziert Draw Calls

### Straßen-Level:
- Gekachelt in 512x512-Chunks
- Trimesh-Kollisionen werden nur beim Start gebaut (nicht per Frame)
- Roads sind auf Layer 2 (kann ignoriert werden für Spieler mit Layer-Masking)

### Optimierungs-Tipps:
- Reduziere `MAX_SEGMENT_LENGTH` (unter 96.0) wenn Speicher-kritisch
- Erhöhe `CHUNK_SIZE` wenn viele Draw Calls problematisch
- Nutze Occlusion Culling für Gebäude

---

## Koordinaten-System

```
Blender (Z-up):          Godot (Y-up):
      Z                        Y
      ↑                        ↑
      |                        |
  Y ← | → -X              X ← | → Z
      |
      v
```

**Konversion (in `export_berlin_network.py`):**
```python
def _godot_relative_point(world_point, anchor):
    return [
        round(world_point.x - anchor.x, 6),  # X bleibt X
        round(world_point.z - anchor.z, 6),  # Blender Z → Godot X
        round(-(world_point.y - anchor.y), 6)  # Blender Y (negiert) → Godot Z
    ]
```

**Result:** Alle Godot-Koordinaten sind **relativ zum Street-Objekt-Ursprung in Blender**

---

## Weitere Ressourcen

- **Main Script:** `scripts/main.gd` - Szenen-Verwaltung
- **Vehicle Physics:** `scripts/vehicle_controller.gd` - Fahrphysik
- **Helicopter Physics:** `scripts/helicopter_controller.gd` - Heliflug
- **Mission-System:** `scripts/mission_one.gd` - Mission-Logik
- **Shader:** `shaders/berlin_building_facade.shader` - Facade-Texturierung

---

**Zuletzt aktualisiert:** 24.07.2026
