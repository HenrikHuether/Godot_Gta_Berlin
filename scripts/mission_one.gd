extends Spatial

const HUMAN_SCENE = preload("res://Assets/HumanV2.glb")
const PERSUASION_EVALUATOR = preload("res://scripts/persuasion_evaluator.gd")

enum MissionState {
	ENTER_CAR,
	DRIVE_TO_BUNDESTAG,
	GAIN_ACCESS,
	ENTER_BUILDING,
	DELIVER_CASE,
	COMPLETE
}

const BUILDING_CENTER = Vector3(-135.0, 0.0, -40.0)
const PARKING_POSITION = Vector3(-56.0, 0.1, -92.0)
const GUARD_POSITION = Vector3(-130.5, 0.05, -99.5)
const RECIPIENT_POSITION = Vector3(-135.0, 0.05, -52.0)
const DELIVERY_POSITION = Vector3(-135.0, 0.2, -58.5)
const CRATE_START = Vector3(-210.0, 0.80, -40.0)

const BUILDING_LENGTH := 138.0
const BUILDING_WIDTH := 98.0
const BUILDING_HEIGHT := 24.0
const DOME_RADIUS := 20.0
const DOME_HEIGHT := 23.5
const DOME_OPENING_RADIUS := 4.0
const DOME_RING_COUNT := 17
const DOME_RIB_COUNT := 24
const SITE_CLEARANCE := 0.75
const SITE_APRON_LOCAL_CENTER_Z := -56.0
const SITE_APRON_HALF_WIDTH := 75.0
const SITE_APRON_HALF_DEPTH := 7.0

var game
var state = MissionState.ENTER_CAR
var has_briefcase = true
var mission_completed = false
var front_door_open = false
var hidden_door_open = false
var access_route = ""
var started_msec = 0

var front_door: StaticBody
var hidden_door: StaticBody
var push_crate: RigidBody
var guard: StaticBody
var recipient: StaticBody
var waypoint: Spatial
var waypoint_ring: MeshInstance
var briefcase_model: Spatial

var mission_layer: CanvasLayer
var objective_label: Label
var distance_label: Label
var inventory_label: Label
var notice_label: Label
var notice_time = 0.0
var completion_panel: ColorRect
var completion_label: Label

var dialogue_layer: CanvasLayer
var dialogue_panel: ColorRect
var dialogue_transcript: RichTextLabel
var dialogue_input: LineEdit
var dialogue_send: Button
var dialogue_close: Button
var dialogue_history = ""
var evaluator


func setup(game_root):
	game = game_root
	started_msec = OS.get_ticks_msec()
	evaluator = PERSUASION_EVALUATOR.new()
	prepare_bundestag_site()
	build_bundestag()
	build_mission_characters()
	build_push_crate()
	build_waypoint()
	build_briefcase()
	build_mission_ui()
	build_dialogue_ui()
	set_state(MissionState.ENTER_CAR)
	show_notice("MISSION 1: SONDERZUSTELLUNG", Color("f4d35e"))


func make_material(color: Color, glowing := false) -> SpatialMaterial:
	var mat = SpatialMaterial.new()
	mat.albedo_color = color
	mat.roughness = 0.78
	if glowing:
		mat.flags_unshaded = true
		mat.emission_enabled = true
		mat.emission = color
	return mat


func add_static_box(parent: Node, node_name: String, position: Vector3, size: Vector3, color: Color) -> StaticBody:
	var body = StaticBody.new()
	body.name = node_name
	body.translation = position
	parent.add_child(body)
	var mesh_instance = MeshInstance.new()
	var mesh = CubeMesh.new()
	mesh.size = size
	mesh.material = make_material(color)
	mesh_instance.mesh = mesh
	body.add_child(mesh_instance)
	var collision = CollisionShape.new()
	var shape = BoxShape.new()
	shape.extents = size * 0.5
	collision.shape = shape
	body.add_child(collision)
	return body


func add_visual_box(parent: Node, node_name: String, position: Vector3, size: Vector3, color: Color, glowing := false) -> MeshInstance:
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = node_name
	mesh_instance.translation = position
	var mesh = CubeMesh.new()
	mesh.size = size
	mesh.material = make_material(color, glowing)
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	return mesh_instance


func add_visual_cylinder(parent: Node, node_name: String, position: Vector3, radius: float, height: float, color: Color, glowing := false) -> MeshInstance:
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = node_name
	mesh_instance.translation = position
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	mesh.material = make_material(color, glowing)
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	return mesh_instance


func add_visual_frustum(parent: Node, node_name: String, position: Vector3, bottom_radius: float, top_radius: float, height: float, color: Color) -> MeshInstance:
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = node_name
	mesh_instance.translation = position
	var mesh = CylinderMesh.new()
	mesh.bottom_radius = bottom_radius
	mesh.top_radius = top_radius
	mesh.height = height
	mesh.radial_segments = 24
	mesh.rings = 4
	mesh.material = make_material(color)
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	return mesh_instance


func add_visual_sphere(parent: Node, node_name: String, position: Vector3, radius: float, color: Color) -> MeshInstance:
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = node_name
	mesh_instance.translation = position
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	mesh.material = make_material(color)
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	return mesh_instance


func prepare_bundestag_site():
	if game == null:
		return
	var berlin_map = game.get_node_or_null("BerlinMap")
	if berlin_map == null:
		return

	# Roof and cornices project one metre beyond the 138 x 98 metre wall shell.
	# The union with the west entrance apron is the complete area that must be
	# clear. A small tolerance prevents coplanar facade faces from flickering.
	var shell_half_width = BUILDING_LENGTH * 0.5 + 1.0
	var shell_half_depth = BUILDING_WIDTH * 0.5 + 1.0
	var site_min = Vector2(
		BUILDING_CENTER.x - max(shell_half_width, SITE_APRON_HALF_WIDTH) - SITE_CLEARANCE,
		min(
			BUILDING_CENTER.z - shell_half_depth,
			BUILDING_CENTER.z + SITE_APRON_LOCAL_CENTER_Z - SITE_APRON_HALF_DEPTH
		) - SITE_CLEARANCE
	)
	var site_max = Vector2(
		BUILDING_CENTER.x + max(shell_half_width, SITE_APRON_HALF_WIDTH) + SITE_CLEARANCE,
		max(
			BUILDING_CENTER.z + shell_half_depth,
			BUILDING_CENTER.z + SITE_APRON_LOCAL_CENTER_Z + SITE_APRON_HALF_DEPTH
		) + SITE_CLEARANCE
	)

	# Collect before detaching anything: mutating a block while traversing its
	# children used to leave neighbouring or nested facade nodes behind.
	var structure_roots = []
	_collect_existing_structure_roots(berlin_map, berlin_map, structure_roots)
	var structures_to_remove = []
	for structure_root in structure_roots:
		if _node_geometry_overlaps_site(structure_root, site_min, site_max):
			structures_to_remove.append(structure_root)
	for structure_root in structures_to_remove:
		_detach_site_node(structure_root)

	# Trees and lamps inside the footprint would otherwise poke through the new
	# building. Sidewalks, courtyards, road meshes, lane marks and ground stay.
	var obstructions_to_remove = []
	_collect_site_obstructions(berlin_map, site_min, site_max, obstructions_to_remove)
	for obstruction in obstructions_to_remove:
		_detach_site_node(obstruction)


func _collect_existing_structure_roots(current: Node, berlin_map: Node, output: Array):
	for child in current.get_children():
		var child_name = String(child.name)
		if child_name.begins_with("Building_"):
			output.append(child)
			continue
		if current == berlin_map:
			if child_name.begins_with("Block_"):
				_collect_existing_structure_roots(child, berlin_map, output)
			elif not _is_protected_map_surface(child_name) and not _is_site_obstruction_name(child_name):
				# Top-level landmarks such as BrandenburgGate can also contain their
				# collision and decorative geometry several levels down.
				output.append(child)
			continue
		_collect_existing_structure_roots(child, berlin_map, output)


func _is_protected_map_surface(node_name: String) -> bool:
	return (
		node_name == "Ground"
		or node_name.begins_with("Road_")
		or node_name.find("LaneMark") != -1
		or node_name.find("Crosswalk") != -1
	)


func _is_site_obstruction_name(node_name: String) -> bool:
	return node_name.find("StreetLamp") != -1 or node_name.find("Tree") != -1


func _collect_site_obstructions(current: Node, site_min: Vector2, site_max: Vector2, output: Array):
	for child in current.get_children():
		var child_name = String(child.name)
		if _is_site_obstruction_name(child_name):
			if _node_geometry_overlaps_site(child, site_min, site_max):
				output.append(child)
			continue
		_collect_site_obstructions(child, site_min, site_max, output)


func _node_geometry_overlaps_site(node: Node, site_min: Vector2, site_max: Vector2) -> bool:
	if node is MeshInstance and node.mesh != null:
		if _transformed_aabb_overlaps_site(node.get_aabb(), node.global_transform, site_min, site_max):
			return true
	elif node is CollisionShape and node.shape is BoxShape:
		var extents = node.shape.extents
		var local_box = AABB(Vector3(-extents.x, -extents.y, -extents.z), extents * 2.0)
		if _transformed_aabb_overlaps_site(local_box, node.global_transform, site_min, site_max):
			return true
	for child in node.get_children():
		if _node_geometry_overlaps_site(child, site_min, site_max):
			return true
	return false


func _transformed_aabb_overlaps_site(local_box: AABB, world_transform: Transform, site_min: Vector2, site_max: Vector2) -> bool:
	var bounds_initialized = false
	var world_min = Vector2()
	var world_max = Vector2()
	for x_side in range(2):
		for y_side in range(2):
			for z_side in range(2):
				var local_point = local_box.position + Vector3(
					local_box.size.x * float(x_side),
					local_box.size.y * float(y_side),
					local_box.size.z * float(z_side)
				)
				var world_point = world_transform.xform(local_point)
				var point_2d = Vector2(world_point.x, world_point.z)
				if not bounds_initialized:
					world_min = point_2d
					world_max = point_2d
					bounds_initialized = true
				else:
					world_min.x = min(world_min.x, point_2d.x)
					world_min.y = min(world_min.y, point_2d.y)
					world_max.x = max(world_max.x, point_2d.x)
					world_max.y = max(world_max.y, point_2d.y)
	return (
		world_max.x >= site_min.x
		and world_min.x <= site_max.x
		and world_max.y >= site_min.y
		and world_min.y <= site_max.y
	)


func _detach_site_node(node: Node):
	if not is_instance_valid(node):
		return
	var parent = node.get_parent()
	if parent != null:
		# Detach synchronously so build_bundestag() cannot share a rendered or
		# colliding frame with the old geometry; free safely at frame end.
		parent.remove_child(node)
	node.queue_free()


func build_bundestag():
	var building = Spatial.new()
	building.name = "BundestagMissionBuilding"
	building.translation = BUILDING_CENTER
	add_child(building)

	var sandstone = Color("c9b58f")
	var sandstone_light = Color("e0d0ae")
	var sandstone_shadow = Color("a69170")
	var roof_color = Color("4b5356")

	# The 138 x 98 metre shell and 24 metre roof line use one Godot unit per metre.
	# A shallow apron masks the old road surface where the monumental stairs meet it.
	add_static_box(
		building,
		"WestEntranceApron",
		Vector3(0, 0.09, SITE_APRON_LOCAL_CENTER_Z),
		Vector3(SITE_APRON_HALF_WIDTH * 2.0, 0.18, SITE_APRON_HALF_DEPTH * 2.0),
		Color("aaa69d")
	)
	add_static_box(building, "InteriorFloor", Vector3(0, 0.12, 0), Vector3(BUILDING_LENGTH, 0.24, BUILDING_WIDTH), Color("b7b1a5"))

	# Exterior collision shell. Gaps are retained for the public west portal and
	# the crate-operated service passage on the north-west side.
	add_static_box(building, "FrontWallLeft", Vector3(-37.5, 12.0, -49.0), Vector3(63.0, 24.0, 1.2), sandstone)
	add_static_box(building, "FrontWallRight", Vector3(37.5, 12.0, -49.0), Vector3(63.0, 24.0, 1.2), sandstone)
	add_static_box(building, "FrontWallAboveDoor", Vector3(0, 15.8, -49.0), Vector3(12.0, 16.4, 1.2), sandstone)
	add_static_box(building, "RearWall", Vector3(0, 12.0, 49.0), Vector3(138.0, 24.0, 1.2), sandstone)
	add_static_box(building, "EastWall", Vector3(69.0, 12.0, 0), Vector3(1.2, 24.0, 98.0), sandstone)
	add_static_box(building, "WestWallFront", Vector3(-69.0, 12.0, -26.0), Vector3(1.2, 24.0, 46.0), sandstone)
	add_static_box(building, "WestWallRear", Vector3(-69.0, 12.0, 26.0), Vector3(1.2, 24.0, 46.0), sandstone)
	add_static_box(building, "WestWallAboveServiceDoor", Vector3(-69.0, 14.25, 0), Vector3(1.2, 19.5, 6.0), sandstone)
	add_static_box(building, "RoofTerrace", Vector3(0, 24.2, 0), Vector3(140.0, 0.4, 100.0), roof_color)

	build_corner_towers(building, sandstone, sandstone_light)
	build_facade_cornices(building, sandstone_shadow, sandstone_light)
	build_facade_windows(building)
	build_west_portico(building, sandstone_light, sandstone_shadow)
	build_reichstag_dome(building)

	front_door = add_static_box(building, "SecureMainDoor", Vector3(0, 4.8, -49.2), Vector3(10.0, 5.6, 0.65), Color("264654"))
	hidden_door = add_static_box(building, "ConcealedServiceDoor", Vector3(-69.2, 2.25, 0), Vector3(0.65, 4.5, 5.8), Color("7b756c"))
	add_visual_box(building, "ServiceDoorSeam", Vector3(-69.56, 2.25, 0), Vector3(0.03, 4.65, 5.95), Color("3b3a38"))

	# The mission interior remains intentionally compact inside the full shell:
	# delivery desk, archive stacks and service tunnel keep their original roles.
	add_static_box(building, "DeliveryDesk", Vector3(0, 0.75, -15.0), Vector3(10.0, 1.5, 1.8), Color("584331"))
	var desk_glass = add_visual_box(building, "DeskGlass", Vector3(0, 1.75, -15.35), Vector3(9.4, 0.85, 0.10), Color(0.28, 0.55, 0.65, 0.62))
	var desk_glass_material = desk_glass.mesh.material as SpatialMaterial
	desk_glass_material.flags_transparent = true
	for shelf_z in [12.0, 22.0, 32.0]:
		add_static_box(building, "ArchiveShelf", Vector3(-51.0, 1.5, shelf_z), Vector3(3.0, 3.0, 6.0), Color("4c3b2d"))
	add_visual_box(building, "ServiceTunnelCeiling", Vector3(-64.0, 4.75, 0), Vector3(10.0, 0.25, 7.0), Color("4d5050"))
	for tunnel_z in [-3.35, 3.35]:
		add_visual_box(building, "TunnelRail", Vector3(-64.0, 2.2, tunnel_z), Vector3(10.0, 0.18, 0.18), Color("8f8d82"))

	for light_position in [Vector3(0, 10.0, -20.0), Vector3(-35.0, 10.0, 18.0), Vector3(35.0, 10.0, 18.0), Vector3(-62.0, 4.0, 0)]:
		var interior_light = OmniLight.new()
		interior_light.name = "InteriorLight"
		interior_light.translation = light_position
		interior_light.light_color = Color("fff1cf")
		interior_light.light_energy = 1.15
		interior_light.omni_range = 42.0
		building.add_child(interior_light)


func build_corner_towers(building: Spatial, sandstone: Color, trim_color: Color):
	var tower_positions = [
		Vector3(-56.0, 12.0, -36.5),
		Vector3(-56.0, 12.0, 36.5),
		Vector3(56.0, 12.0, -36.5),
		Vector3(56.0, 12.0, 36.5),
	]
	for tower_index in range(tower_positions.size()):
		var tower_position = tower_positions[tower_index]
		add_visual_box(building, "CornerTower%02d" % tower_index, tower_position, Vector3(26.0, 24.0, 25.0), sandstone)
		add_visual_box(building, "CornerTowerCornice%02d" % tower_index, Vector3(tower_position.x, 23.25, tower_position.z), Vector3(28.0, 1.25, 27.0), trim_color)
		add_visual_box(building, "CornerTowerParapet%02d" % tower_index, Vector3(tower_position.x, 24.45, tower_position.z), Vector3(26.5, 1.15, 25.5), sandstone)
		add_tower_flag(building, "TowerFlag%02d" % tower_index, Vector3(tower_position.x, 25.0, tower_position.z), tower_index == 2)


func add_tower_flag(parent: Node, prefix: String, base_position: Vector3, european: bool):
	add_visual_cylinder(parent, prefix + "Pole", base_position + Vector3(0, 5.0, 0), 0.12, 10.0, Color("343a3d"))
	if european:
		add_visual_box(parent, prefix + "EuropeBlue", base_position + Vector3(2.5, 8.0, 0), Vector3(5.0, 2.6, 0.10), Color("17458f"))
		for star_index in range(8):
			var angle = float(star_index) / 8.0 * PI * 2.0
			add_visual_sphere(parent, prefix + "Star%02d" % star_index, base_position + Vector3(2.5 + cos(angle) * 0.72, 8.0 + sin(angle) * 0.72, -0.08), 0.10, Color("f2d34f"))
	else:
		add_visual_box(parent, prefix + "Black", base_position + Vector3(2.5, 8.55, 0), Vector3(5.0, 0.55, 0.10), Color("171717"))
		add_visual_box(parent, prefix + "Red", base_position + Vector3(2.5, 8.0, 0), Vector3(5.0, 0.55, 0.10), Color("c52b35"))
		add_visual_box(parent, prefix + "Gold", base_position + Vector3(2.5, 7.45, 0), Vector3(5.0, 0.55, 0.10), Color("e4b43c"))


func build_facade_cornices(building: Spatial, shadow_color: Color, light_color: Color):
	for band_y in [1.15, 8.1, 15.4, 23.15]:
		var band_height = 1.0 if band_y == 1.15 or band_y == 23.15 else 0.55
		var band_color = light_color if band_y >= 15.0 else shadow_color
		add_visual_box(building, "FrontCornice", Vector3(0, band_y, -49.68), Vector3(140.0, band_height, 0.32), band_color)
		add_visual_box(building, "RearCornice", Vector3(0, band_y, 49.68), Vector3(140.0, band_height, 0.32), band_color)
		add_visual_box(building, "EastCornice", Vector3(69.68, band_y, 0), Vector3(0.32, band_height, 100.0), band_color)
		add_visual_box(building, "WestCornice", Vector3(-69.68, band_y, 0), Vector3(0.32, band_height, 100.0), band_color)


func build_facade_windows(building: Spatial):
	var glass_color = Color("304b5c")
	var frame_color = Color("8f8068")
	var facade_x_positions = [-60.0, -50.0, -40.0, -30.0, -20.0, -10.0, 0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0]
	var facade_z_positions = [-38.0, -28.0, -18.0, -8.0, 8.0, 18.0, 28.0, 38.0]
	var row_heights = [4.7, 11.6, 18.4]
	var window_index = 0
	for row_y in row_heights:
		for window_x in facade_x_positions:
			if abs(window_x) >= 17.0:
				add_visual_box(building, "FrontWindow%03d" % window_index, Vector3(window_x, row_y, -49.86), Vector3(4.8, 4.7, 0.12), glass_color)
				add_visual_box(building, "FrontLintel%03d" % window_index, Vector3(window_x, row_y + 2.5, -49.96), Vector3(5.5, 0.28, 0.18), frame_color)
			add_visual_box(building, "RearWindow%03d" % window_index, Vector3(window_x, row_y, 49.86), Vector3(4.8, 4.7, 0.12), glass_color)
			add_visual_box(building, "RearLintel%03d" % window_index, Vector3(window_x, row_y + 2.5, 49.96), Vector3(5.5, 0.28, 0.18), frame_color)
			window_index += 1
		for window_z in facade_z_positions:
			add_visual_box(building, "EastWindow%03d" % window_index, Vector3(69.86, row_y, window_z), Vector3(0.12, 4.7, 4.8), glass_color)
			add_visual_box(building, "EastLintel%03d" % window_index, Vector3(69.96, row_y + 2.5, window_z), Vector3(0.18, 0.28, 5.5), frame_color)
			add_visual_box(building, "WestWindow%03d" % window_index, Vector3(-69.86, row_y, window_z), Vector3(0.12, 4.7, 4.8), glass_color)
			add_visual_box(building, "WestLintel%03d" % window_index, Vector3(-69.96, row_y + 2.5, window_z), Vector3(0.18, 0.28, 5.5), frame_color)
			window_index += 1


func build_west_portico(building: Spatial, stone_color: Color, shadow_color: Color):
	for stair_index in range(8):
		var step_height = 0.25 * float(stair_index + 1)
		var step_z = -57.5 + float(stair_index) * 1.1
		add_visual_box(building, "EntranceStep%d" % stair_index, Vector3(0, step_height * 0.5, step_z), Vector3(44.0, step_height, 1.25), Color("aaa398"))
	# A hidden shallow ramp under the visible risers makes the monumental stair
	# reliably walkable with the existing KinematicBody controller.
	var stair_ramp = StaticBody.new()
	stair_ramp.name = "EntranceStairRamp"
	stair_ramp.translation = Vector3(0, 1.05, -53.65)
	stair_ramp.rotation_degrees.x = -12.8
	var ramp_collision = CollisionShape.new()
	var ramp_shape = BoxShape.new()
	ramp_shape.extents = Vector3(20.5, 0.12, 4.85)
	ramp_collision.shape = ramp_shape
	stair_ramp.add_child(ramp_collision)
	building.add_child(stair_ramp)
	add_static_box(building, "StairCheekLeft", Vector3(-23.0, 1.2, -53.6), Vector3(2.0, 2.4, 10.0), shadow_color)
	add_static_box(building, "StairCheekRight", Vector3(23.0, 1.2, -53.6), Vector3(2.0, 2.4, 10.0), shadow_color)

	var column_positions = [-13.5, -8.1, -2.7, 2.7, 8.1, 13.5]
	for column_index in range(column_positions.size()):
		var column_x = column_positions[column_index]
		add_visual_box(building, "ColumnBase%02d" % column_index, Vector3(column_x, 2.25, -52.0), Vector3(2.8, 0.5, 2.8), shadow_color)
		add_visual_cylinder(building, "FacadeColumn%02d" % column_index, Vector3(column_x, 8.0, -52.0), 1.1, 11.5, stone_color)
		add_visual_box(building, "ColumnCapital%02d" % column_index, Vector3(column_x, 13.75, -52.0), Vector3(2.9, 0.55, 2.9), stone_color)

	add_visual_box(building, "PorticoEntablature", Vector3(0, 14.55, -51.5), Vector3(38.0, 1.8, 5.0), stone_color)
	add_visual_triangular_prism(building, "WestPediment", Vector3(0, 15.45, -51.5), 38.0, 6.0, 4.6, stone_color)
	add_visual_box(building, "InscriptionPanel", Vector3(0, 14.65, -54.08), Vector3(22.0, 1.3, 0.16), Color("d7c8a7"))
	var inscription = Label3D.new()
	inscription.name = "DemDeutschenVolkeInscription"
	inscription.text = "DEM DEUTSCHEN VOLKE"
	inscription.translation = Vector3(0, 14.62, -54.19)
	inscription.rotation_degrees.y = 180.0
	inscription.pixel_size = 0.04
	inscription.modulate = Color("3c3428")
	building.add_child(inscription)

	# Simplified heraldic relief plaques make the portal readable at driving range.
	for relief_x in [-20.5, 20.5]:
		add_visual_box(building, "HeraldicRelief", Vector3(relief_x, 10.0, -49.72), Vector3(6.0, 8.0, 0.28), Color("b7a37e"))
		add_visual_sphere(building, "ReliefMedallion", Vector3(relief_x, 11.1, -49.92), 1.35, stone_color)


func add_visual_triangular_prism(parent: Node, node_name: String, position: Vector3, width: float, height: float, depth: float, color: Color) -> MeshInstance:
	var half_width = width * 0.5
	var half_depth = depth * 0.5
	var front_left = Vector3(-half_width, 0, -half_depth)
	var front_right = Vector3(half_width, 0, -half_depth)
	var front_top = Vector3(0, height, -half_depth)
	var rear_left = Vector3(-half_width, 0, half_depth)
	var rear_right = Vector3(half_width, 0, half_depth)
	var rear_top = Vector3(0, height, half_depth)
	var surface = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_surface_triangle(surface, front_left, front_right, front_top)
	_add_surface_triangle(surface, rear_right, rear_left, rear_top)
	_add_surface_quad(surface, front_left, rear_left, rear_right, front_right)
	_add_surface_quad(surface, front_left, front_top, rear_top, rear_left)
	_add_surface_quad(surface, front_top, front_right, rear_right, rear_top)
	surface.generate_normals()
	var prism_mesh = surface.commit()
	var prism_material = make_material(color)
	prism_material.params_cull_mode = SpatialMaterial.CULL_DISABLED
	prism_mesh.surface_set_material(0, prism_material)
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = node_name
	mesh_instance.translation = position
	mesh_instance.mesh = prism_mesh
	parent.add_child(mesh_instance)
	return mesh_instance


func build_reichstag_dome(building: Spatial):
	add_visual_cylinder(building, "DomeBase", Vector3(0, 24.25, 0), 20.6, 0.8, Color("505b60"))
	# A single convex hull uses the same profile points as the visible glass.
	# It is solid and gapless without the conspicuous invisible ledges produced
	# by stacked cylinder approximations.
	var dome_collision_body = StaticBody.new()
	dome_collision_body.name = "DomeCollisionHull"
	building.add_child(dome_collision_body)
	var dome_collision = CollisionShape.new()
	dome_collision.name = "CollisionShape"
	var dome_shape = ConvexPolygonShape.new()
	var dome_points = PoolVector3Array()
	for collision_ring_index in range(DOME_RING_COUNT):
		var collision_profile = dome_profile(collision_ring_index)
		for collision_segment_index in range(DOME_RIB_COUNT):
			var collision_angle = float(collision_segment_index) / float(DOME_RIB_COUNT) * PI * 2.0
			dome_points.append(dome_point(collision_profile.x, collision_profile.y, collision_angle))
	dome_shape.points = dome_points
	dome_collision.shape = dome_shape
	dome_collision_body.add_child(dome_collision)

	var glass_surface = SurfaceTool.new()
	glass_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring_index in range(DOME_RING_COUNT - 1):
		var lower_profile = dome_profile(ring_index)
		var upper_profile = dome_profile(ring_index + 1)
		for segment_index in range(DOME_RIB_COUNT):
			var angle_a = float(segment_index) / float(DOME_RIB_COUNT) * PI * 2.0
			var angle_b = float(segment_index + 1) / float(DOME_RIB_COUNT) * PI * 2.0
			var lower_a = dome_point(lower_profile.x, lower_profile.y, angle_a)
			var lower_b = dome_point(lower_profile.x, lower_profile.y, angle_b)
			var upper_a = dome_point(upper_profile.x, upper_profile.y, angle_a)
			var upper_b = dome_point(upper_profile.x, upper_profile.y, angle_b)
			_add_surface_quad(glass_surface, lower_a, lower_b, upper_b, upper_a)
	glass_surface.generate_normals()
	var glass_mesh = glass_surface.commit()
	var glass_material = make_material(Color(0.24, 0.50, 0.64, 0.34))
	glass_material.flags_transparent = true
	glass_material.flags_unshaded = true
	glass_material.params_cull_mode = SpatialMaterial.CULL_DISABLED
	glass_material.roughness = 0.18
	glass_mesh.surface_set_material(0, glass_material)
	var glass_dome = MeshInstance.new()
	glass_dome.name = "GlassDome"
	glass_dome.mesh = glass_mesh
	building.add_child(glass_dome)

	# The steel is consolidated into one mesh: 24 curved ribs and 17 rings without
	# hundreds of individual nodes.
	var steel_surface = SurfaceTool.new()
	steel_surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for rib_index in range(DOME_RIB_COUNT):
		var rib_angle = float(rib_index) / float(DOME_RIB_COUNT) * PI * 2.0
		for ring_index in range(DOME_RING_COUNT - 1):
			var lower_profile = dome_profile(ring_index)
			var upper_profile = dome_profile(ring_index + 1)
			var lower_half_angle = 0.11 / max(4.0, lower_profile.x)
			var upper_half_angle = 0.11 / max(4.0, upper_profile.x)
			var lower_left = dome_point(lower_profile.x + 0.08, lower_profile.y, rib_angle - lower_half_angle)
			var lower_right = dome_point(lower_profile.x + 0.08, lower_profile.y, rib_angle + lower_half_angle)
			var upper_left = dome_point(upper_profile.x + 0.08, upper_profile.y, rib_angle - upper_half_angle)
			var upper_right = dome_point(upper_profile.x + 0.08, upper_profile.y, rib_angle + upper_half_angle)
			_add_surface_quad(steel_surface, lower_left, lower_right, upper_right, upper_left)
	for ring_index in range(DOME_RING_COUNT):
		var profile = dome_profile(ring_index)
		for segment_index in range(DOME_RIB_COUNT):
			var angle_a = float(segment_index) / float(DOME_RIB_COUNT) * PI * 2.0
			var angle_b = float(segment_index + 1) / float(DOME_RIB_COUNT) * PI * 2.0
			var lower_a = dome_point(profile.x + 0.10, profile.y - 0.10, angle_a)
			var lower_b = dome_point(profile.x + 0.10, profile.y - 0.10, angle_b)
			var upper_a = dome_point(profile.x + 0.10, profile.y + 0.10, angle_a)
			var upper_b = dome_point(profile.x + 0.10, profile.y + 0.10, angle_b)
			_add_surface_quad(steel_surface, lower_a, lower_b, upper_b, upper_a)
	steel_surface.generate_normals()
	var steel_mesh = steel_surface.commit()
	var steel_material = make_material(Color("7b8589"))
	steel_material.metallic = 0.75
	steel_material.roughness = 0.28
	steel_material.params_cull_mode = SpatialMaterial.CULL_DISABLED
	steel_mesh.surface_set_material(0, steel_material)
	var dome_steel = MeshInstance.new()
	dome_steel.name = "DomeRibsAndRings"
	dome_steel.mesh = steel_mesh
	building.add_child(dome_steel)

	var mirror_cone = add_visual_frustum(building, "MirrorLightFunnel", Vector3(0, 34.25, 0), 3.2, 8.5, 19.0, Color("c5d0d2"))
	var mirror_material = mirror_cone.mesh.material as SpatialMaterial
	mirror_material.metallic = 0.92
	mirror_material.roughness = 0.10

	var dome_light = OmniLight.new()
	dome_light.name = "DomeNightBeacon"
	dome_light.translation = Vector3(0, 36.0, 0)
	dome_light.light_color = Color("d9eef5")
	dome_light.light_energy = 1.1
	dome_light.omni_range = 36.0
	building.add_child(dome_light)


func dome_profile(ring_index: int) -> Vector2:
	var amount = float(ring_index) / float(DOME_RING_COUNT - 1)
	var maximum_angle = acos(DOME_OPENING_RADIUS / DOME_RADIUS)
	var profile_angle = maximum_angle * amount
	var normalized_height = sin(profile_angle) / sin(maximum_angle)
	return Vector2(DOME_RADIUS * cos(profile_angle), BUILDING_HEIGHT + DOME_HEIGHT * normalized_height)


func dome_point(radius: float, height: float, angle: float) -> Vector3:
	return Vector3(cos(angle) * radius, height, sin(angle) * radius)


func _add_surface_triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3):
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)


func _add_surface_quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3):
	_add_surface_triangle(surface, a, b, c)
	_add_surface_triangle(surface, a, c, d)


func build_mission_characters():
	guard = create_mission_npc("SecurityGuard", GUARD_POSITION, Color("233d59"))
	guard.rotation_degrees.y = 180
	recipient = create_mission_npc("BundestagRecipient", RECIPIENT_POSITION, Color("55433f"))
	add_visual_box(recipient, "Credential", Vector3(0.22, 1.18, -0.24), Vector3(0.22, 0.30, 0.03), Color("f0eee2"))


func create_mission_npc(node_name: String, position: Vector3, vest_color: Color) -> StaticBody:
	var npc = StaticBody.new()
	npc.name = node_name
	npc.translation = position
	var human = HUMAN_SCENE.instance()
	human.name = "HumanModel"
	npc.add_child(human)
	add_visual_box(npc, "Jacket", Vector3(0, 1.05, 0), Vector3(0.72, 0.62, 0.42), vest_color)
	var collision = CollisionShape.new()
	var shape = CapsuleShape.new()
	shape.radius = 0.42
	shape.height = 1.2
	collision.shape = shape
	collision.translation.y = 1.0
	npc.add_child(collision)
	add_child(npc)
	return npc


func build_push_crate():
	push_crate = RigidBody.new()
	push_crate.name = "MissionPuzzleCrate"
	push_crate.translation = CRATE_START
	push_crate.mass = 16.0
	# The project uses zero world damping so vehicle drag can be calibrated in
	# physical units. Preserve the crate's former effective 4.6 damping here.
	push_crate.linear_damp = 4.6
	push_crate.angular_damp = 8.0
	push_crate.axis_lock_linear_y = true
	push_crate.axis_lock_angular_x = true
	push_crate.axis_lock_angular_y = true
	push_crate.axis_lock_angular_z = true
	push_crate.continuous_cd = true
	add_child(push_crate)
	var crate_mesh = MeshInstance.new()
	var mesh = CubeMesh.new()
	mesh.size = Vector3(1.8, 1.6, 1.8)
	mesh.material = make_material(Color("765335"))
	crate_mesh.mesh = mesh
	push_crate.add_child(crate_mesh)
	for band_x in [-0.62, 0.62]:
		add_visual_box(push_crate, "MetalBand", Vector3(band_x, 0, -0.91), Vector3(0.12, 1.65, 0.05), Color("34383a"))
	var collision = CollisionShape.new()
	var shape = BoxShape.new()
	shape.extents = Vector3(0.9, 0.8, 0.9)
	collision.shape = shape
	push_crate.add_child(collision)
	# Scrape marks draw attention to the otherwise inconspicuous service wall.
	for mark_z in [-42.0, -40.0, -38.0]:
		add_visual_box(self, "ScrapeMark", Vector3(-207.0, 0.025, mark_z), Vector3(5.0, 0.035, 0.12), Color("77746c"))


func build_waypoint():
	waypoint = Spatial.new()
	waypoint.name = "MissionWaypoint"
	add_child(waypoint)
	waypoint_ring = add_visual_cylinder(waypoint, "WaypointBeam", Vector3(0, 1.8, 0), 1.15, 3.6, Color("f4d35e"), true)
	var marker_material = waypoint_ring.mesh.material as SpatialMaterial
	marker_material.flags_transparent = true
	marker_material.albedo_color.a = 0.58
	var light = OmniLight.new()
	light.light_color = Color("f4d35e")
	light.light_energy = 1.4
	light.omni_range = 9.0
	light.translation.y = 1.5
	waypoint.add_child(light)


func build_briefcase():
	briefcase_model = Spatial.new()
	briefcase_model.name = "MissionBriefcase"
	briefcase_model.translation = Vector3(-0.40, -0.36, -0.72)
	briefcase_model.rotation_degrees = Vector3(-8, 12, -5)
	game.camera.add_child(briefcase_model)
	add_visual_box(briefcase_model, "Case", Vector3.ZERO, Vector3(0.48, 0.34, 0.16), Color("202326"))
	add_visual_box(briefcase_model, "MetalEdge", Vector3(0, 0.16, -0.085), Vector3(0.48, 0.035, 0.025), Color("b5a76c"))
	add_visual_box(briefcase_model, "Handle", Vector3(0, 0.25, 0), Vector3(0.20, 0.06, 0.06), Color("17191b"))


func build_mission_ui():
	mission_layer = CanvasLayer.new()
	mission_layer.layer = 5
	add_child(mission_layer)
	var objective_panel = ColorRect.new()
	objective_panel.rect_position = Vector2(340, 16)
	objective_panel.rect_size = Vector2(600, 106)
	objective_panel.color = Color(0.025, 0.035, 0.05, 0.84)
	mission_layer.add_child(objective_panel)
	var title = Label.new()
	title.rect_position = Vector2(18, 10)
	title.rect_size = Vector2(564, 24)
	title.text = "MISSION 1  •  SONDERZUSTELLUNG"
	title.align = Label.ALIGN_CENTER
	title.add_color_override("font_color", Color("f4d35e"))
	objective_panel.add_child(title)
	objective_label = Label.new()
	objective_label.rect_position = Vector2(24, 38)
	objective_label.rect_size = Vector2(552, 42)
	objective_label.align = Label.ALIGN_CENTER
	objective_label.autowrap = true
	objective_panel.add_child(objective_label)
	distance_label = Label.new()
	distance_label.rect_position = Vector2(18, 80)
	distance_label.rect_size = Vector2(564, 20)
	distance_label.align = Label.ALIGN_CENTER
	distance_label.add_color_override("font_color", Color("b8d8f0"))
	objective_panel.add_child(distance_label)

	inventory_label = Label.new()
	inventory_label.rect_position = Vector2(18, 63)
	inventory_label.rect_size = Vector2(240, 28)
	inventory_label.text = "▣ AKTENKOFFER: GESICHERT"
	inventory_label.add_color_override("font_color", Color("f4d35e"))
	mission_layer.add_child(inventory_label)

	notice_label = Label.new()
	notice_label.rect_position = Vector2(340, 142)
	notice_label.rect_size = Vector2(600, 42)
	notice_label.align = Label.ALIGN_CENTER
	notice_label.add_color_override("font_color", Color("f4d35e"))
	mission_layer.add_child(notice_label)

	completion_panel = ColorRect.new()
	completion_panel.rect_position = Vector2(330, 230)
	completion_panel.rect_size = Vector2(620, 245)
	completion_panel.color = Color(0.02, 0.035, 0.04, 0.94)
	completion_panel.visible = false
	mission_layer.add_child(completion_panel)
	completion_label = Label.new()
	completion_label.rect_position = Vector2(32, 26)
	completion_label.rect_size = Vector2(556, 190)
	completion_label.align = Label.ALIGN_CENTER
	completion_label.valign = Label.VALIGN_CENTER
	completion_panel.add_child(completion_label)


func build_dialogue_ui():
	dialogue_layer = CanvasLayer.new()
	dialogue_layer.layer = 20
	add_child(dialogue_layer)
	dialogue_panel = ColorRect.new()
	dialogue_panel.rect_position = Vector2(170, 340)
	dialogue_panel.rect_size = Vector2(940, 330)
	dialogue_panel.color = Color(0.02, 0.03, 0.045, 0.97)
	dialogue_panel.visible = false
	dialogue_layer.add_child(dialogue_panel)
	var title = Label.new()
	title.rect_position = Vector2(22, 14)
	title.rect_size = Vector2(896, 28)
	title.text = "SICHERHEITSKONTROLLE  •  Freie Eingabe – überzeuge den Wachmann mit deinen Worten"
	title.align = Label.ALIGN_CENTER
	title.add_color_override("font_color", Color("8fc8f2"))
	dialogue_panel.add_child(title)
	dialogue_transcript = RichTextLabel.new()
	dialogue_transcript.rect_position = Vector2(24, 50)
	dialogue_transcript.rect_size = Vector2(892, 190)
	dialogue_transcript.bbcode_enabled = true
	dialogue_transcript.scroll_following = true
	dialogue_panel.add_child(dialogue_transcript)
	dialogue_input = LineEdit.new()
	dialogue_input.rect_position = Vector2(24, 252)
	dialogue_input.rect_size = Vector2(700, 40)
	dialogue_input.max_length = 220
	dialogue_input.placeholder_text = "Was sagst du?"
	dialogue_input.connect("text_entered", self, "_on_dialogue_submitted")
	dialogue_panel.add_child(dialogue_input)
	dialogue_send = Button.new()
	dialogue_send.rect_position = Vector2(736, 252)
	dialogue_send.rect_size = Vector2(84, 40)
	dialogue_send.text = "Senden"
	dialogue_send.connect("pressed", self, "_submit_dialogue_input")
	dialogue_panel.add_child(dialogue_send)
	dialogue_close = Button.new()
	dialogue_close.rect_position = Vector2(832, 252)
	dialogue_close.rect_size = Vector2(84, 40)
	dialogue_close.text = "Zurück"
	dialogue_close.connect("pressed", self, "close_dialogue")
	dialogue_panel.add_child(dialogue_close)
	var hint = Label.new()
	hint.rect_position = Vector2(24, 298)
	hint.rect_size = Vector2(892, 22)
	hint.text = "Enter: senden  •  Esc: Gespräch verlassen  •  Drohungen verschlechtern das Vertrauen"
	hint.align = Label.ALIGN_CENTER
	hint.add_color_override("font_color", Color("a7adb3"))
	dialogue_panel.add_child(hint)


func set_state(next_state: int):
	state = next_state
	distance_label.text = ""
	match state:
		MissionState.ENTER_CAR:
			objective_label.text = "Steig mit dem Aktenkoffer in den goldgelben Golf."
			set_waypoint(game.car.global_transform.origin)
		MissionState.DRIVE_TO_BUNDESTAG:
			objective_label.text = "Fahre ins Regierungsviertel zum Bundestag."
			set_waypoint(PARKING_POSITION)
			show_notice("AKTENKOFFER AN BORD", Color("8ee59b"))
		MissionState.GAIN_ACCESS:
			objective_label.text = "Sprich mit dem Wachmann oder finde einen versteckten Zugang."
			set_waypoint(GUARD_POSITION)
			show_notice("ZIEL ERREICHT – FINDE EINEN WEG HINEIN", Color("f4d35e"))
		MissionState.ENTER_BUILDING:
			objective_label.text = "Betritt den Bundestag und finde den Empfänger."
			set_waypoint(DELIVERY_POSITION)
		MissionState.DELIVER_CASE:
			objective_label.text = "Übergib den Aktenkoffer am Empfang."
			set_waypoint(DELIVERY_POSITION)
		MissionState.COMPLETE:
			objective_label.text = "Mission geschafft: Aktenkoffer übergeben."
			waypoint.visible = false


func set_waypoint(world_position: Vector3):
	if not waypoint:
		return
	waypoint.visible = true
	waypoint.translation = Vector3(world_position.x, 0.08, world_position.z)


func update_mission(delta: float):
	if not game:
		return
	if notice_time > 0.0:
		notice_time -= delta
		if notice_time <= 0.0:
			notice_label.text = ""
	if waypoint and waypoint.visible:
		waypoint.rotate_y(delta * 1.2)
		waypoint_ring.translation.y = 1.8 + sin(float(OS.get_ticks_msec()) * 0.004) * 0.22

	update_briefcase_visibility()
	if state == MissionState.GAIN_ACCESS:
		apply_crate_push()
		check_hidden_passage()

	if state == MissionState.ENTER_CAR:
		set_waypoint(game.car.global_transform.origin)
		if game.in_car:
			set_state(MissionState.DRIVE_TO_BUNDESTAG)
	elif state == MissionState.DRIVE_TO_BUNDESTAG:
		var distance = horizontal_distance(game.car.global_transform.origin, PARKING_POSITION)
		distance_label.text = "Entfernung: %d m" % int(round(distance))
		if game.in_car and distance < 11.0:
			set_state(MissionState.GAIN_ACCESS)
		elif vehicle_failed():
			objective_label.text = "Fahrzeug ausgefallen. Starte Mission 1 neu."
	elif state == MissionState.GAIN_ACCESS:
		if front_door_open or hidden_door_open:
			set_state(MissionState.ENTER_BUILDING)
	elif state == MissionState.ENTER_BUILDING:
		var player_position = game.player.global_transform.origin
		if not game.is_in_vehicle() and (is_player_inside() or player_position.distance_to(DELIVERY_POSITION) < 7.0):
			set_state(MissionState.DELIVER_CASE)


func horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func is_player_inside() -> bool:
	var position = game.player.global_transform.origin
	return (
		not game.is_in_vehicle()
		and position.y > -0.5
		and position.y < BUILDING_HEIGHT - 0.25
		and position.x > BUILDING_CENTER.x - 68.4
		and position.x < BUILDING_CENTER.x + 68.4
		and position.z > BUILDING_CENTER.z - 48.4
		and position.z < BUILDING_CENTER.z + 48.4
	)


func update_briefcase_visibility():
	briefcase_model.visible = has_briefcase and not game.is_in_vehicle() and game.equipped_weapon == "" and not is_overlay_open()
	inventory_label.text = "▣ AKTENKOFFER: GESICHERT" if has_briefcase else "▢ AKTENKOFFER: ÜBERGEBEN"


func apply_crate_push():
	if not is_instance_valid(push_crate) or game.is_in_vehicle() or is_overlay_open():
		return
	var player_position = game.player.global_transform.origin
	var crate_position = push_crate.global_transform.origin
	var to_crate = crate_position - player_position
	to_crate.y = 0
	if to_crate.length() > 2.3 or to_crate.length() < 0.1:
		return
	var input = game.input_vector()
	if input.length() < 0.1:
		return
	var push_direction = game.player.global_transform.basis.x * input.x + game.player.global_transform.basis.z * input.y
	push_direction.y = 0
	if push_direction.length() > 0.1 and push_direction.normalized().dot(to_crate.normalized()) > 0.35:
		push_crate.sleeping = false
		push_crate.add_central_force(push_direction.normalized() * 52.0)


func check_hidden_passage():
	if state != MissionState.GAIN_ACCESS or hidden_door_open or not is_instance_valid(push_crate):
		return
	if horizontal_distance(push_crate.global_transform.origin, CRATE_START) > 2.1:
		hidden_door_open = true
		if access_route == "":
			access_route = "Geheimgang"
		raise_door(hidden_door)
		show_notice("GEHEIMGANG FREIGELEGT", Color("8ee59b"))


func raise_door(door: StaticBody):
	if not is_instance_valid(door):
		return
	var tween = Tween.new()
	door.add_child(tween)
	tween.interpolate_property(door, "translation:y", door.translation.y, door.translation.y + 5.5, 0.85, Tween.TRANS_QUAD, Tween.EASE_IN_OUT)
	tween.start()


func open_front_door():
	if state != MissionState.GAIN_ACCESS or front_door_open:
		return
	front_door_open = true
	if access_route == "":
		access_route = "Haupteingang"
	raise_door(front_door)
	show_notice("ZUTRITT GENEHMIGT", Color("8ee59b"))


func handle_interact() -> bool:
	if is_overlay_open():
		return true
	if game.is_in_vehicle():
		return false
	var player_position = game.player.global_transform.origin
	if state == MissionState.DELIVER_CASE and player_position.distance_to(DELIVERY_POSITION) < 3.4:
		complete_mission()
		return true
	if state == MissionState.GAIN_ACCESS and player_position.distance_to(GUARD_POSITION) < 3.5:
		open_dialogue()
		return true
	return false


func get_context_prompt() -> String:
	if not game or is_overlay_open():
		return ""
	var player_position = game.player.global_transform.origin
	if game.in_helicopter:
		return ""
	if vehicle_failed():
		return "[R] Fahrzeug ausgefallen – Mission neu starten"
	if state == MissionState.DELIVER_CASE and not game.is_in_vehicle() and player_position.distance_to(DELIVERY_POSITION) < 3.4:
		return "[E] Aktenkoffer übergeben"
	if state == MissionState.GAIN_ACCESS and not game.is_in_vehicle() and player_position.distance_to(GUARD_POSITION) < 3.5:
		return "[E] Frei mit dem Wachmann sprechen"
	if state == MissionState.GAIN_ACCESS and not game.is_in_vehicle() and is_instance_valid(push_crate) and player_position.distance_to(push_crate.global_transform.origin) < 3.1 and not hidden_door_open:
		return "Kiste mit WASD verschieben – dahinter sind Schleifspuren"
	if state == MissionState.GAIN_ACCESS and game.in_car and horizontal_distance(game.car.global_transform.origin, PARKING_POSITION) < 16.0:
		return "[E] Aussteigen – Eingang untersuchen"
	if state == MissionState.COMPLETE:
		return "[R] Mission neu starten"
	return ""


func open_dialogue():
	if state != MissionState.GAIN_ACCESS or game.is_in_vehicle() or game.player.global_transform.origin.distance_to(GUARD_POSITION) >= 3.5:
		return
	if dialogue_history == "":
		dialogue_history = "[color=#8fc8f2]Wachmann:[/color] Halt. Ohne nachvollziehbaren Auftrag kommt hier niemand mit einem verschlossenen Koffer hinein.\n"
	dialogue_transcript.bbcode_text = dialogue_history
	dialogue_input.text = ""
	dialogue_input.editable = true
	dialogue_send.disabled = false
	dialogue_close.text = "Zurück"
	dialogue_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	dialogue_input.grab_focus()


func _submit_dialogue_input():
	_on_dialogue_submitted(dialogue_input.text)


func _on_dialogue_submitted(text: String):
	if state != MissionState.GAIN_ACCESS or not is_overlay_open() or horizontal_distance(game.player.global_transform.origin, GUARD_POSITION) >= 3.8:
		return
	var clean_text = text.strip_edges()
	if clean_text == "":
		return
	dialogue_input.text = ""
	var safe_text = clean_text.replace("[", "(").replace("]", ")")
	var result = evaluator.evaluate(clean_text)
	dialogue_history += "\n[color=#f4d35e]Du:[/color] %s\n[color=#8fc8f2]Wachmann:[/color] %s\n" % [safe_text, str(result.reply)]
	dialogue_transcript.bbcode_text = dialogue_history
	if bool(result.success):
		open_front_door()
		dialogue_input.editable = false
		dialogue_send.disabled = true
		dialogue_close.text = "Weiter"


func close_dialogue():
	if not dialogue_panel or not dialogue_panel.visible:
		return
	dialogue_panel.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func is_overlay_open() -> bool:
	return dialogue_panel != null and dialogue_panel.visible


func controls_locked() -> bool:
	return is_overlay_open()


func complete_mission():
	if mission_completed or not has_briefcase:
		return
	mission_completed = true
	has_briefcase = false
	set_state(MissionState.COMPLETE)
	var elapsed = max(0, int((OS.get_ticks_msec() - started_msec) / 1000))
	var minutes = elapsed / 60
	var seconds = elapsed % 60
	var route_name = access_route if access_route != "" else "Bundestag-Empfang"
	completion_label.text = "MISSION GESCHAFFT\n\nAktenkoffer erfolgreich übergeben\nZugang: %s\nZeit: %02d:%02d\n\n[R] Mission neu starten" % [route_name, minutes, seconds]
	completion_label.add_color_override("font_color", Color("8ee59b"))
	completion_panel.visible = true
	show_notice("AKTENKOFFER ÜBERGEBEN", Color("8ee59b"))


func show_notice(text: String, color: Color):
	if not notice_label:
		return
	notice_label.text = text
	notice_label.add_color_override("font_color", color)
	notice_time = 3.2


func handle_shortcut(event) -> bool:
	# R is the EC135's right pedal. Never treat it as a mission restart while
	# the player is flying, even if the completion/failure panel is still open.
	if game != null and game.in_helicopter:
		return false
	if (state == MissionState.COMPLETE or vehicle_failed()) and event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_R:
		get_tree().reload_current_scene()
		return true
	return false


func vehicle_failed() -> bool:
	return game != null and state <= MissionState.DRIVE_TO_BUNDESTAG and (game.car_health <= 0 or game.car_fuel <= 0.0)
