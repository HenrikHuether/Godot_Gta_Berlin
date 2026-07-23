"""Export Blender edge-only map guides to a compact Godot-ready JSON file.

Run with Blender, not the system Python:
  blender --background Berlin_Segmentiert.blend \
    --python tools/export_berlin_network.py -- Assets/Maps/berlin_network.json

The Blender glTF exporter intentionally omits edge-only meshes.  This keeps the
Street, Kanal and Oberbahn source graphs alongside the GLB without baking their
rendered width into the source model.
"""

import json
import os
import pathlib
import sys

import bpy


GRAPH_OBJECTS = {
    "street": "Street",
    "kanal": "Kanal",
    "oberbahn": "Oberbahn",
}


def _script_arguments():
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1 :]


def _godot_relative_point(world_point, anchor):
    # Blender is Z-up; glTF/Godot is Y-up and flips Blender's Y axis into +Z.
    return [
        round(world_point.x - anchor.x, 6),
        round(world_point.z - anchor.z, 6),
        round(-(world_point.y - anchor.y), 6),
    ]


def _export_graph(obj, anchor):
    if obj.type != "MESH":
        raise TypeError("%s must be a mesh, got %s" % (obj.name, obj.type))
    mesh = obj.data
    return {
        "source_object": obj.name,
        "vertices": [
            _godot_relative_point(obj.matrix_world @ vertex.co, anchor)
            for vertex in mesh.vertices
        ],
        "edges": [[int(edge.vertices[0]), int(edge.vertices[1])] for edge in mesh.edges],
    }


def main():
    arguments = _script_arguments()
    if len(arguments) != 1:
        raise SystemExit("Expected one output path after --")

    street = bpy.data.objects.get(GRAPH_OBJECTS["street"])
    if street is None:
        raise KeyError("Street object is missing")
    anchor = street.matrix_world.translation

    payload = {
        "format_version": 1,
        "coordinate_system": "Godot Y-up, metres, relative to Street origin",
        "source_blend": pathlib.Path(bpy.data.filepath).name,
        "source_anchor_godot": [
            round(anchor.x, 6),
            round(anchor.z, 6),
            round(-anchor.y, 6),
        ],
        "graphs": {},
    }
    for key, object_name in GRAPH_OBJECTS.items():
        obj = bpy.data.objects.get(object_name)
        if obj is None:
            raise KeyError("%s object is missing" % object_name)
        payload["graphs"][key] = _export_graph(obj, anchor)

    output_path = pathlib.Path(arguments[0]).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(
        "Exported map graphs:",
        {
            key: (
                len(graph["vertices"]),
                len(graph["edges"]),
            )
            for key, graph in payload["graphs"].items()
        },
    )
    # Blender can wait indefinitely for an unavailable PulseAudio main loop in
    # headless CI. The file is fully flushed by write_text before this point.
    sys.stdout.flush()
    if bpy.app.background:
        os._exit(0)


if __name__ == "__main__":
    main()
