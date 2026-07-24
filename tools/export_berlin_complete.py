"""Export complete Berlin map (GLB geometry + network graphs) from Blender.

Run with Blender:
  blender --background Berlin_Segmentiert_EinzelneHaeuser.blend \
    --python tools/export_berlin_complete.py -- \
    Assets/Maps/Berlin_Segmentiert_EinzelneHaeuser.glb \
    Assets/Maps/berlin_network.json
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
    """Convert Blender Z-up coordinates to Godot Y-up relative coordinates."""
    return [
        round(world_point.x - anchor.x, 6),
        round(world_point.z - anchor.z, 6),
        round(-(world_point.y - anchor.y), 6),
    ]


def _export_graph(obj, anchor):
    """Export a single graph object (Street, Kanal, Oberbahn)."""
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


def _export_glb(output_path):
    """Export scene to GLB format."""
    bpy.ops.export_scene.gltf(
        filepath=str(output_path),
        export_format='GLB',
        export_image_format='AUTO',
        export_materials=True,
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_quantize_modules=False,
    )
    print("Exported GLB: %s" % output_path)


def _export_networks(output_path):
    """Export network graphs (Street, Kanal, Oberbahn) to JSON."""
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

    output_path = pathlib.Path(output_path).resolve()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(payload, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(
        "Exported networks: %s (graphs: %s)"
        % (
            output_path,
            {
                key: (len(graph["vertices"]), len(graph["edges"]))
                for key, graph in payload["graphs"].items()
            },
        )
    )


def main():
    arguments = _script_arguments()
    if len(arguments) != 2:
        raise SystemExit("Expected two output paths: GLB and JSON")

    glb_path = pathlib.Path(arguments[0]).resolve()
    json_path = pathlib.Path(arguments[1]).resolve()

    # Create output directories
    glb_path.parent.mkdir(parents=True, exist_ok=True)
    json_path.parent.mkdir(parents=True, exist_ok=True)

    print("=" * 60)
    print("Berlin Map Export")
    print("=" * 60)
    print("Source: %s" % bpy.data.filepath)
    print("GLB output: %s" % glb_path)
    print("JSON output: %s" % json_path)
    print("=" * 60)

    try:
        _export_glb(glb_path)
        _export_networks(json_path)
        print("=" * 60)
        print("Export completed successfully!")
        print("=" * 60)
    except Exception as e:
        print("ERROR: %s" % str(e))
        raise

    # Blender can wait indefinitely for PulseAudio in headless CI
    os.execl("true")


if __name__ == "__main__":
    main()
