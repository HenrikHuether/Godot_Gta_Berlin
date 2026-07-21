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

const BUILDING_CENTER = Vector3(-218.0, 0.0, -52.0)
const PARKING_POSITION = Vector3(-218.0, 0.1, -84.0)
const GUARD_POSITION = Vector3(-213.5, 0.05, -74.0)
const RECIPIENT_POSITION = Vector3(-218.0, 0.05, -39.5)
const DELIVERY_POSITION = Vector3(-218.0, 0.2, -44.5)
const CRATE_START = Vector3(-245.0, 0.80, -52.0)

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


func build_bundestag():
	var building = Spatial.new()
	building.name = "BundestagMissionBuilding"
	building.translation = BUILDING_CENTER
	add_child(building)

	add_static_box(building, "InteriorFloor", Vector3(0, 0.12, 0), Vector3(46, 0.24, 34), Color("b7b1a5"))
	add_static_box(building, "FrontWallLeft", Vector3(-12.75, 3.6, -17), Vector3(20.5, 7.2, 0.65), Color("d7c7a7"))
	add_static_box(building, "FrontWallRight", Vector3(12.75, 3.6, -17), Vector3(20.5, 7.2, 0.65), Color("d7c7a7"))
	add_static_box(building, "RearWall", Vector3(0, 3.6, 17), Vector3(46, 7.2, 0.65), Color("cbb995"))
	add_static_box(building, "EastWall", Vector3(23, 3.6, 0), Vector3(0.65, 7.2, 34), Color("d2c19d"))
	add_static_box(building, "WestWallFront", Vector3(-23, 3.6, -9.75), Vector3(0.65, 7.2, 14.5), Color("d2c19d"))
	add_static_box(building, "WestWallRear", Vector3(-23, 3.6, 9.75), Vector3(0.65, 7.2, 14.5), Color("d2c19d"))
	add_visual_box(building, "Roof", Vector3(0, 7.25, 0), Vector3(47, 0.35, 35), Color("4e5558"))

	# The central glass dome and flag make the destination readable from the road.
	add_visual_cylinder(building, "DomeBase", Vector3(0, 7.65, 2.5), 5.2, 0.7, Color("59666b"))
	var dome = add_visual_sphere(building, "GlassDome", Vector3(0, 9.2, 2.5), 4.1, Color(0.30, 0.52, 0.62, 0.82))
	var dome_material = dome.mesh.material as SpatialMaterial
	dome_material.flags_transparent = true
	add_visual_cylinder(building, "FlagPole", Vector3(0, 14.0, 2.5), 0.10, 6.0, Color("30363a"))
	add_visual_box(building, "GermanFlagBlack", Vector3(1.5, 15.8, 2.5), Vector3(3.0, 0.35, 0.06), Color("171717"))
	add_visual_box(building, "GermanFlagRed", Vector3(1.5, 15.45, 2.5), Vector3(3.0, 0.35, 0.06), Color("c52b35"))
	add_visual_box(building, "GermanFlagGold", Vector3(1.5, 15.10, 2.5), Vector3(3.0, 0.35, 0.06), Color("e4b43c"))

	for column_x in [-10.0, -6.5, 6.5, 10.0]:
		add_visual_cylinder(building, "FacadeColumn", Vector3(column_x, 3.15, -18.0), 0.48, 6.3, Color("e4d8c0"))
	for stair_index in range(3):
		var stair_width = 14.0 + float(stair_index) * 2.0
		add_static_box(building, "EntranceStep%d" % stair_index, Vector3(0, 0.10 + stair_index * 0.10, -19.2 + stair_index * 0.65), Vector3(stair_width, 0.20 + stair_index * 0.20, 1.3), Color("aaa398"))

	front_door = add_static_box(building, "SecureMainDoor", Vector3(0, 2.5, -17.15), Vector3(4.8, 5.0, 0.45), Color("264654"))
	hidden_door = add_static_box(building, "ConcealedServiceDoor", Vector3(-23.15, 2.25, 0), Vector3(0.45, 4.5, 4.8), Color("7b756c"))
	add_visual_box(building, "ServiceDoorSeam", Vector3(-23.40, 2.25, 0), Vector3(0.03, 4.65, 4.95), Color("3b3a38"))

	# Interior delivery desk, archive stacks, lighting, and the short service corridor.
	add_static_box(building, "DeliveryDesk", Vector3(0, 0.75, 9.5), Vector3(6.5, 1.5, 1.4), Color("584331"))
	add_visual_box(building, "DeskGlass", Vector3(0, 1.7, 9.75), Vector3(6.0, 0.75, 0.08), Color(0.28, 0.55, 0.65, 0.62))
	for shelf_z in [4.0, 8.0, 12.0]:
		add_static_box(building, "ArchiveShelf", Vector3(-17.5, 1.25, shelf_z), Vector3(2.0, 2.5, 2.8), Color("4c3b2d"))
	add_visual_box(building, "ServiceTunnelCeiling", Vector3(-20.0, 4.6, 0), Vector3(6.0, 0.25, 5.0), Color("4d5050"))
	for tunnel_z in [-2.35, 2.35]:
		add_visual_box(building, "TunnelRail", Vector3(-20.0, 2.2, tunnel_z), Vector3(6.0, 0.18, 0.18), Color("8f8d82"))

	var interior_light = OmniLight.new()
	interior_light.name = "InteriorLight"
	interior_light.translation = Vector3(0, 5.8, 3.0)
	interior_light.light_color = Color("fff1cf")
	interior_light.light_energy = 1.3
	interior_light.omni_range = 30.0
	building.add_child(interior_light)


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
	push_crate.linear_damp = 4.5
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
	for mark_z in [-54.0, -52.0, -50.0]:
		add_visual_box(self, "ScrapeMark", Vector3(-244.0, 0.025, mark_z), Vector3(5.0, 0.035, 0.12), Color("77746c"))


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
			objective_label.text = "Steig mit dem Aktenkoffer in das rote Auto."
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
		if is_player_inside() or horizontal_distance(game.player.global_transform.origin, DELIVERY_POSITION) < 7.0:
			set_state(MissionState.DELIVER_CASE)


func horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func is_player_inside() -> bool:
	var position = game.player.global_transform.origin
	return position.x > BUILDING_CENTER.x - 22.4 and position.x < BUILDING_CENTER.x + 22.4 and position.z > BUILDING_CENTER.z - 16.6 and position.z < BUILDING_CENTER.z + 16.6


func update_briefcase_visibility():
	briefcase_model.visible = has_briefcase and not game.in_car and game.equipped_weapon == "" and not is_overlay_open()
	inventory_label.text = "▣ AKTENKOFFER: GESICHERT" if has_briefcase else "▢ AKTENKOFFER: ÜBERGEBEN"


func apply_crate_push():
	if not is_instance_valid(push_crate) or game.in_car or is_overlay_open():
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
	if game.in_car:
		return false
	var player_position = game.player.global_transform.origin
	if state == MissionState.DELIVER_CASE and horizontal_distance(player_position, DELIVERY_POSITION) < 3.4:
		complete_mission()
		return true
	if state == MissionState.GAIN_ACCESS and horizontal_distance(player_position, GUARD_POSITION) < 3.5:
		open_dialogue()
		return true
	return false


func get_context_prompt() -> String:
	if not game or is_overlay_open():
		return ""
	var player_position = game.player.global_transform.origin
	if vehicle_failed():
		return "[R] Fahrzeug ausgefallen – Mission neu starten"
	if state == MissionState.DELIVER_CASE and not game.in_car and horizontal_distance(player_position, DELIVERY_POSITION) < 3.4:
		return "[E] Aktenkoffer übergeben"
	if state == MissionState.GAIN_ACCESS and not game.in_car and horizontal_distance(player_position, GUARD_POSITION) < 3.5:
		return "[E] Frei mit dem Wachmann sprechen"
	if state == MissionState.GAIN_ACCESS and not game.in_car and is_instance_valid(push_crate) and horizontal_distance(player_position, push_crate.global_transform.origin) < 3.1 and not hidden_door_open:
		return "Kiste mit WASD verschieben – dahinter sind Schleifspuren"
	if state == MissionState.GAIN_ACCESS and game.in_car and horizontal_distance(game.car.global_transform.origin, PARKING_POSITION) < 16.0:
		return "[E] Aussteigen – Eingang untersuchen"
	if state == MissionState.COMPLETE:
		return "[R] Mission neu starten"
	return ""


func open_dialogue():
	if state != MissionState.GAIN_ACCESS or game.in_car or horizontal_distance(game.player.global_transform.origin, GUARD_POSITION) >= 3.5:
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
	if (state == MissionState.COMPLETE or vehicle_failed()) and event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_R:
		get_tree().reload_current_scene()
		return true
	return false


func vehicle_failed() -> bool:
	return game != null and state <= MissionState.DRIVE_TO_BUNDESTAG and (game.car_health <= 0 or game.car_fuel <= 0.0)
