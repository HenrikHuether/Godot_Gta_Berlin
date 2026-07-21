extends Spatial

const BERLIN_MAP_SCENE = preload("res://scenes/BerlinMap.tscn")
const HUMAN_SCENE = preload("res://Assets/HumanV2.glb")
const MISSION_ONE_SCRIPT = preload("res://scripts/mission_one.gd")
const MAP_EXPANSION_SCRIPT = preload("res://scripts/map_expansion.gd")
const WALK_SPEED = 8.0
const DRIVE_SPEED = 22.0
const GRAVITY = 24.0
const POLICE_SPEED = 16.0
const OFFICER_SPEED = 5.2
const FIRE_ENGINE_SPEED = 13.0
const DEATH_FALL_DURATION = 0.90
const DEATH_FADE_DELAY = 0.15
const DEATH_FADE_OUT_DURATION = 1.05
const DEATH_BLACK_HOLD_DURATION = 0.35
const DEATH_FADE_IN_DURATION = 0.65

enum PlayerDeathPhase {
	ALIVE,
	FALLING,
	BLACK_HOLD,
	FADE_IN
}

var player: KinematicBody
var player_collider: CollisionShape
var camera: Camera
var car: KinematicBody
var car_body: MeshInstance
var weapon_pivot: Spatial
var pistol_model: Spatial
var bazooka_model: Spatial
var rifle_model: Spatial
var velocity = Vector3.ZERO
var car_speed = 0.0
var look_x = 0.0
var in_car = false
var equipped_weapon = ""
var bazooka_ready = true
var player_health = 100
var prompt: Label
var status: Label
var crosshair: Label
var alert_label: Label
var npcs = []
var emergency_vehicles = []
var police_officers = []
var destroyed_buildings = []
var police_dispatch_count = 0
var mission_one
var map_expansion
var car_fuel = 38.0
var car_health = 100
var car_damage_cooldown = 0.0
var wanted_level = 0
var weapon_cooldown = 0.0
var reload_remaining = 0.0
var reloading_weapon = ""
var rifle_fire_mode = "auto"
var weapon_kick = 0.0
var rifle_bloom = 0.0
var ammo_in_mag = {"pistol": 15, "rifle": 30, "bazooka": 1}
var ammo_reserve = {"pistol": 45, "rifle": 120, "bazooka": 3}
var magazine_capacity = {"pistol": 15, "rifle": 30, "bazooka": 1}
var damage_overlay: ColorRect
var damage_flash_time = 0.0
var death_fade_layer: CanvasLayer
var death_fade_overlay: ColorRect
var player_dying = false
var player_death_phase = PlayerDeathPhase.ALIVE
var death_elapsed = 0.0
var death_start_position = Vector3.ZERO
var death_fall_position = Vector3.ZERO
var death_start_rotation = Vector3.ZERO
var death_fall_rotation = Vector3.ZERO
var death_start_camera_rotation = Vector3.ZERO
var sound_streams = {}
var vehicle_fires = []
var destroyed_vehicles = []

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	build_world()
	map_expansion = MAP_EXPANSION_SCRIPT.new()
	map_expansion.setup(self)
	build_player()
	build_car()
	build_npcs()
	build_ui()
	build_audio()
	tag_destructible_buildings(get_node("BerlinMap"))
	tag_destructible_buildings(map_expansion)
	mission_one = MISSION_ONE_SCRIPT.new()
	mission_one.name = "MissionOne"
	add_child(mission_one)
	mission_one.setup(self)
	update_status()

func build_audio():
	# Procedural samples keep the prototype self-contained while still providing
	# distinct gunshots, launch, explosion and looping vehicle-fire sounds.
	sound_streams["pistol"] = create_sound_sample("pistol", 0.16)
	sound_streams["rifle"] = create_sound_sample("rifle", 0.11)
	sound_streams["police_pistol"] = create_sound_sample("police_pistol", 0.14)
	sound_streams["rocket"] = create_sound_sample("rocket", 0.34)
	sound_streams["explosion"] = create_sound_sample("explosion", 0.95)
	sound_streams["fire"] = create_sound_sample("fire", 1.20, true)

func create_sound_sample(kind: String, duration: float, looping := false) -> AudioStreamSample:
	var mix_rate = 22050
	var frame_count = int(duration * mix_rate)
	var bytes = PoolByteArray()
	bytes.resize(frame_count * 2)
	for frame in range(frame_count):
		var time = float(frame) / float(mix_rate)
		var progress = float(frame) / float(max(1, frame_count - 1))
		var pseudo = sin(float(frame) * 12.9898 + sin(float(frame) * 0.017) * 31.7) * 43758.5453
		var noise = (pseudo - floor(pseudo)) * 2.0 - 1.0
		var wave = 0.0
		if kind == "pistol":
			wave = (noise * 0.72 + sin(time * PI * 2.0 * 92.0) * 0.42) * pow(1.0 - progress, 3.2)
		elif kind == "rifle":
			wave = (noise * 0.78 + sin(time * PI * 2.0 * 138.0) * 0.34) * pow(1.0 - progress, 4.0)
		elif kind == "police_pistol":
			wave = (noise * 0.64 + sin(time * PI * 2.0 * 105.0) * 0.38) * pow(1.0 - progress, 3.5)
		elif kind == "rocket":
			wave = (noise * 0.46 + sin(time * PI * 2.0 * (180.0 - progress * 125.0)) * 0.52) * (1.0 - progress)
		elif kind == "explosion":
			wave = (noise * 0.62 + sin(time * PI * 2.0 * 43.0) * 0.58 + sin(time * PI * 2.0 * 67.0) * 0.24) * pow(1.0 - progress, 1.7)
		else:
			var crackle = 1.0 if noise > 0.72 else noise * 0.28
			var loop_fade = min(1.0, min(progress * 18.0, (1.0 - progress) * 18.0))
			wave = (crackle * 0.55 + sin(time * PI * 2.0 * 74.0) * 0.10) * loop_fade
		var value = int(clamp(wave, -1.0, 1.0) * 32767.0)
		bytes[frame * 2] = value & 0xff
		bytes[frame * 2 + 1] = (value >> 8) & 0xff
	var sample = AudioStreamSample.new()
	sample.format = AudioStreamSample.FORMAT_16_BITS
	sample.mix_rate = mix_rate
	sample.stereo = false
	sample.data = bytes
	if looping:
		sample.loop_mode = AudioStreamSample.LOOP_FORWARD
		sample.loop_begin = 0
		sample.loop_end = frame_count
	return sample

func play_sound_3d(kind: String, position: Vector3, volume_db := 0.0, looping := false):
	if not sound_streams.has(kind):
		return null
	var audio = AudioStreamPlayer3D.new()
	audio.name = "Sound_%s" % kind
	audio.stream = sound_streams[kind]
	audio.unit_db = volume_db
	audio.max_distance = 180.0 if kind == "explosion" else 95.0
	add_child(audio)
	audio.global_transform = Transform(Basis(), position)
	audio.play()
	if not looping:
		get_tree().create_timer(1.5).connect("timeout", audio, "queue_free")
	return audio

func material(color: Color) -> SpatialMaterial:
	var mat = SpatialMaterial.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat

func textured_car_paint() -> SpatialMaterial:
	# Small procedural paint texture: dark red squares give the body visible panel detail.
	var image = Image.new()
	image.create(64, 64, false, Image.FORMAT_RGBA8)
	image.lock()
	for y in range(64):
		for x in range(64):
			var panel = (x / 16 + y / 16) % 2
			var edge = x % 16 < 2 or y % 16 < 2
			var color = Color("8e1720") if panel == 0 else Color("bd2932")
			if edge:
				color = Color("5b1015")
			image.set_pixel(x, y, color)
	image.unlock()
	var texture = ImageTexture.new()
	texture.create_from_image(image, Texture.FLAG_REPEAT | Texture.FLAG_MIPMAPS)
	var mat = SpatialMaterial.new()
	mat.albedo_texture = texture
	mat.roughness = 0.35
	mat.metallic = 0.25
	return mat

func add_box(parent: Node, name: String, pos: Vector3, size: Vector3, color: Color, collision := true):
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = name
	var mesh = CubeMesh.new()
	mesh.size = size
	mesh.material = material(color)
	mesh_instance.mesh = mesh
	mesh_instance.translation = pos
	parent.add_child(mesh_instance)
	if collision:
		var body = StaticBody.new()
		var shape = CollisionShape.new()
		var box = BoxShape.new()
		box.extents = size * 0.5
		shape.shape = box
		body.add_child(shape)
		mesh_instance.add_child(body)
	return mesh_instance

func add_sphere(parent: Node, name: String, pos: Vector3, radius: float, color: Color):
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = name
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh.material = material(color)
	mesh_instance.mesh = mesh
	mesh_instance.translation = pos
	parent.add_child(mesh_instance)
	return mesh_instance

func add_cylinder(parent: Node, name: String, pos: Vector3, radius: float, height: float, color: Color, rotation := Vector3.ZERO):
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = name
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.material = material(color)
	mesh_instance.mesh = mesh
	mesh_instance.translation = pos
	mesh_instance.rotation_degrees = rotation
	parent.add_child(mesh_instance)
	return mesh_instance

func build_world():
	var sun = DirectionalLight.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var berlin_map = get_node_or_null("BerlinMap")
	if not berlin_map:
		berlin_map = BERLIN_MAP_SCENE.instance()
		berlin_map.name = "BerlinMap"
		add_child(berlin_map)

func build_player():
	player = KinematicBody.new()
	player.name = "Player"
	player.translation = Vector3(3, 8, 8)
	player_collider = CollisionShape.new()
	player_collider.name = "CollisionShape"
	var capsule = CapsuleShape.new()
	capsule.radius = 0.45
	capsule.height = 1.70
	player_collider.shape = capsule
	player.add_child(player_collider)
	camera = Camera.new()
	camera.translation = Vector3(0, 0.65, 0)
	camera.far = 10000.0
	camera.current = true
	player.add_child(camera)
	weapon_pivot = Spatial.new()
	weapon_pivot.name = "WeaponPivot"
	camera.add_child(weapon_pivot)
	build_pistol()
	build_bazooka()
	build_rifle()
	add_child(player)

func build_pistol():
	pistol_model = Spatial.new()
	pistol_model.name = "Pistol"
	pistol_model.translation = Vector3(0.34, -0.29, -0.64)
	pistol_model.rotation_degrees = Vector3(-4, -4, 0)
	# Detailed service pistol: moving slide, frame rails, ejection port, sights and controls.
	add_box(pistol_model, "Slide", Vector3(0, 0.01, -0.15), Vector3(0.17, 0.15, 0.58), Color("20242a"), false)
	add_box(pistol_model, "Frame", Vector3(0, -0.10, -0.05), Vector3(0.15, 0.10, 0.38), Color("343941"), false)
	add_box(pistol_model, "EjectionPort", Vector3(0.087, 0.045, -0.10), Vector3(0.015, 0.065, 0.15), Color("090a0c"), false)
	add_box(pistol_model, "MagazineBase", Vector3(0, -0.48, 0.09), Vector3(0.17, 0.055, 0.23), Color("111317"), false)
	var grip = add_box(pistol_model, "Grip", Vector3(0, -0.29, 0.08), Vector3(0.15, 0.38, 0.21), Color("171a1e"), false)
	grip.rotation_degrees.x = -11
	add_cylinder(pistol_model, "Barrel", Vector3(0, 0.0, -0.49), 0.043, 0.13, Color("090a0c"), Vector3(90, 0, 0))
	add_box(pistol_model, "FrontSight", Vector3(0, 0.105, -0.39), Vector3(0.032, 0.045, 0.065), Color("d7d8d2"), false)
	add_box(pistol_model, "RearSightLeft", Vector3(-0.055, 0.105, 0.07), Vector3(0.035, 0.045, 0.06), Color("d7d8d2"), false)
	add_box(pistol_model, "RearSightRight", Vector3(0.055, 0.105, 0.07), Vector3(0.035, 0.045, 0.06), Color("d7d8d2"), false)
	add_box(pistol_model, "Trigger", Vector3(0, -0.17, -0.12), Vector3(0.035, 0.13, 0.035), Color("0d0f12"), false).rotation_degrees.x = -18
	add_box(pistol_model, "TriggerGuardFront", Vector3(0, -0.19, -0.23), Vector3(0.13, 0.035, 0.035), Color("30353b"), false)
	add_box(pistol_model, "TriggerGuardBottom", Vector3(0, -0.25, -0.11), Vector3(0.13, 0.035, 0.25), Color("30353b"), false)
	var flash = add_sphere(pistol_model, "MuzzleFlash", Vector3(0, 0, -0.58), 0.11, Color("ffdf62"))
	flash.scale = Vector3(0.65, 0.65, 1.8)
	flash.visible = false
	pistol_model.visible = false
	weapon_pivot.add_child(pistol_model)

func build_bazooka():
	bazooka_model = Spatial.new()
	bazooka_model.name = "Bazooka"
	bazooka_model.translation = Vector3(0.42, -0.30, -0.78)
	bazooka_model.rotation_degrees = Vector3(-3, -4, 0)
	add_cylinder(bazooka_model, "LauncherTube", Vector3(0, 0, -0.12), 0.125, 1.18, Color("46513b"), Vector3(90, 0, 0))
	add_cylinder(bazooka_model, "RearRing", Vector3(0, 0, 0.43), 0.17, 0.08, Color("242a22"), Vector3(90, 0, 0))
	add_cylinder(bazooka_model, "FrontRing", Vector3(0, 0, -0.68), 0.16, 0.08, Color("242a22"), Vector3(90, 0, 0))
	add_box(bazooka_model, "Grip", Vector3(0, -0.22, 0.12), Vector3(0.12, 0.36, 0.16), Color("20231e"), false)
	add_box(bazooka_model, "ShoulderRest", Vector3(0, -0.13, 0.38), Vector3(0.28, 0.18, 0.26), Color("252a22"), false)
	add_box(bazooka_model, "Optic", Vector3(0.11, 0.17, -0.30), Vector3(0.10, 0.12, 0.22), Color("171a16"), false)
	add_cylinder(bazooka_model, "OpticLens", Vector3(0.11, 0.17, -0.43), 0.035, 0.03, Color("5fb2c5"), Vector3(90, 0, 0))
	add_box(bazooka_model, "SafetyLever", Vector3(-0.09, -0.04, 0.10), Vector3(0.04, 0.08, 0.12), Color("d3a52e"), false)
	var flash = add_sphere(bazooka_model, "MuzzleFlash", Vector3(0, 0, -0.77), 0.17, Color("ffad32"))
	flash.scale = Vector3(0.8, 0.8, 2.1)
	flash.visible = false
	bazooka_model.visible = false
	weapon_pivot.add_child(bazooka_model)

func build_rifle():
	rifle_model = Spatial.new()
	rifle_model.name = "AssaultRifle"
	rifle_model.translation = Vector3(0.39, -0.31, -0.78)
	rifle_model.rotation_degrees = Vector3(-3, -4, 0)
	add_box(rifle_model, "Receiver", Vector3(0, 0, -0.08), Vector3(0.22, 0.20, 0.55), Color("24292d"), false)
	add_box(rifle_model, "UpperReceiver", Vector3(0, 0.12, -0.13), Vector3(0.20, 0.09, 0.50), Color("171b1e"), false)
	add_box(rifle_model, "Handguard", Vector3(0, 0.01, -0.52), Vector3(0.20, 0.18, 0.42), Color("30363a"), false)
	add_box(rifle_model, "TopRail", Vector3(0, 0.18, -0.33), Vector3(0.10, 0.035, 0.90), Color("0c0e10"), false)
	add_cylinder(rifle_model, "Barrel", Vector3(0, 0.02, -0.91), 0.035, 0.62, Color("101315"), Vector3(90, 0, 0))
	add_cylinder(rifle_model, "MuzzleBrake", Vector3(0, 0.02, -1.24), 0.055, 0.12, Color("090b0d"), Vector3(90, 0, 0))
	add_box(rifle_model, "Stock", Vector3(0, -0.01, 0.42), Vector3(0.18, 0.22, 0.48), Color("292e31"), false)
	add_box(rifle_model, "ButtPad", Vector3(0, -0.01, 0.68), Vector3(0.20, 0.27, 0.08), Color("111416"), false)
	var rifle_grip = add_box(rifle_model, "PistolGrip", Vector3(0, -0.25, 0.10), Vector3(0.13, 0.36, 0.17), Color("171a1d"), false)
	rifle_grip.rotation_degrees.x = -13
	var magazine = add_box(rifle_model, "Magazine", Vector3(0, -0.31, -0.12), Vector3(0.15, 0.42, 0.22), Color("181c1f"), false)
	magazine.rotation_degrees.x = 10
	add_box(rifle_model, "EjectionPort", Vector3(0.115, 0.06, -0.05), Vector3(0.02, 0.08, 0.22), Color("08090a"), false)
	add_box(rifle_model, "ChargingHandle", Vector3(0.13, 0.14, 0.10), Vector3(0.09, 0.04, 0.06), Color("0c0e10"), false)
	add_box(rifle_model, "RearSight", Vector3(0, 0.25, 0.08), Vector3(0.08, 0.11, 0.06), Color("111416"), false)
	add_box(rifle_model, "FrontSight", Vector3(0, 0.25, -0.75), Vector3(0.07, 0.14, 0.05), Color("111416"), false)
	var flash = add_sphere(rifle_model, "MuzzleFlash", Vector3(0, 0.02, -1.34), 0.13, Color("ffd15a"))
	flash.scale = Vector3(0.70, 0.70, 2.25)
	flash.visible = false
	rifle_model.visible = false
	weapon_pivot.add_child(rifle_model)

func tag_destructible_buildings(node: Node):
	if node is StaticBody and (node.name.begins_with("Building_") or node.name.begins_with("OuterBuilding_")):
		node.set_meta("destructible_building", true)
	for child in node.get_children():
		tag_destructible_buildings(child)

func build_car():
	car = KinematicBody.new()
	car.name = "Car"
	car.translation = Vector3(2.8, 8, -4)
	register_damageable_vehicle(car, 100, "player_car")
	var paint = textured_car_paint()
	car_body = add_box(car, "Body", Vector3(0, 0, 0.05), Vector3(2.1, 0.65, 3.75), Color("c3282f"), false)
	car_body.mesh.material = paint
	var hood = add_box(car, "Hood", Vector3(0, 0.30, -1.48), Vector3(1.95, 0.22, 1.15), Color("c3282f"), false)
	hood.mesh.material = paint
	var trunk = add_box(car, "Trunk", Vector3(0, 0.28, 1.55), Vector3(1.95, 0.25, 0.72), Color("c3282f"), false)
	trunk.mesh.material = paint
	# Separate pillars and glass make a recognizable cabin instead of one large box.
	add_box(car, "Roof", Vector3(0, 1.12, 0.30), Vector3(1.65, 0.14, 1.72), Color("75151c"), false)
	add_box(car, "Windshield", Vector3(0, 0.83, -0.58), Vector3(1.62, 0.55, 0.08), Color("47788e"), false).rotation_degrees.x = -18
	add_box(car, "RearWindow", Vector3(0, 0.83, 1.18), Vector3(1.62, 0.50, 0.08), Color("47788e"), false).rotation_degrees.x = 18
	for side in [-1, 1]:
		add_box(car, "SideWindow", Vector3(side * 0.86, 0.82, 0.30), Vector3(0.06, 0.48, 1.15), Color("315d71"), false)
		add_box(car, "Mirror", Vector3(side * 1.13, 0.65, -0.55), Vector3(0.26, 0.16, 0.30), Color("5b1015"), false)
		for z in [-1.25, 1.28]:
			add_cylinder(car, "Wheel", Vector3(side * 1.06, -0.22, z), 0.43, 0.28, Color("111215"), Vector3(0, 0, 90))
			add_cylinder(car, "Rim", Vector3(side * 1.22, -0.22, z), 0.22, 0.04, Color("aeb4ba"), Vector3(0, 0, 90))
	add_box(car, "FrontBumper", Vector3(0, -0.05, -2.00), Vector3(2.05, 0.20, 0.16), Color("25282b"), false)
	add_box(car, "RearBumper", Vector3(0, -0.05, 2.00), Vector3(2.05, 0.20, 0.16), Color("25282b"), false)
	for x in [-0.68, 0.68]:
		add_box(car, "Headlight", Vector3(x, 0.18, -2.09), Vector3(0.48, 0.22, 0.08), Color("fff0ad"), false)
		add_box(car, "TailLight", Vector3(x, 0.18, 2.09), Vector3(0.48, 0.22, 0.08), Color("e31e27"), false)
	var collider = CollisionShape.new()
	collider.name = "CollisionShape"
	var shape = BoxShape.new()
	shape.extents = Vector3(1.1, 0.5, 2.1)
	collider.shape = shape
	car.add_child(collider)
	add_child(car)
	call_deferred("place_car_on_ground")

func place_car_on_ground():
	var origin = car.global_transform.origin
	var excluded = [car]
	if player:
		excluded.append(player)
	var hit = get_world().direct_space_state.intersect_ray(
		Vector3(origin.x, 50.0, origin.z),
		Vector3(origin.x, -10.0, origin.z),
		excluded
	)
	if hit:
		car.translation.y = hit.position.y + 0.72

func build_npcs():
	var positions = [Vector3(-5, 8, -8), Vector3(8, 8, 5), Vector3(-8, 8, 12)]
	for i in range(positions.size()):
		var npc = StaticBody.new()
		npc.name = "NPC_%d" % (i + 1)
		npc.translation = positions[i]
		npc.set_meta("health", 100)
		npc.set_meta("role", "civilian")
		var human = HUMAN_SCENE.instance()
		human.name = "HumanV2"
		npc.add_child(human)
		var collider = CollisionShape.new()
		var shape = CapsuleShape.new()
		shape.radius = 0.42
		shape.height = 1.20
		collider.shape = shape
		collider.translation.y = 1.0
		npc.add_child(collider)
		add_child(npc)
		npcs.append(npc)
	call_deferred("place_npcs_on_map")

func place_npcs_on_map():
	var excluded = [player, car]
	for npc in npcs:
		excluded.append(npc)
	for npc in npcs:
		var origin = npc.global_transform.origin
		var hit = get_world().direct_space_state.intersect_ray(Vector3(origin.x, 50, origin.z), Vector3(origin.x, -10, origin.z), excluded)
		if hit:
			npc.translation.y = hit.position.y

func build_ui():
	var layer = CanvasLayer.new()
	add_child(layer)
	status = Label.new()
	status.rect_position = Vector2(18, 16)
	status.text = "ZU FUSS | HP 100 | Waffe: keine"
	status.add_color_override("font_color", Color.white)
	layer.add_child(status)
	prompt = Label.new()
	prompt.anchor_left = 0.5
	prompt.anchor_top = 0.88
	prompt.rect_position = Vector2(-180, 0)
	prompt.rect_size = Vector2(360, 40)
	prompt.align = Label.ALIGN_CENTER
	layer.add_child(prompt)
	crosshair = Label.new()
	crosshair.anchor_left = 0.5
	crosshair.anchor_top = 0.5
	crosshair.rect_position = Vector2(-8, -14)
	crosshair.text = "+"
	crosshair.visible = false
	layer.add_child(crosshair)
	alert_label = Label.new()
	alert_label.anchor_left = 1.0
	alert_label.rect_position = Vector2(-310, 18)
	alert_label.rect_size = Vector2(290, 40)
	alert_label.align = Label.ALIGN_RIGHT
	alert_label.add_color_override("font_color", Color("ff5b4d"))
	layer.add_child(alert_label)
	var help = Label.new()
	help.anchor_top = 1.0
	help.rect_position = Vector2(18, -52)
	help.text = "WASD Bewegen/Fahren  •  E Auto  •  1 Pistole  •  2 Bazooka  •  3 Sturmgewehr  •  R Nachladen  •  B Feuermodus"
	layer.add_child(help)
	damage_overlay = ColorRect.new()
	damage_overlay.anchor_right = 1.0
	damage_overlay.anchor_bottom = 1.0
	damage_overlay.color = Color(0.72, 0.02, 0.01, 0.0)
	damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(damage_overlay)
	death_fade_layer = CanvasLayer.new()
	death_fade_layer.name = "DeathFadeLayer"
	death_fade_layer.layer = 100
	add_child(death_fade_layer)
	death_fade_overlay = ColorRect.new()
	death_fade_overlay.name = "DeathFade"
	death_fade_overlay.anchor_right = 1.0
	death_fade_overlay.anchor_bottom = 1.0
	death_fade_overlay.color = Color(0, 0, 0, 0)
	death_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_fade_overlay.visible = false
	death_fade_layer.add_child(death_fade_overlay)

func _unhandled_input(event):
	if player_dying:
		if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		return
	if mission_one and mission_one.is_overlay_open():
		if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
			mission_one.close_dialogue()
		return
	if mission_one and mission_one.handle_shortcut(event):
		return
	if event is InputEventKey and event.echo:
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		player.rotate_y(deg2rad(-event.relative.x * 0.12))
		look_x = clamp(look_x - event.relative.y * 0.12, -80, 80)
		camera.rotation_degrees.x = look_x
	if event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return
	if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if event.is_action_pressed("interact"):
		if not mission_one or not mission_one.handle_interact():
			toggle_car()
	if event.is_action_pressed("equip") and not in_car:
		set_weapon("" if equipped_weapon == "pistol" else "pistol")
	if event.is_action_pressed("equip_bazooka") and not in_car:
		set_weapon("" if equipped_weapon == "bazooka" else "bazooka")
	if event.is_action_pressed("equip_rifle") and not in_car:
		set_weapon("" if equipped_weapon == "rifle" else "rifle")
	if event.is_action_pressed("reload") and not in_car:
		start_reload()
	if event.is_action_pressed("toggle_fire_mode") and equipped_weapon == "rifle" and not in_car:
		rifle_fire_mode = "semi" if rifle_fire_mode == "auto" else "auto"
		update_status()
	if event.is_action_pressed("shoot") and equipped_weapon != "" and not in_car:
		try_fire_weapon()

func _physics_process(delta):
	car_damage_cooldown = max(0.0, car_damage_cooldown - delta)
	if player_dying:
		update_player_death(delta)
	var controls_locked = player_dying or (mission_one and mission_one.controls_locked())
	update_weapon_system(delta, controls_locked)
	update_damage_feedback(delta)
	if not controls_locked:
		if in_car:
			drive(delta)
		else:
			walk(delta)
	update_emergency_vehicles(delta)
	update_police_officers(delta)
	update_vehicle_fires(delta)
	if mission_one and not player_dying:
		mission_one.update_mission(delta)
	var near_car = player.global_transform.origin.distance_to(car.global_transform.origin) < 3.5
	var mission_prompt = mission_one.get_context_prompt() if mission_one else ""
	if player_dying:
		prompt.text = ""
	elif mission_prompt != "":
		prompt.text = mission_prompt
	else:
		if near_car and not in_car and car.has_meta("destroyed") and bool(car.get_meta("destroyed")):
			prompt.text = "FAHRZEUG ZERSTÖRT"
		else:
			prompt.text = "[E] Einsteigen" if near_car and not in_car else ("[E] Aussteigen" if in_car else "")

func input_vector() -> Vector2:
	return Vector2(Input.get_action_strength("move_right") - Input.get_action_strength("move_left"), Input.get_action_strength("move_back") - Input.get_action_strength("move_forward")).normalized()

func walk(delta):
	var input = input_vector()
	var direction = (player.global_transform.basis.x * input.x + player.global_transform.basis.z * input.y)
	velocity.x = direction.x * WALK_SPEED
	velocity.z = direction.z * WALK_SPEED
	velocity.y = -0.5 if player.is_on_floor() else velocity.y - GRAVITY * delta
	if Input.is_action_just_pressed("jump") and player.is_on_floor():
		velocity.y = 9.0
	# Infinite inertia lets the character push the mission crate without inheriting its spin.
	velocity = player.move_and_slide(velocity, Vector3.UP, false, 4, deg2rad(46), true)

func drive(delta):
	var input = input_vector()
	var throttle = -input.y
	if car_fuel <= 0.0 or car_health <= 0:
		throttle = 0.0
	consume_car_fuel(throttle, delta)
	var acceleration = 15.0 if throttle >= 0 else 22.0
	if abs(throttle) > 0.05:
		car_speed = move_toward(car_speed, throttle * DRIVE_SPEED, acceleration * delta)
	else:
		car_speed = move_toward(car_speed, 0.0, 7.0 * delta)
	# Steering is weaker at a standstill and reverses naturally when backing up.
	var steering_strength = clamp(abs(car_speed) / 5.0, 0.18, 1.0)
	if abs(input.x) > 0.03:
		car.rotate_y(-input.x * delta * 1.65 * steering_strength * sign(car_speed if abs(car_speed) > 0.2 else 1.0))
	var forward = -car.global_transform.basis.z.normalized()
	# Gravity projected along the car's nose makes hills affect acceleration.
	car_speed += Vector3.DOWN.dot(forward) * 9.0 * delta
	var motion = forward * car_speed + Vector3.DOWN * 5.0
	var previous_position = car.global_transform.origin
	var impact_speed = abs(car_speed)
	car.move_and_slide(motion, Vector3.UP, true, 4, deg2rad(48))
	var hit_obstacle = false
	for collision_index in range(car.get_slide_count()):
		var collision = car.get_slide_collision(collision_index)
		if collision and abs(collision.normal.y) < 0.55:
			hit_obstacle = true
	if hit_obstacle and car.global_transform.origin.distance_to(previous_position) < impact_speed * delta * 0.35:
		car_speed *= 0.45
		apply_car_impact_damage(impact_speed)
	align_car_to_ground(delta)
	player.global_transform = car.global_transform
	player.translation.y += 1.2
	update_status()

func consume_car_fuel(throttle: float, delta: float):
	if abs(throttle) > 0.05 and car_fuel > 0.0 and car_health > 0:
		car_fuel = max(0.0, car_fuel - abs(throttle) * delta * 0.20)

func apply_car_impact_damage(impact_speed: float) -> int:
	if impact_speed <= 9.0 or car_damage_cooldown > 0.0:
		return 0
	var damage = int(clamp((impact_speed - 7.0) * 2.0, 4.0, 32.0))
	damage_vehicle(car, damage)
	car_damage_cooldown = 0.65
	prompt.text = "Kollision! Fahrzeugschaden: %d%%" % car_health
	update_status()
	return damage

func align_car_to_ground(delta):
	var origin = car.global_transform.origin
	var hit = get_world().direct_space_state.intersect_ray(origin + Vector3.UP * 2.0, origin + Vector3.DOWN * 3.5, [car, player])
	if not hit:
		return
	var normal = hit.normal.normalized()
	var forward = -car.global_transform.basis.z
	forward = (forward - normal * forward.dot(normal)).normalized()
	if forward.length() < 0.1:
		return
	var right = forward.cross(normal).normalized()
	var target_basis = Basis(right, normal, -forward).orthonormalized()
	var current_quat = Quat(car.global_transform.basis.orthonormalized())
	var target_quat = Quat(target_basis)
	var transform = car.global_transform
	transform.basis = Basis(current_quat.slerp(target_quat, clamp(delta * 7.0, 0.0, 1.0)))
	car.global_transform = transform

func toggle_car():
	if in_car:
		in_car = false
		player.translation = car.translation + car.global_transform.basis.x * 2.2 + Vector3.UP
		player_collider.disabled = false
		car_body.visible = true
	elif player.global_transform.origin.distance_to(car.global_transform.origin) < 3.5 and not bool(car.get_meta("destroyed")):
		in_car = true
		set_weapon("")
		player_collider.disabled = true
	update_status()

func set_weapon(weapon: String):
	reload_remaining = 0.0
	reloading_weapon = ""
	equipped_weapon = weapon
	pistol_model.visible = weapon == "pistol"
	bazooka_model.visible = weapon == "bazooka"
	rifle_model.visible = weapon == "rifle"
	crosshair.visible = weapon != ""
	update_status()

func update_weapon_system(delta: float, controls_locked: bool):
	weapon_cooldown = max(0.0, weapon_cooldown - delta)
	rifle_bloom = move_toward(rifle_bloom, 0.0, delta * 0.65)
	weapon_kick = move_toward(weapon_kick, 0.0, delta * 0.55)
	weapon_pivot.translation.z = weapon_kick
	if reload_remaining > 0.0:
		reload_remaining = max(0.0, reload_remaining - delta)
		if reload_remaining <= 0.0:
			finish_reload()
		else:
			update_status()
	if equipped_weapon == "rifle" and rifle_fire_mode == "auto" and not in_car and not controls_locked and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("shoot"):
		try_fire_weapon()

func try_fire_weapon():
	if equipped_weapon == "" or weapon_cooldown > 0.0 or reload_remaining > 0.0:
		return
	if not ammo_in_mag.has(equipped_weapon):
		return
	if int(ammo_in_mag[equipped_weapon]) <= 0:
		start_reload()
		return
	if equipped_weapon == "bazooka" and not bazooka_ready:
		return
	ammo_in_mag[equipped_weapon] = int(ammo_in_mag[equipped_weapon]) - 1
	if equipped_weapon == "pistol":
		weapon_cooldown = 0.24
		fire_hitscan("pistol")
	elif equipped_weapon == "rifle":
		weapon_cooldown = 0.095
		fire_hitscan("rifle")
	else:
		weapon_cooldown = 1.20
		fire_bazooka()
	apply_weapon_recoil(equipped_weapon)
	update_status()

func start_reload():
	if equipped_weapon == "" or reload_remaining > 0.0 or not ammo_in_mag.has(equipped_weapon):
		return
	var current = int(ammo_in_mag[equipped_weapon])
	var capacity = int(magazine_capacity[equipped_weapon])
	if current >= capacity or int(ammo_reserve[equipped_weapon]) <= 0:
		return
	reloading_weapon = equipped_weapon
	reload_remaining = 1.35 if equipped_weapon == "pistol" else (1.90 if equipped_weapon == "rifle" else 2.80)
	update_status()

func finish_reload():
	if reloading_weapon == "" or not ammo_in_mag.has(reloading_weapon):
		return
	var required = int(magazine_capacity[reloading_weapon]) - int(ammo_in_mag[reloading_weapon])
	var loaded = min(required, int(ammo_reserve[reloading_weapon]))
	ammo_in_mag[reloading_weapon] = int(ammo_in_mag[reloading_weapon]) + loaded
	ammo_reserve[reloading_weapon] = int(ammo_reserve[reloading_weapon]) - loaded
	reloading_weapon = ""
	update_status()

func fire_hitscan(weapon: String):
	var from = camera.global_transform.origin
	var base_direction = -camera.global_transform.basis.z
	var spread_degrees = 0.35 if weapon == "pistol" else 0.55 + rifle_bloom
	var spread = deg2rad(spread_degrees)
	var direction = (base_direction + camera.global_transform.basis.x * rand_range(-spread, spread) + camera.global_transform.basis.y * rand_range(-spread, spread)).normalized()
	var weapon_range = 140.0 if weapon == "pistol" else 240.0
	var to = from + direction * weapon_range
	var excluded = [player]
	if in_car:
		excluded.append(car)
	var hit = get_world().direct_space_state.intersect_ray(from, to, excluded)
	var end = hit.position if hit else to
	var model = pistol_model if weapon == "pistol" else rifle_model
	var flash = model.get_node("MuzzleFlash")
	show_shot_trace(flash.global_transform.origin, end)
	play_sound_3d(weapon, flash.global_transform.origin, -2.0 if weapon == "pistol" else -1.0)
	flash.visible = true
	get_tree().create_timer(0.045).connect("timeout", flash, "set_visible", [false])
	eject_casing(weapon)
	if hit:
		show_impact(hit.position, hit.normal)
	if hit and hit.collider.has_meta("health"):
		var target = hit.collider
		var damage = 55 if weapon == "pistol" else 34
		var distance = from.distance_to(hit.position)
		var falloff_start = 35.0 if weapon == "pistol" else 90.0
		if distance > falloff_start:
			damage = int(float(damage) * clamp(1.0 - (distance - falloff_start) / weapon_range, 0.55, 1.0))
		if hit.position.y > target.global_transform.origin.y + 1.45:
			damage = int(float(damage) * (2.0 if weapon == "pistol" else 4.0))
		apply_weapon_damage(target, damage)
	if weapon == "rifle":
		rifle_bloom = min(1.45, rifle_bloom + 0.12)

func apply_weapon_damage(target, damage: int):
	if not is_instance_valid(target) or not target.has_meta("health"):
		return
	var role = str(target.get_meta("role"))
	if role == "vehicle":
		damage_vehicle(target, damage)
		return
	if role == "civilian" and not target.has_meta("police_called"):
		target.set_meta("police_called", true)
		dispatch_police(target.global_transform.origin)
	var health = int(target.get_meta("health")) - damage
	target.set_meta("health", health)
	if health > 0:
		return
	if role == "civilian":
		npcs.erase(target)
	else:
		police_officers.erase(target)
	target.queue_free()

func apply_weapon_recoil(weapon: String):
	var vertical_recoil = 1.40 if weapon == "pistol" else (0.62 if weapon == "rifle" else 3.0)
	look_x = clamp(look_x - vertical_recoil, -80.0, 80.0)
	camera.rotation_degrees.x = look_x
	player.rotate_y(deg2rad(rand_range(-0.22, 0.22) * (1.0 if weapon != "bazooka" else 2.0)))
	weapon_kick = min(0.14, weapon_kick + (0.055 if weapon == "rifle" else 0.085))

func eject_casing(weapon: String):
	var casing = RigidBody.new()
	casing.name = "RifleCasing" if weapon == "rifle" else "PistolCasing"
	casing.mass = 0.02
	add_child(casing)
	var position = camera.global_transform.origin + camera.global_transform.basis.x * 0.28 + camera.global_transform.basis.y * -0.10 + -camera.global_transform.basis.z * 0.38
	var casing_transform = Transform(Basis(), position)
	casing.global_transform = casing_transform
	add_cylinder(casing, "Brass", Vector3.ZERO, 0.018, 0.075 if weapon == "rifle" else 0.055, Color("b58a35"), Vector3(0, 0, 90))
	var collision = CollisionShape.new()
	var shape = CylinderShape.new()
	shape.radius = 0.018
	shape.height = 0.075 if weapon == "rifle" else 0.055
	collision.shape = shape
	collision.rotation_degrees.z = 90
	casing.add_child(collision)
	casing.linear_velocity = camera.global_transform.basis.x * 2.4 + Vector3.UP * 1.2 + camera.global_transform.basis.z * rand_range(-0.4, 0.4)
	casing.angular_velocity = Vector3(rand_range(-8.0, 8.0), rand_range(-8.0, 8.0), rand_range(-8.0, 8.0))
	get_tree().create_timer(2.0).connect("timeout", casing, "queue_free")

func fire_bazooka():
	if not bazooka_ready:
		return
	bazooka_ready = false
	var muzzle_flash = bazooka_model.get_node("MuzzleFlash")
	muzzle_flash.visible = true
	get_tree().create_timer(0.10).connect("timeout", muzzle_flash, "set_visible", [false])
	var from = muzzle_flash.global_transform.origin
	play_sound_3d("rocket", from, -1.0)
	var to = camera.global_transform.origin + -camera.global_transform.basis.z * 300.0
	var rocket_excluded = [player]
	if in_car:
		rocket_excluded.append(car)
	var hit = get_world().direct_space_state.intersect_ray(camera.global_transform.origin, to, rocket_excluded)
	var end = hit.position if hit else to
	var target = hit.collider if hit else null
	var normal = hit.normal if hit else Vector3.UP
	var rocket = add_sphere(self, "BazookaRocket", from, 0.13, Color("ff9d32"))
	var rocket_mat = rocket.mesh.material as SpatialMaterial
	rocket_mat.emission_enabled = true
	rocket_mat.emission = Color("ff6d20")
	var backblast_position = camera.global_transform.origin + camera.global_transform.basis.z * 0.75
	var backblast = add_sphere(self, "Backblast", backblast_position, 0.55, Color("ff7b32"))
	var backblast_material = backblast.mesh.material as SpatialMaterial
	backblast_material.emission_enabled = true
	backblast_material.emission = Color("ff5b20")
	get_tree().create_timer(0.16).connect("timeout", backblast, "queue_free")
	var tween = Tween.new()
	add_child(tween)
	tween.interpolate_property(rocket, "translation", from, end, clamp(from.distance_to(end) / 120.0, 0.12, 1.2), Tween.TRANS_LINEAR, Tween.EASE_IN)
	tween.connect("tween_all_completed", self, "_on_rocket_arrived", [rocket, tween, target, end, normal], CONNECT_ONESHOT)
	tween.start()
	get_tree().create_timer(1.4).connect("timeout", self, "set_bazooka_ready")

func set_bazooka_ready():
	bazooka_ready = true

func _on_rocket_arrived(rocket, tween, target, position: Vector3, normal: Vector3):
	if is_instance_valid(rocket):
		rocket.queue_free()
	if is_instance_valid(tween):
		tween.queue_free()
	show_explosion(position, normal)
	apply_explosion_damage(position, 10.0)
	var building = find_destructible_building(target)
	if building:
		collapse_building(building)

func find_destructible_building(target):
	var node = target
	while is_instance_valid(node) and node != self:
		if node.has_meta("destructible_building"):
			return node
		node = node.get_parent()
	return null

func show_explosion(position: Vector3, normal: Vector3):
	play_sound_3d("explosion", position, 1.5)
	var blast = add_sphere(self, "Explosion", position + normal * 0.4, 2.2, Color("ff7b22"))
	var blast_mat = blast.mesh.material as SpatialMaterial
	blast_mat.emission_enabled = true
	blast_mat.emission = Color("ff3b0a")
	var light = OmniLight.new()
	light.light_color = Color("ff742b")
	light.omni_range = 18.0
	light.light_energy = 5.0
	blast.add_child(light)
	var tween = Tween.new()
	blast.add_child(tween)
	tween.interpolate_property(blast, "scale", Vector3(0.15, 0.15, 0.15), Vector3(3.2, 2.3, 3.2), 0.28, Tween.TRANS_QUAD, Tween.EASE_OUT)
	tween.start()
	get_tree().create_timer(0.7).connect("timeout", blast, "queue_free")

func register_damageable_vehicle(vehicle, health: int, kind: String):
	vehicle.set_meta("health", health)
	vehicle.set_meta("max_health", health)
	vehicle.set_meta("role", "vehicle")
	vehicle.set_meta("vehicle_kind", kind)
	vehicle.set_meta("destroyed", false)

func damage_vehicle(vehicle, amount: int, create_blast := true):
	if not is_instance_valid(vehicle) or not vehicle.has_meta("health"):
		return
	if vehicle.has_meta("destroyed") and bool(vehicle.get_meta("destroyed")):
		return
	var health = max(0, int(vehicle.get_meta("health")) - max(0, amount))
	vehicle.set_meta("health", health)
	if vehicle == car:
		car_health = health
	if health <= 0:
		destroy_vehicle(vehicle, create_blast)
	else:
		update_status()

func destroy_vehicle(vehicle, create_blast := true):
	if not is_instance_valid(vehicle) or (vehicle.has_meta("destroyed") and bool(vehicle.get_meta("destroyed"))):
		return
	vehicle.set_meta("destroyed", true)
	vehicle.set_meta("health", 0)
	destroyed_vehicles.append(vehicle)
	var wreck_position = vehicle.global_transform.origin + Vector3.UP * 0.65
	if create_blast:
		show_explosion(wreck_position, Vector3.UP)
		apply_explosion_damage(wreck_position, 7.0)
	if vehicle == car:
		car_health = 0
		car_speed = 0.0
		if in_car:
			in_car = false
			player.global_transform = Transform(car.global_transform.basis, car.global_transform.origin + car.global_transform.basis.x * 2.8 + Vector3.UP)
			player_collider.disabled = false
			set_weapon("")
			damage_player(35)
		alert_label.text = "FAHRZEUG ZERSTÖRT"
	char_vehicle_visuals(vehicle)
	create_vehicle_fire(vehicle)
	update_status()

func char_vehicle_visuals(node):
	for child in node.get_children():
		if child is MeshInstance:
			var burnt = material(Color("211f1c"))
			burnt.roughness = 1.0
			burnt.metallic = 0.12
			child.material_override = burnt
		char_vehicle_visuals(child)

func create_vehicle_fire(vehicle):
	var effect = Spatial.new()
	effect.name = "VehicleFire"
	add_child(effect)
	effect.global_transform = Transform(Basis(), vehicle.global_transform.origin + Vector3.UP * 0.55)
	var flame_colors = [Color("ff3b0a"), Color("ff7a13"), Color("ffd447")]
	for flame_index in range(5):
		var angle = float(flame_index) / 5.0 * PI * 2.0
		var base_position = Vector3(cos(angle) * 0.62, 0.48 + float(flame_index % 2) * 0.28, sin(angle) * 0.82)
		var flame = add_sphere(effect, "Flame%d" % flame_index, base_position, 0.48 + float(flame_index % 3) * 0.10, flame_colors[flame_index % flame_colors.size()])
		var flame_material = flame.mesh.material as SpatialMaterial
		flame_material.emission_enabled = true
		flame_material.emission = flame_material.albedo_color
		flame.set_meta("base_position", base_position)
		flame.set_meta("phase", float(flame_index) * 1.37)
	for smoke_index in range(4):
		var smoke_position = Vector3((float(smoke_index) - 1.5) * 0.28, 1.25 + float(smoke_index) * 0.58, sin(float(smoke_index) * 2.1) * 0.34)
		var smoke = add_sphere(effect, "Smoke%d" % smoke_index, smoke_position, 0.62 + float(smoke_index) * 0.12, Color(0.09, 0.085, 0.08, 0.58))
		var smoke_material = smoke.mesh.material as SpatialMaterial
		smoke_material.flags_transparent = true
		smoke.set_meta("start_y", smoke_position.y)
		smoke.set_meta("phase", float(smoke_index) * 0.91)
	var fire_light = OmniLight.new()
	fire_light.name = "FireLight"
	fire_light.translation = Vector3(0, 1.1, 0)
	fire_light.light_color = Color("ff641c")
	fire_light.light_energy = 3.2
	fire_light.omni_range = 13.0
	effect.add_child(fire_light)
	var fire_audio = play_sound_3d("fire", effect.global_transform.origin, -7.0, true)
	vehicle_fires.append({"effect": effect, "audio": fire_audio, "elapsed": 0.0, "duration": 20.0})

func update_vehicle_fires(delta: float):
	for fire_index in range(vehicle_fires.size() - 1, -1, -1):
		var fire_data = vehicle_fires[fire_index]
		var effect = fire_data.effect
		if not is_instance_valid(effect):
			vehicle_fires.remove(fire_index)
			continue
		fire_data.elapsed = float(fire_data.elapsed) + delta
		vehicle_fires[fire_index] = fire_data
		for fire_child in effect.get_children():
			if fire_child.name.begins_with("Flame"):
				var phase = float(fire_child.get_meta("phase"))
				var pulse = 0.82 + sin(float(fire_data.elapsed) * 10.0 + phase) * 0.20
				fire_child.scale = Vector3(pulse, pulse * 1.35, pulse)
				var flame_base = fire_child.get_meta("base_position")
				fire_child.translation = flame_base + Vector3(0, sin(float(fire_data.elapsed) * 7.0 + phase) * 0.12, 0)
			elif fire_child.name.begins_with("Smoke"):
				var smoke_phase = float(fire_child.get_meta("phase"))
				fire_child.translation.y += delta * (0.34 + smoke_phase * 0.08)
				fire_child.translation.x += sin(float(fire_data.elapsed) * 1.7 + smoke_phase) * delta * 0.11
				if fire_child.translation.y > float(fire_child.get_meta("start_y")) + 3.2:
					fire_child.translation.y = float(fire_child.get_meta("start_y"))
		if float(fire_data.elapsed) >= float(fire_data.duration):
			if is_instance_valid(fire_data.audio):
				fire_data.audio.stop()
				fire_data.audio.queue_free()
			effect.queue_free()
			vehicle_fires.remove(fire_index)

func apply_explosion_damage(position: Vector3, radius: float):
	var vehicles = [car]
	for response in emergency_vehicles:
		if is_instance_valid(response.node) and not vehicles.has(response.node):
			vehicles.append(response.node)
	for vehicle in vehicles:
		if not is_instance_valid(vehicle) or not vehicle.has_meta("role") or str(vehicle.get_meta("role")) != "vehicle":
			continue
		var vehicle_distance = vehicle.global_transform.origin.distance_to(position)
		if vehicle_distance < radius:
			var vehicle_damage = int(230.0 * (1.0 - vehicle_distance / radius))
			damage_vehicle(vehicle, vehicle_damage, false)
	for target_group in [npcs.duplicate(), police_officers.duplicate()]:
		for target in target_group:
			if not is_instance_valid(target):
				continue
			var target_distance = target.global_transform.origin.distance_to(position)
			if target_distance < radius:
				var blast_damage = int(180.0 * (1.0 - target_distance / radius))
				if blast_damage > 0:
					apply_weapon_damage(target, blast_damage)
	if not in_car:
		var player_distance = player.global_transform.origin.distance_to(position)
		if player_distance < radius:
			var player_blast_damage = int(90.0 * (1.0 - player_distance / radius))
			if player_blast_damage > 0:
				damage_player(player_blast_damage)

func collapse_building(building):
	if building in destroyed_buildings:
		return
	destroyed_buildings.append(building)
	var building_position = building.global_transform.origin
	var collision_shape = building.get_node_or_null("CollisionShape")
	var extents = Vector3(8, 10, 8)
	if collision_shape and collision_shape.shape is BoxShape:
		extents = collision_shape.shape.extents
	var ground_y = building_position.y - extents.y
	var rubble = Spatial.new()
	rubble.name = "Rubble_%s" % building.name
	rubble.translation = Vector3(building_position.x, ground_y, building_position.z)
	add_child(rubble)
	for i in range(20):
		var chunk_size = Vector3(1.1 + fmod(i * 1.37, 2.5), 0.5 + fmod(i * 0.73, 1.5), 1.0 + fmod(i * 0.91, 2.2))
		var spread_x = sin(float(i) * 2.31) * extents.x * 0.86
		var spread_z = cos(float(i) * 1.73) * extents.z * 0.86
		var chunk = add_box(rubble, "RubbleChunk", Vector3(spread_x, chunk_size.y * 0.5, spread_z), chunk_size, Color("756c63"), i < 8)
		chunk.rotation_degrees = Vector3((i * 19) % 35, (i * 43) % 180, (i * 11) % 28)
	for flame_position in [Vector3(-2, 0.8, 1), Vector3(2.5, 1.1, -1.5), Vector3(0, 1.4, 0)]:
		var flame = add_sphere(rubble, "Fire", flame_position, 0.7, Color("ff6422"))
		var flame_mat = flame.mesh.material as SpatialMaterial
		flame_mat.emission_enabled = true
		flame_mat.emission = Color("ff3c0d")
	building.queue_free()
	prompt.text = "Gebäude zerstört – Feuerwehr alarmiert"
	dispatch_fire_department(Vector3(building_position.x, ground_y, building_position.z))
	dispatch_police(Vector3(building_position.x, ground_y, building_position.z), 2)

func nearest_road(value: float) -> float:
	var result = -180.0
	var best_distance = INF
	for road in [-180.0, -90.0, 0.0, 90.0, 180.0]:
		var distance = abs(value - road)
		if distance < best_distance:
			best_distance = distance
			result = road
	return result

func nearest_expansion_axis(value: float) -> float:
	var result = -180.0
	var best_distance = INF
	for road in [-180.0, 0.0, 180.0]:
		var distance = abs(value - road)
		if distance < best_distance:
			best_distance = distance
			result = road
	return result

func clamp_response_point(point: Vector3) -> Vector3:
	# Keep the full responder body inside the colliding +/-699 m guard rail.
	point.x = clamp(point.x, -680.0, 680.0)
	point.z = clamp(point.z, -680.0, 680.0)
	return point

func response_route(incident: Vector3, variant: int) -> Array:
	var direction_sign = 1.0 if variant % 2 == 0 else -1.0
	# Outside the legacy 520 m core, route responders along the generated
	# outbound axes or the +/-320 m orbital road instead of across open terrain.
	if abs(incident.x) > 260.0 and abs(incident.z) <= 260.0:
		var horizontal_target = clamp_response_point(Vector3(incident.x, 0.0, nearest_expansion_axis(incident.z)))
		var horizontal_spawn = clamp_response_point(horizontal_target + Vector3(65.0 * direction_sign, 0, 0))
		return [horizontal_spawn, horizontal_target]
	if abs(incident.z) > 260.0 and abs(incident.x) <= 260.0:
		var vertical_target = clamp_response_point(Vector3(nearest_expansion_axis(incident.x), 0.0, incident.z))
		var vertical_spawn = clamp_response_point(vertical_target + Vector3(0, 0, 65.0 * direction_sign))
		return [vertical_spawn, vertical_target]
	if abs(incident.x) > 260.0 and abs(incident.z) > 260.0:
		var ring_x = 320.0 * sign(incident.x)
		var ring_z = 320.0 * sign(incident.z)
		if abs(abs(incident.x) - 320.0) < abs(abs(incident.z) - 320.0):
			var vertical_ring_target = clamp_response_point(Vector3(ring_x, 0.0, incident.z))
			var vertical_ring_spawn = clamp_response_point(vertical_ring_target + Vector3(0, 0, 65.0 * direction_sign))
			return [vertical_ring_spawn, vertical_ring_target]
		var horizontal_ring_target = clamp_response_point(Vector3(incident.x, 0.0, ring_z))
		var horizontal_ring_spawn = clamp_response_point(horizontal_ring_target + Vector3(65.0 * direction_sign, 0, 0))
		return [horizontal_ring_spawn, horizontal_ring_target]
	var road_x = nearest_road(incident.x)
	var road_z = nearest_road(incident.z)
	var target
	var spawn
	if abs(incident.x - road_x) < abs(incident.z - road_z):
		target = Vector3(road_x, 0.0, incident.z)
		spawn = target + Vector3(0, 0, 65.0 * direction_sign)
	else:
		target = Vector3(incident.x, 0.0, road_z)
		spawn = target + Vector3(65.0 * direction_sign, 0, 0)
	return [spawn, target]

func create_emergency_vehicle(kind: String, spawn_position: Vector3):
	var vehicle = KinematicBody.new()
	vehicle.name = "FireEngine" if kind == "fire" else "PoliceCar"
	vehicle.translation = spawn_position
	register_damageable_vehicle(vehicle, 240 if kind == "fire" else 160, "%s_vehicle" % kind)
	add_child(vehicle)
	if kind == "fire":
		add_box(vehicle, "Body", Vector3(0, 0.55, 0), Vector3(2.6, 1.45, 5.8), Color("c52520"), false)
		add_box(vehicle, "Cab", Vector3(0, 1.42, -1.62), Vector3(2.4, 1.25, 2.15), Color("e43a31"), false)
		add_box(vehicle, "Windshield", Vector3(0, 1.55, -2.72), Vector3(2.0, 0.65, 0.08), Color("315b6d"), false)
		add_box(vehicle, "Ladder", Vector3(0, 1.55, 0.95), Vector3(0.65, 0.18, 3.0), Color("d8d7cc"), false)
		for side in [-1, 1]:
			for z in [-1.7, 1.75]:
				add_cylinder(vehicle, "Wheel", Vector3(side * 1.34, -0.05, z), 0.52, 0.30, Color("111214"), Vector3(0, 0, 90))
		var fire_collision = CollisionShape.new()
		fire_collision.name = "CollisionShape"
		var fire_shape = BoxShape.new()
		fire_shape.extents = Vector3(1.38, 0.92, 3.0)
		fire_collision.shape = fire_shape
		fire_collision.translation.y = 0.72
		vehicle.add_child(fire_collision)
	else:
		# German patrol-car silhouette: silver body, blue side livery, glass cabin and blue/blue lightbar.
		add_box(vehicle, "LowerBody", Vector3(0, 0.35, 0), Vector3(2.16, 0.68, 4.55), Color("d9dcdd"), false)
		add_box(vehicle, "Hood", Vector3(0, 0.66, -1.56), Vector3(2.04, 0.19, 1.24), Color("e9ebeb"), false)
		add_box(vehicle, "Trunk", Vector3(0, 0.64, 1.72), Vector3(2.02, 0.20, 0.78), Color("e7e9e9"), false)
		add_box(vehicle, "Roof", Vector3(0, 1.39, 0.20), Vector3(1.72, 0.13, 1.78), Color("e7e9e9"), false)
		add_box(vehicle, "Windshield", Vector3(0, 1.08, -0.66), Vector3(1.72, 0.59, 0.08), Color("294858"), false).rotation_degrees.x = -19
		add_box(vehicle, "RearWindow", Vector3(0, 1.08, 1.08), Vector3(1.72, 0.55, 0.08), Color("294858"), false).rotation_degrees.x = 19
		add_box(vehicle, "LightbarBase", Vector3(0, 1.54, 0.13), Vector3(1.15, 0.08, 0.28), Color("222a31"), false)
		add_box(vehicle, "FrontBumper", Vector3(0, 0.18, -2.33), Vector3(2.18, 0.20, 0.15), Color("22272b"), false)
		add_box(vehicle, "RearBumper", Vector3(0, 0.18, 2.33), Vector3(2.18, 0.20, 0.15), Color("22272b"), false)
		add_box(vehicle, "FrontGrille", Vector3(0, 0.48, -2.31), Vector3(0.78, 0.25, 0.08), Color("15191d"), false)
		for side in [-1, 1]:
			add_box(vehicle, "SideWindow", Vector3(side * 0.88, 1.08, 0.20), Vector3(0.06, 0.52, 1.20), Color("244555"), false)
			add_box(vehicle, "BlueSideStripe", Vector3(side * 1.09, 0.61, 0.02), Vector3(0.045, 0.30, 3.63), Color("1765a2"), false)
			add_box(vehicle, "PoliceDoorPanel", Vector3(side * 1.115, 0.66, 0.20), Vector3(0.025, 0.18, 1.02), Color("e8ecec"), false)
			var door_label = Label3D.new()
			door_label.name = "PoliceDoorLabelLeft" if side < 0 else "PoliceDoorLabelRight"
			door_label.text = "POLIZEI"
			door_label.translation = Vector3(side * 1.135, 0.66, 0.20)
			door_label.rotation_degrees.y = float(side) * 90.0
			door_label.pixel_size = 0.014
			door_label.modulate = Color("175f98")
			vehicle.add_child(door_label)
			add_box(vehicle, "Mirror", Vector3(side * 1.15, 1.00, -0.64), Vector3(0.24, 0.17, 0.28), Color("1c2730"), false)
			for z in [-1.35, 1.35]:
				add_cylinder(vehicle, "Wheel", Vector3(side * 1.07, -0.08, z), 0.42, 0.25, Color("111214"), Vector3(0, 0, 90))
		for x in [-0.70, 0.70]:
			add_box(vehicle, "Headlight", Vector3(x, 0.58, -2.33), Vector3(0.48, 0.23, 0.08), Color("fff3bd"), false)
			add_box(vehicle, "TailLight", Vector3(x, 0.56, 2.33), Vector3(0.46, 0.23, 0.08), Color("c83238"), false)
		var vehicle_collision = CollisionShape.new()
		vehicle_collision.name = "CollisionShape"
		var vehicle_shape = BoxShape.new()
		vehicle_shape.extents = Vector3(1.12, 0.72, 2.35)
		vehicle_collision.shape = vehicle_shape
		vehicle_collision.translation.y = 0.55
		vehicle.add_child(vehicle_collision)
	if kind == "fire":
		var red_light = add_sphere(vehicle, "RedLight", Vector3(-0.30, 1.85, 0), 0.14, Color("ff2020"))
		var blue_light = add_sphere(vehicle, "BlueLight", Vector3(0.30, 1.85, 0), 0.14, Color("248dff"))
		for light_mesh in [red_light, blue_light]:
			var light_mat = light_mesh.mesh.material as SpatialMaterial
			light_mat.emission_enabled = true
			light_mat.emission = light_mat.albedo_color
	else:
		for light_data in [["BlueLightLeft", -0.36], ["BlueLightRight", 0.36]]:
			var police_light = add_box(vehicle, light_data[0], Vector3(float(light_data[1]), 1.61, 0.13), Vector3(0.56, 0.16, 0.24), Color("167cff"), false)
			var police_light_mat = police_light.mesh.material as SpatialMaterial
			police_light_mat.emission_enabled = true
			police_light_mat.emission = Color("167cff")
	return vehicle

func dispatch_fire_department(incident: Vector3):
	var route = response_route(incident, destroyed_buildings.size())
	var fire_spawn = route[0]
	var fire_target = route[1]
	fire_spawn.y = 0.62
	fire_target.y = 0.62
	var engine = create_emergency_vehicle("fire", fire_spawn)
	emergency_vehicles.append({"node": engine, "kind": "fire", "target": fire_target, "incident": incident, "arrived": false})
	alert_label.text = "FEUERWEHR AUF ANFAHRT"

func dispatch_police(incident: Vector3, severity := 1):
	wanted_level = min(3, wanted_level + int(severity))
	update_status()
	police_dispatch_count += 1
	for unit in range(2):
		var route = response_route(incident, police_dispatch_count + unit)
		var police_spawn = route[0]
		var police_target = route[1]
		police_spawn.y = 0.55
		police_target.y = 0.55
		var police_car = create_emergency_vehicle("police", police_spawn + Vector3(unit * 2.6, 0, unit * 2.6))
		emergency_vehicles.append({"node": police_car, "kind": "police", "target": police_target, "incident": incident, "arrived": false})
	alert_label.text = "POLIZEI ALARMIERT"

func update_emergency_vehicles(delta):
	for response in emergency_vehicles:
		var vehicle = response.node
		if not is_instance_valid(vehicle) or response.arrived:
			continue
		if vehicle.has_meta("destroyed") and bool(vehicle.get_meta("destroyed")):
			response.arrived = true
			continue
		var target = response.target
		var offset = target - vehicle.translation
		offset.y = 0
		if offset.length() > 2.5:
			var speed = FIRE_ENGINE_SPEED if response.kind == "fire" else POLICE_SPEED
			if vehicle is KinematicBody:
				vehicle.move_and_slide(offset.normalized() * speed, Vector3.UP)
			else:
				vehicle.translation += offset.normalized() * speed * delta
			vehicle.look_at(Vector3(target.x, vehicle.translation.y, target.z), Vector3.UP)
		else:
			response.arrived = true
			if response.kind == "police":
				spawn_police_officers(vehicle.global_transform.origin)
				alert_label.text = "POLIZEI: STEHEN BLEIBEN!"
			else:
				spawn_firefighters(vehicle.global_transform.origin, response.incident)
				alert_label.text = "FEUERWEHR AM EINSATZORT"
		var flash = int(OS.get_ticks_msec() / 220) % 2 == 0
		if vehicle.has_node("BlueLightLeft"):
			vehicle.get_node("BlueLightLeft").visible = flash
			vehicle.get_node("BlueLightRight").visible = not flash
		elif vehicle.has_node("RedLight"):
			vehicle.get_node("RedLight").visible = flash
		if vehicle.has_node("BlueLight"):
			vehicle.get_node("BlueLight").visible = not flash

func spawn_police_officers(vehicle_position: Vector3):
	for side in [-1, 1]:
		var officer = KinematicBody.new()
		officer.name = "PoliceOfficer"
		officer.translation = Vector3(vehicle_position.x + side * 2.0, 0.05, vehicle_position.z)
		officer.set_meta("health", 120)
		officer.set_meta("role", "police")
		officer.set_meta("shoot_cooldown", 0.4 + float(side + 1) * 0.25)
		officer.set_meta("shots_fired", 0)
		var human = HUMAN_SCENE.instance()
		human.name = "OfficerModel"
		officer.add_child(human)
		build_police_officer_gear(officer)
		var collision = CollisionShape.new()
		var shape = CapsuleShape.new()
		shape.radius = 0.42
		shape.height = 1.25
		collision.shape = shape
		collision.translation.y = 1.0
		officer.add_child(collision)
		add_child(officer)
		police_officers.append(officer)

func build_police_officer_gear(officer):
	# Navy operational uniform with a segmented vest, equipment belt, cap and service pistol.
	add_box(officer, "FrontVest", Vector3(0, 1.08, -0.24), Vector3(0.72, 0.68, 0.12), Color("173858"), false)
	add_box(officer, "BackVest", Vector3(0, 1.08, 0.24), Vector3(0.72, 0.68, 0.12), Color("173858"), false)
	add_box(officer, "FrontPolicePatch", Vector3(0, 1.18, -0.31), Vector3(0.44, 0.13, 0.025), Color("d7e8f0"), false)
	add_box(officer, "BackPolicePatch", Vector3(0, 1.18, 0.31), Vector3(0.50, 0.13, 0.025), Color("d7e8f0"), false)
	for label_data in [["FrontPoliceLabel", -0.326, 180.0], ["BackPoliceLabel", 0.326, 0.0]]:
		var police_label = Label3D.new()
		police_label.name = label_data[0]
		police_label.text = "POLIZEI"
		police_label.translation = Vector3(0, 1.18, float(label_data[1]))
		police_label.rotation_degrees.y = float(label_data[2])
		police_label.pixel_size = 0.007
		police_label.modulate = Color("173858")
		officer.add_child(police_label)
	add_box(officer, "UtilityBelt", Vector3(0, 0.78, 0), Vector3(0.80, 0.12, 0.45), Color("111820"), false)
	add_box(officer, "MagazinePouch", Vector3(-0.20, 0.86, -0.27), Vector3(0.16, 0.25, 0.11), Color("101820"), false)
	add_box(officer, "Radio", Vector3(0.27, 1.24, -0.30), Vector3(0.14, 0.29, 0.10), Color("101419"), false)
	add_cylinder(officer, "RadioAntenna", Vector3(0.27, 1.47, -0.30), 0.018, 0.24, Color("0b0d10"))
	add_box(officer, "Holster", Vector3(0.43, 0.68, -0.04), Vector3(0.16, 0.39, 0.18), Color("111418"), false)
	add_box(officer, "ShoulderPatchLeft", Vector3(-0.39, 1.29, -0.02), Vector3(0.035, 0.22, 0.18), Color("2f78a8"), false)
	add_box(officer, "ShoulderPatchRight", Vector3(0.39, 1.29, -0.02), Vector3(0.035, 0.22, 0.18), Color("2f78a8"), false)
	add_cylinder(officer, "PoliceCap", Vector3(0, 1.86, 0), 0.31, 0.16, Color("162f4a"))
	add_box(officer, "CapBrim", Vector3(0, 1.80, -0.25), Vector3(0.48, 0.05, 0.32), Color("10243a"), false)
	var service_pistol = Spatial.new()
	service_pistol.name = "ServicePistol"
	service_pistol.translation = Vector3(0.24, 1.28, -0.37)
	officer.add_child(service_pistol)
	add_box(service_pistol, "Slide", Vector3(0, 0.02, -0.14), Vector3(0.14, 0.13, 0.45), Color("171b20"), false)
	add_box(service_pistol, "Grip", Vector3(0, -0.20, 0.01), Vector3(0.13, 0.32, 0.17), Color("111418"), false).rotation_degrees.x = -10
	add_cylinder(service_pistol, "Barrel", Vector3(0, 0.02, -0.41), 0.032, 0.11, Color("080a0c"), Vector3(90, 0, 0))
	var muzzle_flash = add_sphere(service_pistol, "MuzzleFlash", Vector3(0, 0.02, -0.49), 0.10, Color("ffd15b"))
	muzzle_flash.scale = Vector3(0.65, 0.65, 1.8)
	muzzle_flash.visible = false

func update_police_officers(delta):
	for officer in police_officers.duplicate():
		if not is_instance_valid(officer):
			police_officers.erase(officer)
			continue
		var target_body = car if in_car else player
		var target_position = target_body.global_transform.origin
		var offset = target_position - officer.global_transform.origin
		offset.y = 0
		if offset.length() > 7.0:
			officer.move_and_slide(offset.normalized() * OFFICER_SPEED + Vector3.DOWN * 4.0, Vector3.UP)
		if offset.length() > 0.2:
			officer.look_at(Vector3(target_position.x, officer.global_transform.origin.y, target_position.z), Vector3.UP)
		var cooldown = float(officer.get_meta("shoot_cooldown")) - delta
		if cooldown <= 0.0 and offset.length() < 38.0:
			police_shoot(officer)
			cooldown = 1.15
		officer.set_meta("shoot_cooldown", cooldown)

func police_shoot(officer):
	if not is_instance_valid(officer) or player_dying:
		return
	var target_body = car if in_car else player
	var target_shape = player_collider if target_body == player else target_body.get_node_or_null("CollisionShape")
	var aim_point = target_shape.global_transform.origin if target_shape else target_body.global_transform.origin
	# The player's origin is the capsule centre. Aim slightly below it, squarely
	# through the lower chest/upper abdomen, so the visible trace cannot pass overhead.
	if target_body == player:
		aim_point += Vector3.DOWN * 0.18
	else:
		aim_point += Vector3.UP * 0.08
	var service_pistol = officer.get_node_or_null("ServicePistol")
	var muzzle_flash = service_pistol.get_node_or_null("MuzzleFlash") if service_pistol else null
	var from = muzzle_flash.global_transform.origin if muzzle_flash else officer.global_transform.origin + Vector3.UP * 1.35
	var shot_number = int(officer.get_meta("shots_fired")) + 1
	officer.set_meta("shots_fired", shot_number)
	# A deterministic occasional miss keeps the encounter readable without bypassing physical cover.
	if shot_number % 5 == 0:
		var miss_direction = (aim_point - from).normalized().cross(Vector3.UP).normalized()
		aim_point += miss_direction * 1.15
	officer.set_meta("last_aim_point", aim_point)
	var direction = (aim_point - from).normalized()
	var ray_end = aim_point + direction * 2.5
	var hit = get_world().direct_space_state.intersect_ray(from, ray_end, [officer])
	var trace_end = hit.position if hit else aim_point
	show_shot_trace(from, trace_end)
	play_sound_3d("police_pistol", from, -4.0)
	if muzzle_flash:
		muzzle_flash.visible = true
		get_tree().create_timer(0.055).connect("timeout", muzzle_flash, "set_visible", [false])
	if hit:
		show_impact(hit.position, hit.normal)
	if not hit or hit.collider != target_body:
		return
	if in_car:
		damage_vehicle(car, 6)
		damage_player(7)
	else:
		damage_player(12)

func damage_player(amount: int):
	if player_dying or amount <= 0:
		return
	player_health = max(0, player_health - amount)
	damage_flash_time = 0.38
	prompt.text = "Du wirst beschossen!"
	update_status()
	if player_health <= 0:
		start_player_death()

func start_player_death():
	if player_dying:
		return
	player_dying = true
	player_health = 0
	velocity = Vector3.ZERO
	car_speed = 0.0
	if mission_one and mission_one.is_overlay_open():
		mission_one.close_dialogue()
	if in_car:
		in_car = false
		var exit_position = car.global_transform.origin + car.global_transform.basis.x * 2.6 + Vector3.UP * 0.8
		var car_yaw = car.rotation_degrees.y
		player.global_transform = Transform(Basis(), exit_position)
		player.rotation_degrees.y = car_yaw
	else:
		player.rotation_degrees = Vector3(0, player.rotation_degrees.y, 0)
	if is_instance_valid(player_collider) and not player_collider.disabled:
		player_collider.set_deferred("disabled", true)
	set_weapon("")
	alert_label.text = "ERWISCHT"
	prompt.text = ""
	death_fade_overlay.visible = true
	death_fade_overlay.color = Color(0, 0, 0, 0)
	player_death_phase = PlayerDeathPhase.FALLING
	death_elapsed = 0.0
	death_start_position = player.translation
	var backward = player.global_transform.basis.z
	backward.y = 0.0
	backward = backward.normalized() if backward.length() > 0.01 else Vector3(0, 0, 1)
	death_fall_position = death_start_position + backward * 1.05 + Vector3.DOWN * 0.72
	death_start_rotation = player.rotation_degrees
	death_fall_rotation = Vector3(82.0, death_start_rotation.y, death_start_rotation.z + 5.0)
	death_start_camera_rotation = camera.rotation_degrees
	update_player_death_fall_visuals()
	update_status()

func update_player_death(delta: float):
	# Consume all of delta so even a slow frame cannot skip the black hold or
	# leave the state machine between phases.
	var remaining = max(0.0, delta)
	while remaining > 0.00001 and player_dying:
		if player_death_phase == PlayerDeathPhase.FALLING:
			var fade_out_total = DEATH_FADE_DELAY + DEATH_FADE_OUT_DURATION
			var fall_step = min(remaining, fade_out_total - death_elapsed)
			death_elapsed += fall_step
			remaining -= fall_step
			update_player_death_fall_visuals()
			if death_elapsed >= fade_out_total - 0.00001:
				set_death_fade_alpha(1.0)
				player_death_phase = PlayerDeathPhase.BLACK_HOLD
				death_elapsed = 0.0
				commit_player_respawn()
		elif player_death_phase == PlayerDeathPhase.BLACK_HOLD:
			var hold_step = min(remaining, DEATH_BLACK_HOLD_DURATION - death_elapsed)
			death_elapsed += hold_step
			remaining -= hold_step
			set_death_fade_alpha(1.0)
			if death_elapsed >= DEATH_BLACK_HOLD_DURATION - 0.00001:
				player_death_phase = PlayerDeathPhase.FADE_IN
				death_elapsed = 0.0
		elif player_death_phase == PlayerDeathPhase.FADE_IN:
			var fade_in_step = min(remaining, DEATH_FADE_IN_DURATION - death_elapsed)
			death_elapsed += fade_in_step
			remaining -= fade_in_step
			var fade_in_progress = clamp(death_elapsed / DEATH_FADE_IN_DURATION, 0.0, 1.0)
			set_death_fade_alpha(pow(1.0 - fade_in_progress, 2.0))
			if death_elapsed >= DEATH_FADE_IN_DURATION - 0.00001:
				complete_player_respawn()
		else:
			complete_player_respawn()

func update_player_death_fall_visuals():
	var fall_progress = clamp(death_elapsed / DEATH_FALL_DURATION, 0.0, 1.0)
	var fall_eased = pow(fall_progress, 3.0)
	player.translation = death_start_position.linear_interpolate(death_fall_position, fall_eased)
	player.rotation_degrees = death_start_rotation.linear_interpolate(death_fall_rotation, fall_eased)
	var camera_progress = clamp(death_elapsed / 0.65, 0.0, 1.0)
	var camera_eased = 1.0 - pow(1.0 - camera_progress, 2.0)
	camera.rotation_degrees = death_start_camera_rotation.linear_interpolate(Vector3(0, 0, -4), camera_eased)
	var fade_progress = clamp((death_elapsed - DEATH_FADE_DELAY) / DEATH_FADE_OUT_DURATION, 0.0, 1.0)
	set_death_fade_alpha(pow(fade_progress, 2.0))

func set_death_fade_alpha(alpha: float):
	var fade_color = death_fade_overlay.color
	fade_color.a = clamp(alpha, 0.0, 1.0)
	death_fade_overlay.color = fade_color

func commit_player_respawn():
	# Reset behind the opaque overlay so the teleport is never visible.
	player.global_transform = Transform(Basis(), Vector3(3, 4, 8))
	player.rotation_degrees = Vector3.ZERO
	camera.rotation_degrees = Vector3.ZERO
	look_x = 0.0
	velocity = Vector3.ZERO
	player_health = 100
	# The state update runs before movement in _physics_process(), so enabling the
	# collider here is deterministic before controls can unlock.
	if is_instance_valid(player_collider):
		player_collider.disabled = false
		player_collider.set_deferred("disabled", false)
	alert_label.text = "ERWISCHT – ZURÜCK AM START"
	update_status()

func complete_player_respawn():
	death_fade_overlay.color = Color(0, 0, 0, 0)
	death_fade_overlay.visible = false
	player_death_phase = PlayerDeathPhase.ALIVE
	death_elapsed = 0.0
	player_dying = false
	update_status()

func update_damage_feedback(delta: float):
	if not is_instance_valid(damage_overlay):
		return
	damage_flash_time = max(0.0, damage_flash_time - delta)
	var overlay_color = damage_overlay.color
	overlay_color.a = clamp(damage_flash_time / 0.38, 0.0, 1.0) * 0.32
	damage_overlay.color = overlay_color

func spawn_firefighters(vehicle_position: Vector3, incident: Vector3):
	for side in [-1, 1]:
		var firefighter = Spatial.new()
		firefighter.name = "Firefighter"
		firefighter.translation = Vector3(vehicle_position.x + side * 1.5, 0.05, vehicle_position.z)
		var human = HUMAN_SCENE.instance()
		firefighter.add_child(human)
		add_box(firefighter, "SafetyJacket", Vector3(0, 1.05, 0), Vector3(0.76, 0.62, 0.44), Color("d7bf21"), false)
		add_box(firefighter, "ReflectiveStripe", Vector3(0, 1.0, -0.24), Vector3(0.70, 0.10, 0.03), Color("eff6dc"), false)
		add_child(firefighter)
	var hose = ImmediateGeometry.new()
	hose.name = "WaterHose"
	var hose_material = SpatialMaterial.new()
	hose_material.flags_unshaded = true
	hose_material.vertex_color_use_as_albedo = true
	hose.material_override = hose_material
	add_child(hose)
	hose.begin(Mesh.PRIMITIVE_LINES)
	hose.set_color(Color("75cfff"))
	hose.add_vertex(vehicle_position + Vector3.UP)
	hose.add_vertex(incident + Vector3.UP * 2.0)
	hose.end()
	get_tree().create_timer(5.0).connect("timeout", self, "extinguish_fire", [incident, hose])

func extinguish_fire(incident: Vector3, hose):
	if is_instance_valid(hose):
		hose.queue_free()
	for child in get_children():
		if child.name.begins_with("Rubble_") and child.global_transform.origin.distance_to(incident) < 12.0:
			for rubble_child in child.get_children():
				if rubble_child.name.begins_with("Fire"):
					rubble_child.queue_free()
	alert_label.text = "BRAND GELÖSCHT"

func show_shot_trace(from: Vector3, to: Vector3):
	var tracer = ImmediateGeometry.new()
	tracer.name = "BulletTracer"
	var tracer_material = SpatialMaterial.new()
	tracer_material.flags_unshaded = true
	tracer_material.vertex_color_use_as_albedo = true
	tracer_material.emission_enabled = true
	tracer_material.emission = Color("ffd75a")
	tracer.material_override = tracer_material
	add_child(tracer)
	tracer.begin(Mesh.PRIMITIVE_LINES)
	tracer.set_color(Color("fff3a1"))
	tracer.add_vertex(from)
	tracer.set_color(Color("ff9f22"))
	tracer.add_vertex(to)
	tracer.end()
	get_tree().create_timer(0.09).connect("timeout", tracer, "queue_free")

func show_impact(position: Vector3, normal: Vector3):
	var impact = add_sphere(self, "BulletImpact", position + normal * 0.035, 0.075, Color("ffb32f"))
	get_tree().create_timer(0.45).connect("timeout", impact, "queue_free")

func update_status():
	var weapon_name = "keine"
	if equipped_weapon == "pistol":
		weapon_name = "Pistole"
	elif equipped_weapon == "rifle":
		weapon_name = "Sturmgewehr"
	elif equipped_weapon == "bazooka":
		weapon_name = "Raketenwerfer"
	var ammo_text = ""
	if equipped_weapon != "" and ammo_in_mag.has(equipped_weapon):
		ammo_text = " %d/%d" % [int(ammo_in_mag[equipped_weapon]), int(ammo_reserve[equipped_weapon])]
		if equipped_weapon == "rifle":
			ammo_text += " %s" % ("AUTO" if rifle_fire_mode == "auto" else "EINZEL")
		if reload_remaining > 0.0:
			ammo_text += " · NACHLADEN %.1fs" % reload_remaining
	var wanted_text = ""
	if wanted_level > 0:
		var stars = ""
		for _star in range(wanted_level):
			stars += "★"
		wanted_text = " | FAHNDUNG %s" % stars
	var vehicle_text = ""
	if in_car:
		vehicle_text = " | BENZIN %d%% | AUTO %d%%" % [int(ceil(car_fuel)), car_health]
	status.text = ("IM AUTO" if in_car else "ZU FUSS") + " | HP %d%s%s | Waffe: %s%s" % [player_health, vehicle_text, wanted_text, weapon_name, ammo_text]
