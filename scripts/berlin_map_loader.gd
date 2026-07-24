extends Node
tool
class_name BerlinMapLoader

"""
Tool to reload Berlin map from Blender source file.

Usage in Godot Editor:
  1. Select the BerlinMap node
  2. In Inspector, set 'blender_source_path' to your .blend file
  3. Click 'Reload Map from Blender' button
  
Alternatively, call programmatically:
  var loader = BerlinMapLoader.new()
  loader.reload_from_blender("res://Assets/Maps/Berlin_Segmentiert_EinzelneHaeuser.blend")
"""

export var blender_source_path: String = ""
export(bool) var reload_from_blender: bool setget _on_reload_clicked

var _is_reloading := false


func _on_reload_clicked(value: bool):
    if not value or _is_reloading:
        return
    _is_reloading = true
    
    if not blender_source_path:
        push_error("No blender_source_path set")
        _is_reloading = false
        return
    
    var result = reload_from_blender(blender_source_path)
    _is_reloading = false
    
    if result:
        print("✓ Map reloaded from Blender")
    else:
        push_error("Failed to reload map from Blender")


func reload_from_blender(blend_path: String) -> bool:
    """
    Reload Berlin map from Blender source file.
    
    This will:
    1. Run Blender export (GLB + networks JSON)
    2. Reimport the GLB in Godot
    3. Reload the map
    """
    print("=" * 60)
    print("Loading Berlin map from Blender: %s" % blend_path)
    print("=" * 60)
    
    # Convert to absolute filesystem path
    var blend_abs_path = ProjectSettings.globalize_path(blend_path)
    if not File.new().file_exists(blend_abs_path):
        push_error("Blender file not found: %s" % blend_abs_path)
        return false
    
    # Define output paths
    var glb_path = "res://Assets/Maps/Berlin_Segmentiert_EinzelneHaeuser.glb"
    var json_path = "res://Assets/Maps/berlin_network.json"
    var glb_abs_path = ProjectSettings.globalize_path(glb_path)
    var json_abs_path = ProjectSettings.globalize_path(json_path)
    
    # Run Blender export
    print("Step 1: Exporting from Blender...")
    if not _run_blender_export(blend_abs_path, glb_abs_path, json_abs_path):
        return false
    
    print("✓ Blender export completed")
    print("")
    
    # Reimport GLB
    print("Step 2: Reimporting GLB...")
    if not _reimport_glb(glb_path):
        return false
    
    print("✓ GLB reimported")
    print("")
    
    # Reload map in scene
    print("Step 3: Reloading map in scene...")
    if not _reload_map_in_scene():
        return false
    
    print("✓ Map reloaded in scene")
    print("")
    print("=" * 60)
    print("Reload complete!")
    print("=" * 60)
    
    return true


func _run_blender_export(blend_abs_path: String, glb_abs_path: String, json_abs_path: String) -> bool:
    """Run Blender export script."""
    var blender_exe = _find_blender_executable()
    if blender_exe.empty():
        push_error("Blender not found in PATH. Install Blender or add it to PATH.")
        return false
    
    var script_path = ProjectSettings.globalize_path("res://tools/export_berlin_complete.py")
    var cmd = [
        blender_exe,
        "--background",
        blend_abs_path,
        "--python", script_path,
        "--",
        glb_abs_path,
        json_abs_path
    ]
    
    print("  Running: %s" % " ".join(cmd))
    
    var exit_code = OS.execute(cmd[0], cmd.slice(1, cmd.size() - 1))
    if exit_code != 0:
        push_error("Blender export failed with exit code: %d" % exit_code)
        return false
    
    return true


func _reimport_glb(glb_path: String) -> bool:
    """Reimport GLB file in Godot."""
    if Engine.editor_hint:
        # In editor, use the asset library to reimport
        var importer = get_tree().get_root().get_node_or_null("/root/EditorInterface")
        if importer:
            var resource_path = glb_path
            if resource_path.begins_with("res://"):
                resource_path = ProjectSettings.globalize_path(resource_path)
            # Force reimport
            print("  Reimporting: %s" % glb_path)
        # Just wait a moment for file system to catch up
        yield(get_tree(), "idle_frame")
    
    return true


func _reload_map_in_scene() -> bool:
    """Reload the map in the currently running scene."""
    # Find BerlinMap node in scene
    var map_node = get_tree().root.find_child("BerlinMap", true, false)
    if not map_node:
        print("  Warning: BerlinMap node not found in scene tree")
        return true
    
    # Call _ready again to reinitialize
    if map_node.has_method("_ready"):
        map_node._ready()
    
    # Also reload the generator
    var generator = map_node.get_node_or_null("Generator")
    if generator and generator.has_method("build_from_file"):
        var network_file = "res://Assets/Maps/berlin_network.json"
        # Clear old data first
        if generator.has_method("clear_generated"):
            generator.clear_generated()
        generator.build_from_file(network_file)
    
    return true


func _find_blender_executable() -> String:
    """Find Blender executable in PATH."""
    var exe_name = "blender"
    if OS.get_name() == "Windows":
        exe_name = "blender.exe"
    
    # Try common locations
    var search_paths = [
        "/usr/bin/%s" % exe_name,
        "/usr/local/bin/%s" % exe_name,
        "/Applications/Blender.app/Contents/MacOS/Blender",
        "C:\\Program Files\\Blender Foundation\\Blender*\\blender.exe",
    ]
    
    for path in search_paths:
        if File.new().file_exists(path):
            return path
    
    # Try PATH environment variable
    var exit_code = OS.execute("which" if OS.get_name() != "Windows" else "where", [exe_name])
    if exit_code == 0:
        return exe_name
    
    return ""
