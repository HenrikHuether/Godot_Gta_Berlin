extends Spatial
class_name BerlinMapExpansion

# Runtime extension for BerlinMap.tscn. The original map occupies x/z -260..260.
# This component fills the surrounding area up to x/z -700..700 without
# placing geometry in the original core or in the Reichstag mission area.
const CORE_HALF_EXTENT := 260.0
const MAP_HALF_EXTENT := 700.0
const OUTER_STRIP_CENTER := 480.0
const OUTER_STRIP_DEPTH := 440.0
const ROAD_LEVEL := 0.026

var _built := false
var _materials := {}


# The caller may either add this node first or let setup() attach it.
# Example:
#   var expansion = preload("res://scripts/map_expansion.gd").new()
#   expansion.setup(self)
func setup(game_root):
	if get_parent() == null:
		if game_root == null:
			push_error("BerlinMapExpansion.setup() requires a game root")
			return self
		game_root.add_child(self)
	name = "MapExpansion"
	build()
	return self


func build():
	if _built:
		return
	_built = true
	_build_materials()
	_build_outer_terrain()
	_build_roads_and_walkways()
	_build_outer_districts()
	_build_street_lighting()
	_build_boundary()


func get_map_bounds() -> AABB:
	return AABB(
		Vector3(-MAP_HALF_EXTENT, -0.4, -MAP_HALF_EXTENT),
		Vector3(MAP_HALF_EXTENT * 2.0, 90.0, MAP_HALF_EXTENT * 2.0)
	)


func _build_materials():
	_materials["grass"] = _make_material(Color("315835"), 0.96)
	_materials["asphalt"] = _make_material(Color("22262b"), 0.91)
	_materials["sidewalk"] = _make_material(Color("777875"), 0.88)
	_materials["curb"] = _make_material(Color("a6a39b"), 0.92)
	_materials["lane"] = _make_material(Color("e8e1bd"), 0.82)
	_materials["glass"] = _make_material(Color("233e4c"), 0.18, 0.28)
	_materials["glass_lit"] = _make_material(Color("f2c878"), 0.30, 0.05, true)
	_materials["roof"] = _make_material(Color("34383c"), 0.74, 0.25)
	_materials["metal"] = _make_material(Color("25292d"), 0.36, 0.62)
	_materials["door"] = _make_material(Color("342119"), 0.72)
	_materials["lamp"] = _make_material(Color("ffe0a0"), 0.24, 0.0, true)
	_materials["facade_0"] = _make_material(Color("d8c6a5"), 0.86)
	_materials["facade_1"] = _make_material(Color("b99d83"), 0.87)
	_materials["facade_2"] = _make_material(Color("c8c6bd"), 0.89)
	_materials["facade_3"] = _make_material(Color("a87763"), 0.88)
	_materials["facade_4"] = _make_material(Color("d1b978"), 0.86)


func _make_material(color: Color, roughness: float, metallic := 0.0, glowing := false) -> SpatialMaterial:
	var material = SpatialMaterial.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if glowing:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy = 1.35
	return material


func _make_section(section_name: String) -> Spatial:
	var section = Spatial.new()
	section.name = section_name
	add_child(section)
	return section


func _build_outer_terrain():
	var terrain = _make_section("ExpandedTerrain")
	# North/south include the corners. East/west only fill the remaining
	# centre strips, so no large coplanar ground surfaces overlap.
	_add_static_box(terrain, "NorthGround", Vector3(0, -0.2, -OUTER_STRIP_CENTER), Vector3(1400, 0.4, OUTER_STRIP_DEPTH), _materials["grass"])
	_add_static_box(terrain, "SouthGround", Vector3(0, -0.2, OUTER_STRIP_CENTER), Vector3(1400, 0.4, OUTER_STRIP_DEPTH), _materials["grass"])
	_add_static_box(terrain, "WestGround", Vector3(-OUTER_STRIP_CENTER, -0.2, 0), Vector3(OUTER_STRIP_DEPTH, 0.4, 520), _materials["grass"])
	_add_static_box(terrain, "EastGround", Vector3(OUTER_STRIP_CENTER, -0.2, 0), Vector3(OUTER_STRIP_DEPTH, 0.4, 520), _materials["grass"])


func _build_roads_and_walkways():
	var roads = _make_section("ExpandedRoadNetwork")
	var walkways = _make_section("ExpandedWalkways")

	# A square orbital road completely outside the legacy map.
	_add_road(roads, "RingNorth", Vector3(0, ROAD_LEVEL, -320), Vector3(1400, 0.052, 18), true)
	_add_road(roads, "RingSouth", Vector3(0, ROAD_LEVEL, 320), Vector3(1400, 0.052, 18), true)
	_add_road(roads, "RingWest", Vector3(-320, ROAD_LEVEL, 0), Vector3(18, 0.052, 1400), false)
	_add_road(roads, "RingEast", Vector3(320, ROAD_LEVEL, 0), Vector3(18, 0.052, 1400), false)

	# Continuations of the three strongest existing axes. Segments start at
	# +/-260, so no new surface is laid over BerlinMap.tscn.
	var route_axes = [-180.0, 0.0, 180.0]
	for axis in route_axes:
		_add_road(roads, "NorthRoute_%d" % int(axis), Vector3(axis, ROAD_LEVEL + 0.001, -480), Vector3(16, 0.054, 440), false)
		_add_road(roads, "SouthRoute_%d" % int(axis), Vector3(axis, ROAD_LEVEL + 0.001, 480), Vector3(16, 0.054, 440), false)
		_add_road(roads, "WestRoute_%d" % int(axis), Vector3(-480, ROAD_LEVEL + 0.002, axis), Vector3(440, 0.056, 16), true)
		_add_road(roads, "EastRoute_%d" % int(axis), Vector3(480, ROAD_LEVEL + 0.002, axis), Vector3(440, 0.056, 16), true)

	# Raised, colliding sidewalks along both sides of the ring road.
	for offset in [-12.0, 12.0]:
		_add_sidewalk(walkways, "NorthRingWalk", Vector3(0, 0.09, -320 + offset), Vector3(1400, 0.18, 4.0))
		_add_sidewalk(walkways, "SouthRingWalk", Vector3(0, 0.09, 320 + offset), Vector3(1400, 0.18, 4.0))
		_add_sidewalk(walkways, "WestRingWalk", Vector3(-320 + offset, 0.09, 0), Vector3(4.0, 0.18, 1400))
		_add_sidewalk(walkways, "EastRingWalk", Vector3(320 + offset, 0.09, 0), Vector3(4.0, 0.18, 1400))

	# Walkways on the central outbound routes make the expansion usable on foot.
	for side in [-11.0, 11.0]:
		_add_sidewalk(walkways, "NorthMainWalk", Vector3(side, 0.09, -480), Vector3(4.0, 0.18, 440))
		_add_sidewalk(walkways, "SouthMainWalk", Vector3(side, 0.09, 480), Vector3(4.0, 0.18, 440))
		_add_sidewalk(walkways, "WestMainWalk", Vector3(-480, 0.09, side), Vector3(440, 0.18, 4.0))
		_add_sidewalk(walkways, "EastMainWalk", Vector3(480, 0.09, side), Vector3(440, 0.18, 4.0))


func _add_road(parent: Node, road_name: String, position: Vector3, size: Vector3, horizontal: bool):
	_add_visual_box(parent, road_name, position, size, _materials["asphalt"])
	var start = -680.0
	while start <= 680.0:
		var marker_position = Vector3(start, position.y + 0.035, position.z) if horizontal else Vector3(position.x, position.y + 0.035, start)
		var marker_size = Vector3(6.0, 0.025, 0.20) if horizontal else Vector3(0.20, 0.025, 6.0)
		# Only emit a marker where it lies inside this particular road segment.
		if (horizontal and abs(start - position.x) <= size.x * 0.5) or (not horizontal and abs(start - position.z) <= size.z * 0.5):
			_add_visual_box(parent, "LaneMark", marker_position, marker_size, _materials["lane"])
		start += 18.0


func _add_sidewalk(parent: Node, sidewalk_name: String, position: Vector3, size: Vector3):
	_add_static_box(parent, sidewalk_name, position, size, _materials["sidewalk"])


func _build_outer_districts():
	var districts = _make_section("ExpandedDistricts")
	# 32 buildings give the outer districts a dense skyline while keeping the
	# runtime-generated node count reasonable on the GLES2 renderer.
	var grid = [-570.0, -440.0, -230.0, 230.0, 440.0, 570.0]
	var building_index = 0
	for x in grid:
		for z in grid:
			# The inner 720 x 720 square stays free. This includes all existing
			# city blocks, the Reichstag footprint and the orbital road.
			if abs(x) < 360.0 and abs(z) < 360.0:
				continue
			var width = 38.0 + float((building_index * 7) % 17)
			var depth = 36.0 + float((building_index * 11) % 15)
			var height = 19.0 + float((building_index * 13) % 34)
			_build_city_building(districts, building_index, Vector3(x, 0, z), Vector3(width, height, depth))
			building_index += 1


func _build_city_building(parent: Node, index: int, ground_position: Vector3, dimensions: Vector3):
	var facade_material = _materials["facade_%d" % (index % 5)]
	var width = dimensions.x
	var height = dimensions.y
	var depth = dimensions.z

	_add_static_box(
		parent,
		"BuildingSidewalk_%02d" % index,
		ground_position + Vector3(0, 0.09, 0),
		Vector3(width + 7.0, 0.18, depth + 7.0),
		_materials["sidewalk"]
	)
	var building = _add_static_box(
		parent,
		"OuterBuilding_%02d" % index,
		ground_position + Vector3(0, 0.18 + height * 0.5, 0),
		Vector3(width, height, depth),
		facade_material
	)

	# Cornice, roof cap and simple rooftop equipment break up the silhouettes.
	_add_visual_box(building, "Cornice", Vector3(0, height * 0.5 - 0.9, 0), Vector3(width + 0.8, 0.55, depth + 0.8), _materials["curb"])
	_add_visual_box(building, "RoofCap", Vector3(0, height * 0.5 + 0.22, 0), Vector3(width + 0.5, 0.44, depth + 0.5), _materials["roof"])
	_add_visual_box(building, "RoofUtility", Vector3(width * 0.18, height * 0.5 + 1.0, -depth * 0.12), Vector3(4.5, 1.55, 3.6), _materials["metal"])

	# A recessed-looking front entrance with lintel and canopy.
	var local_base = -height * 0.5
	_add_visual_box(building, "Entrance", Vector3(0, local_base + 1.65, depth * 0.5 + 0.035), Vector3(3.0, 3.3, 0.16), _materials["door"])
	_add_visual_box(building, "EntranceGlass", Vector3(0, local_base + 2.05, depth * 0.5 + 0.13), Vector3(1.65, 1.85, 0.08), _materials["glass"])
	_add_visual_box(building, "Canopy", Vector3(0, local_base + 3.5, depth * 0.5 + 0.75), Vector3(4.7, 0.22, 1.6), _materials["metal"])

	var floor_count = int(clamp(floor((height - 5.0) / 4.2), 3.0, 10.0))
	for floor_index in range(floor_count):
		var y = local_base + 5.0 + floor_index * 4.15
		var window_material = _materials["glass_lit"] if (index + floor_index) % 4 == 0 else _materials["glass"]
		_add_window_band(building, "FrontWindows", Vector3(0, y, depth * 0.5 + 0.045), Vector3(width * 0.76, 1.15, 0.12), window_material)
		_add_window_band(building, "RearWindows", Vector3(0, y, -depth * 0.5 - 0.045), Vector3(width * 0.76, 1.15, 0.12), window_material)
		_add_window_band(building, "LeftWindows", Vector3(-width * 0.5 - 0.045, y, 0), Vector3(0.12, 1.15, depth * 0.67), window_material)
		_add_window_band(building, "RightWindows", Vector3(width * 0.5 + 0.045, y, 0), Vector3(0.12, 1.15, depth * 0.67), window_material)
	_add_facade_piers(building, width, height, depth)


func _add_window_band(parent: Node, band_name: String, position: Vector3, size: Vector3, material):
	_add_visual_box(parent, band_name, position, size, material)


func _add_facade_piers(parent: Node, width: float, height: float, depth: float):
	# Shared vertical piers divide every window row at once. This gives the
	# facades rhythm without creating several mullion nodes per floor.
	var pier_height = height - 5.6
	for divider in [-0.25, 0.25]:
		var front_x = width * divider
		_add_visual_box(parent, "FrontPier", Vector3(front_x, 1.4, depth * 0.5 + 0.12), Vector3(0.18, pier_height, 0.20), _materials["metal"])
	for side_divider in [-0.25, 0.0, 0.25]:
		var side_x = width * side_divider
		var side_z = depth * side_divider
		_add_visual_box(parent, "RearPier", Vector3(side_x, 1.4, -depth * 0.5 - 0.12), Vector3(0.18, pier_height, 0.20), _materials["metal"])
		_add_visual_box(parent, "LeftPier", Vector3(-width * 0.5 - 0.12, 1.4, side_z), Vector3(0.20, pier_height, 0.18), _materials["metal"])
		_add_visual_box(parent, "RightPier", Vector3(width * 0.5 + 0.12, 1.4, side_z), Vector3(0.20, pier_height, 0.18), _materials["metal"])


func _build_street_lighting():
	var lighting = _make_section("ExpandedStreetLighting")
	var positions = [-580.0, -450.0, -250.0, -90.0, 90.0, 250.0, 450.0, 580.0]
	var lamp_index = 0
	for coordinate in positions:
		_build_street_lamp(lighting, Vector3(coordinate, 0, -336), lamp_index)
		lamp_index += 1
		_build_street_lamp(lighting, Vector3(coordinate, 0, 336), lamp_index)
		lamp_index += 1
		_build_street_lamp(lighting, Vector3(-336, 0, coordinate), lamp_index)
		lamp_index += 1
		_build_street_lamp(lighting, Vector3(336, 0, coordinate), lamp_index)
		lamp_index += 1


func _build_street_lamp(parent: Node, position: Vector3, index: int):
	var lamp = Spatial.new()
	lamp.name = "ExpansionLamp_%02d" % index
	lamp.translation = position
	parent.add_child(lamp)
	_add_visual_cylinder(lamp, "Pole", Vector3(0, 3.1, 0), 0.10, 6.2, _materials["metal"])
	_add_visual_box(lamp, "LampHousing", Vector3(0, 6.25, 0), Vector3(0.75, 0.25, 0.42), _materials["metal"])
	_add_visual_box(lamp, "LampGlow", Vector3(0, 6.08, 0), Vector3(0.56, 0.08, 0.30), _materials["lamp"])
	# Eleven real lights are enough to illuminate the new roads without the
	# cost of casting dozens of overlapping GLES2 lights.
	if index % 3 == 0:
		var light = OmniLight.new()
		light.name = "RoadLight"
		light.translation = Vector3(0, 5.9, 0)
		light.light_color = Color("ffdca0")
		light.light_energy = 0.72
		light.omni_range = 19.0
		light.shadow_enabled = false
		lamp.add_child(light)


func _build_boundary():
	var boundary = _make_section("ExpandedMapBoundary")
	var barrier_material = _materials["metal"]
	# A low guard rail makes the expanded edge readable and prevents vehicles
	# from falling into empty space beyond the generated ground.
	_add_static_box(boundary, "NorthBoundary", Vector3(0, 0.55, -699), Vector3(1400, 1.1, 1.2), barrier_material)
	_add_static_box(boundary, "SouthBoundary", Vector3(0, 0.55, 699), Vector3(1400, 1.1, 1.2), barrier_material)
	_add_static_box(boundary, "WestBoundary", Vector3(-699, 0.55, 0), Vector3(1.2, 1.1, 1400), barrier_material)
	_add_static_box(boundary, "EastBoundary", Vector3(699, 0.55, 0), Vector3(1.2, 1.1, 1400), barrier_material)


func _add_static_box(parent: Node, node_name: String, position: Vector3, size: Vector3, material) -> StaticBody:
	var body = StaticBody.new()
	body.name = node_name
	body.translation = position
	parent.add_child(body)
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = "Mesh"
	var mesh = CubeMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	var collision_shape = CollisionShape.new()
	collision_shape.name = "CollisionShape"
	var shape = BoxShape.new()
	shape.extents = size * 0.5
	collision_shape.shape = shape
	body.add_child(collision_shape)
	return body


func _add_visual_box(parent: Node, node_name: String, position: Vector3, size: Vector3, material) -> MeshInstance:
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = node_name
	mesh_instance.translation = position
	var mesh = CubeMesh.new()
	mesh.size = size
	mesh.material = material
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	return mesh_instance


func _add_visual_cylinder(parent: Node, node_name: String, position: Vector3, radius: float, height: float, material) -> MeshInstance:
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = node_name
	mesh_instance.translation = position
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.material = material
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	return mesh_instance
