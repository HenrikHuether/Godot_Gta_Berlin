extends Spatial

const BERLIN_MAP_SCENE = preload("res://scenes/BerlinSegmentedMap.tscn")
const HUMAN_SCENE = preload("res://Assets/HumanV2.glb")
const GOLF_SCENE = preload("res://Assets/Golf7ModelV3.glb")
const HLF_SCENE = preload("res://Assets/Vehicles/Feuerwehr_HLF.glb")
const EC135_SCENE = preload("res://Assets/Helicopters/EC135.glb")
const PLAYER_VEHICLE_SCENE = preload("res://scenes/PlayerVehicle.tscn")
const PLAYER_HELICOPTER_SCENE = preload("res://scenes/PlayerHelicopter.tscn")
const MISSION_ONE_SCRIPT = preload("res://scripts/mission_one.gd")
const GOLF_VISUAL_SCALE = 0.65
const GOLF_VISUAL_OFFSET = Vector3(0.0, -0.52, 0.0)
const GOLF_COLLIDER_EXTENTS = Vector3(1.06, 0.72, 2.14)
const GOLF_GROUND_HEIGHT = 0.72
const HLF_VISUAL_OFFSET = Vector3(0.0, -0.5318517, -2.654151)
const HLF_COLLIDER_EXTENTS = Vector3(1.15, 1.25, 3.70)
const HLF_COLLIDER_OFFSET = Vector3(0.0, 0.73, 0.0)
const HLF_TIRE_BOTTOM_LOCAL_Y = 0.00685
const HLF_ROAD_SURFACE_Y = 0.05
const HLF_GROUND_HEIGHT = 0.57
const HLF_FRONT_LIGHT_POSITION = Vector3(0.0113, 2.6606, 0.7325)
const HLF_REAR_LIGHT_LEFT_POSITION = Vector3(-0.7865, 2.7684, -5.3798)
const HLF_REAR_LIGHT_RIGHT_POSITION = Vector3(0.7836, 2.7684, -5.3798)
const HLF_BLUE_EMISSION_ENERGY = 5.5
const HLF_BLUE_LIGHT_ENERGY = 2.4
const EC135_VISUAL_SCALE = 0.1724221
const EC135_VISUAL_OFFSET = Vector3(0.0, 141.6558, 0.76277)
const EC135_GROUND_HEIGHT = 1.50
const EC135_SPAWN_POSITION = Vector3(0.0, 8.0, 26.0)
const EC135_COCKPIT_POSITION = Vector3(0.38, -0.30, -1.90)
const EC135_GLASS_ALPHA = 0.18
const CAMERA_EYE_OFFSET = Vector3(0.0, 0.65, 0.0)
const FIRE_SUPPRESSION_DURATION = 300.0
const FIRE_ENGINE_ARRIVAL_DISTANCE = 6.0
const EMERGENCY_LANE_OFFSET = 3.0
const FIREFIGHTER_SIDE_DISTANCE = 2.10
const FIREFIGHTER_FOOT_HEIGHT = 0.07
const WATER_SPRAY_SEGMENTS = 14
const WATER_DROPLET_COUNT = 7
const WALK_SPEED = 8.0
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
var car: RigidBody
var car_body: Spatial
var helicopter: RigidBody
var helicopter_body: Spatial
var helicopter_cockpit_anchor: Spatial
var helicopter_audio: AudioStreamPlayer3D
var weapon_pivot: Spatial
var pistol_model: Spatial
var bazooka_model: Spatial
var rifle_model: Spatial
var velocity = Vector3.ZERO
var car_speed = 0.0
var look_x = 0.0
var helicopter_look_yaw = 0.0
var in_car = false
var in_helicopter = false
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
# Kept as a null compatibility field while older tests and callers migrate away
# from the removed procedural expansion.
var map_expansion
var berlin_map
var car_fuel = 38.0
var car_health = 100
var car_damage_cooldown = 0.0
var helicopter_health = 180
var helicopter_damage_cooldown = 0.0
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
var firefighting_operations = []

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	build_world()
	configure_driving_surfaces()
	build_player()
	build_audio()
	build_car()
	build_helicopter()
	build_npcs()
	build_ui()
	tag_destructible_buildings(berlin_map)
	mission_one = MISSION_ONE_SCRIPT.new()
	mission_one.name = "MissionOne"
	add_child(mission_one)
	mission_one.setup(self)
	update_status()

func build_audio():
	# Procedural samples keep the prototype self-contained while still providing
	# distinct gunshots, launch, explosion, vehicle and emergency sounds.
	sound_streams["pistol"] = create_sound_sample("pistol", 0.16)
	sound_streams["rifle"] = create_sound_sample("rifle", 0.11)
	sound_streams["police_pistol"] = create_sound_sample("police_pistol", 0.14)
	sound_streams["rocket"] = create_sound_sample("rocket", 0.34)
	sound_streams["explosion"] = create_sound_sample("explosion", 0.95)
	sound_streams["fire"] = create_sound_sample("fire", 1.20, true)
	sound_streams["fire_engine"] = create_sound_sample("fire_engine", 1.0, true)
	sound_streams["martinshorn"] = create_sound_sample("martinshorn", 2.4, true)
	sound_streams["helicopter"] = create_sound_sample("helicopter", 1.0, true)

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
		elif kind == "fire":
			var crackle = 1.0 if noise > 0.72 else noise * 0.28
			var loop_fade = min(1.0, min(progress * 18.0, (1.0 - progress) * 18.0))
			wave = (crackle * 0.55 + sin(time * PI * 2.0 * 74.0) * 0.10) * loop_fade
		elif kind == "fire_engine":
			# Integer harmonics and modulation cycles make this a seamless diesel loop.
			var engine_pulse = 0.78 + sin(time * PI * 2.0 * 4.0) * 0.12
			wave = (
				sin(time * PI * 2.0 * 48.0) * 0.36
				+ sin(time * PI * 2.0 * 96.0 + 0.42) * 0.20
				+ sin(time * PI * 2.0 * 144.0 + 0.18) * 0.11
				+ sin(time * PI * 2.0 * 240.0) * 0.045
			) * engine_pulse
		elif kind == "helicopter":
			# Four-blade rotor pulse plus gearbox/turbine harmonics. Integer
			# frequencies keep the one-second sample seamless when it loops.
			var blade_pulse = 0.78 + sin(time * PI * 2.0 * 4.0) * 0.16
			wave = (
				sin(time * PI * 2.0 * 13.0) * 0.20
				+ sin(time * PI * 2.0 * 26.0) * 0.38
				+ sin(time * PI * 2.0 * 52.0 + 0.35) * 0.18
				+ sin(time * PI * 2.0 * 156.0) * 0.08
				+ noise * 0.025
			) * blade_pulse
		elif kind == "martinshorn":
			# Four pneumatic bells recreate the paired pipes and characteristic beat of
			# a classic German Martinshorn. Independent valve envelopes add the short
			# pressure dip between notes and also make the 2.4-second loop seamless.
			var horn_cycle = fmod(time, 1.2)
			var low_gate = martinshorn_note_gate(horn_cycle)
			var high_gate = martinshorn_note_gate(horn_cycle - 0.6)
			var low_horn = martinshorn_horn_voice(435.0, time) * 0.56 + martinshorn_horn_voice(450.0, time) * 0.44
			var high_horn = martinshorn_horn_voice(580.0, time) * 0.56 + martinshorn_horn_voice(600.0, time) * 0.44
			var pressure = 0.97 + sin(time * PI * 2.0 * 5.0 + 0.3) * 0.025 + sin(time * PI * 2.0 * 10.0 + 1.1) * 0.012
			var active_gate = low_gate + high_gate
			var air_noise = noise * 0.008 * active_gate * (1.0 - active_gate * 0.5)
			wave = (low_horn * low_gate + high_horn * high_gate) * pressure * 0.76 + air_noise
		else:
			wave = 0.0
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

func martinshorn_note_gate(local_time: float) -> float:
	if local_time < 0.0 or local_time >= 0.6:
		return 0.0
	if local_time < 0.028:
		return smoothstep_unit(local_time / 0.028)
	if local_time > 0.558:
		return 1.0 - smoothstep_unit((local_time - 0.558) / 0.042)
	return 1.0

func martinshorn_horn_voice(frequency: float, time: float) -> float:
	var phase = time * PI * 2.0 * frequency
	return (
		sin(phase) * 0.64
		+ sin(phase * 2.0 + 0.10) * 0.205
		+ sin(phase * 3.0 + 0.35) * 0.09
		+ sin(phase * 4.0 + 0.20) * 0.04
		+ sin(phase * 5.0 + 0.55) * 0.018
	)

func smoothstep_unit(value: float) -> float:
	var bounded = clamp(value, 0.0, 1.0)
	return bounded * bounded * (3.0 - 2.0 * bounded)

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

func add_cylinder_between(parent: Spatial, name: String, start: Vector3, finish: Vector3, radius: float, color: Color):
	var offset = finish - start
	if offset.length_squared() < 0.000001:
		return null
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = name
	mesh_instance.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = offset.length()
	mesh.radial_segments = 10
	mesh.material = material(color)
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	# CylinderMesh is authored along +Y. Build a stable orthonormal basis whose
	# Y axis follows the hose/nozzle segment, including near-vertical segments.
	var y_axis = offset.normalized()
	var reference_axis = Vector3.FORWARD if abs(y_axis.dot(Vector3.FORWARD)) < 0.96 else Vector3.RIGHT
	var x_axis = reference_axis.cross(y_axis).normalized()
	var z_axis = x_axis.cross(y_axis).normalized()
	mesh_instance.global_transform = Transform(Basis(x_axis, y_axis, z_axis), (start + finish) * 0.5)
	return mesh_instance

func build_world():
	var sun = DirectionalLight.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	berlin_map = get_node_or_null("BerlinMap")
	if not berlin_map:
		berlin_map = BERLIN_MAP_SCENE.instance()
		berlin_map.name = "BerlinMap"
		add_child(berlin_map)
	if berlin_map.has_method("setup"):
		berlin_map.setup(self)

func get_berlin_map():
	if is_instance_valid(berlin_map):
		return berlin_map
	berlin_map = get_node_or_null("BerlinMap")
	return berlin_map

func get_map_spawn_transform(spawn_id: String, fallback: Transform) -> Transform:
	var map = get_berlin_map()
	if not is_instance_valid(map) or not map.has_method("get_spawn_transform"):
		return fallback
	var spawn_value = map.get_spawn_transform(spawn_id)
	if typeof(spawn_value) == TYPE_TRANSFORM:
		return spawn_value
	if typeof(spawn_value) == TYPE_VECTOR3:
		var position_transform = fallback
		position_transform.origin = spawn_value
		return position_transform
	if typeof(spawn_value) == TYPE_DICTIONARY:
		if spawn_value.has("transform") and typeof(spawn_value["transform"]) == TYPE_TRANSFORM:
			return spawn_value["transform"]
		var dictionary_transform = fallback
		if spawn_value.has("position") and typeof(spawn_value["position"]) == TYPE_VECTOR3:
			dictionary_transform.origin = spawn_value["position"]
		if spawn_value.has("basis") and typeof(spawn_value["basis"]) == TYPE_BASIS:
			dictionary_transform.basis = spawn_value["basis"]
		return dictionary_transform
	return fallback

func map_surface_ray(origin: Vector3, excluded := []):
	var top_y = max(origin.y + 50.0, 150.0)
	var bottom_y = min(origin.y - 60.0, -60.0)
	var map = get_berlin_map()
	if is_instance_valid(map) and map.has_method("get_map_bounds"):
		var bounds = map.get_map_bounds()
		if typeof(bounds) == TYPE_AABB:
			top_y = max(top_y, bounds.position.y + bounds.size.y + 30.0)
			bottom_y = min(bottom_y, bounds.position.y - 30.0)
	return get_world().direct_space_state.intersect_ray(
		Vector3(origin.x, top_y, origin.z),
		Vector3(origin.x, bottom_y, origin.z),
		excluded
	)

func build_player():
	player = KinematicBody.new()
	player.name = "Player"
	player.collision_layer = 1
	player.collision_mask = 1
	player.transform = get_map_spawn_transform(
		"player",
		Transform(Basis(), Vector3(3, 8, 8))
	)
	player_collider = CollisionShape.new()
	player_collider.name = "CollisionShape"
	var capsule = CapsuleShape.new()
	capsule.radius = 0.45
	capsule.height = 1.70
	player_collider.shape = capsule
	player.add_child(player_collider)
	camera = Camera.new()
	camera.translation = CAMERA_EYE_OFFSET
	camera.far = 10000.0
	camera.current = true
	camera.doppler_tracking = Camera.DOPPLER_TRACKING_PHYSICS_STEP
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
	car = PLAYER_VEHICLE_SCENE.instance()
	car.name = "Car"
	car.transform = get_map_spawn_transform(
		"car",
		Transform(Basis(), Vector3(2.8, 8, -4))
	)
	register_damageable_vehicle(car, 100, "player_car")
	car_body = add_golf_visual(car)
	add_child(car)
	car.bind_wheel_visuals(car_body.get_node_or_null("Golf7Model"), GOLF_VISUAL_SCALE)
	car.set_driver_active(false)
	car.connect("hard_impact", self, "_on_car_hard_impact")
	call_deferred("place_car_on_ground")

func build_helicopter():
	helicopter = PLAYER_HELICOPTER_SCENE.instance()
	helicopter.name = "EC135"
	helicopter.transform = get_map_spawn_transform(
		"helicopter",
		Transform(Basis(), EC135_SPAWN_POSITION)
	)
	helicopter_cockpit_anchor = Spatial.new()
	helicopter_cockpit_anchor.name = "CockpitAnchor"
	helicopter_cockpit_anchor.translation = EC135_COCKPIT_POSITION
	helicopter.add_child(helicopter_cockpit_anchor)
	register_damageable_vehicle(helicopter, helicopter_health, "player_helicopter")
	helicopter_body = add_ec135_visual(helicopter)
	add_child(helicopter)
	helicopter.bind_visuals(helicopter_body.get_node_or_null("EC135Model"))
	helicopter.set_driver_active(false)
	helicopter.set_engine_enabled(false)
	helicopter.connect("rotor_destroyed", self, "_on_helicopter_rotor_destroyed")
	helicopter.connect("hard_impact", self, "_on_helicopter_hard_impact")
	helicopter.connect("fatal_crash", self, "_on_helicopter_fatal_crash")
	add_helicopter_audio(helicopter)
	call_deferred("place_helicopter_on_ground")

func add_ec135_visual(parent: Node) -> Spatial:
	# The source scene uses a large Sketchfab offset and a 60.317 m imported
	# rotor disk. This wrapper recentres it and calibrates the disk to 10.40 m.
	var visual = Spatial.new()
	visual.name = "EC135Visual"
	visual.translation = EC135_VISUAL_OFFSET
	visual.scale = Vector3.ONE * EC135_VISUAL_SCALE
	parent.add_child(visual)
	var model = EC135_SCENE.instance()
	model.name = "EC135Model"
	visual.add_child(model)
	configure_ec135_materials(model)
	# The player's camera occupies the left cockpit seat. Hiding both supplied
	# pilots prevents duplicate occupants and removes their draw calls.
	for pilot_name in ["ResucePilot_Final1", "ResucePilot_Final2"]:
		var pilot = model.find_node(pilot_name, true, false)
		if pilot:
			pilot.visible = false
	return visual

func configure_ec135_materials(node: Node):
	if node is MeshInstance and node.mesh:
		for surface_index in range(node.mesh.get_surface_count()):
			var source_material = node.get_surface_material(surface_index)
			if source_material == null:
				source_material = node.mesh.surface_get_material(surface_index)
			if not (source_material is SpatialMaterial) or source_material.resource_name != "EC135_Glass_Mat":
				continue
			# The imported GLB uses a 74%-opaque alpha-prepass material. In GLES2
			# that depth pass masks the world behind the canopy, especially from
			# the cockpit. Preserve its textures/tint but use true two-sided glass
			# that neither writes an opaque depth silhouette nor blocks the view.
			var glass_material = source_material.duplicate(true) as SpatialMaterial
			glass_material.resource_name = "EC135_Glass_Clear"
			var glass_color = glass_material.albedo_color
			glass_color.a = EC135_GLASS_ALPHA
			glass_material.albedo_color = glass_color
			glass_material.flags_transparent = true
			glass_material.params_blend_mode = SpatialMaterial.BLEND_MODE_MIX
			glass_material.params_cull_mode = SpatialMaterial.CULL_DISABLED
			glass_material.params_depth_draw_mode = SpatialMaterial.DEPTH_DRAW_DISABLED
			glass_material.metallic = 0.0
			glass_material.roughness = 0.08
			node.set_surface_material(surface_index, glass_material)
	for child in node.get_children():
		configure_ec135_materials(child)

func add_helicopter_audio(vehicle: Node):
	if not sound_streams.has("helicopter"):
		sound_streams["helicopter"] = create_sound_sample("helicopter", 1.0, true)
	helicopter_audio = AudioStreamPlayer3D.new()
	helicopter_audio.name = "RotorAudio"
	helicopter_audio.stream = sound_streams["helicopter"]
	helicopter_audio.unit_db = -40.0
	helicopter_audio.max_distance = 420.0
	helicopter_audio.unit_size = 18.0
	helicopter_audio.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
	helicopter_audio.out_of_range_mode = AudioStreamPlayer3D.OUT_OF_RANGE_PAUSE
	vehicle.add_child(helicopter_audio)
	helicopter_audio.play()

func update_helicopter_audio():
	if not is_instance_valid(helicopter_audio) or not is_instance_valid(helicopter):
		return
	var rotor_ratio = clamp(helicopter.get_rotor_rpm() / helicopter.NOMINAL_ROTOR_RPM, 0.0, 1.10)
	helicopter_audio.unit_db = lerp(-40.0, -3.5, sqrt(rotor_ratio))
	helicopter_audio.pitch_scale = 0.48 + rotor_ratio * 0.68

func add_golf_visual(parent: Node, police_variant := false) -> Spatial:
	# The supplied GLB points toward +Z. Rotate its visual wrapper so it follows
	# the driving code's -Z forward convention, and scale it to real Golf size.
	var visual = Spatial.new()
	visual.name = "Golf7Visual"
	visual.translation = GOLF_VISUAL_OFFSET
	visual.rotation_degrees.y = 180.0
	visual.scale = Vector3.ONE * GOLF_VISUAL_SCALE
	parent.add_child(visual)
	var model = GOLF_SCENE.instance()
	model.name = "Golf7Model"
	visual.add_child(model)
	configure_golf_materials(model, police_variant)
	return visual

func configure_golf_materials(node: Node, police_variant: bool):
	if node is MeshInstance and node.mesh:
		for surface_index in range(node.mesh.get_surface_count()):
			var source_material = node.mesh.surface_get_material(surface_index)
			var material_name = source_material.resource_name if source_material else ""
			# The source has one deliberately unassigned detail surface. Give it an
			# explicit metallic trim color so its appearance is renderer-independent.
			if not source_material and node.name == "Auto":
				var trim = material(Color("d9dcdd"))
				trim.roughness = 0.32
				trim.metallic = 0.58
				node.set_surface_material(surface_index, trim)
			elif police_variant and (material_name == "Carosse" or (node.name == "Auto" and surface_index == 1)):
				var police_paint = material(Color("dfe3e5"))
				police_paint.roughness = 0.34
				police_paint.metallic = 0.22
				node.set_surface_material(surface_index, police_paint)
	for child in node.get_children():
		configure_golf_materials(child, police_variant)

func add_golf_collision(vehicle: PhysicsBody) -> CollisionShape:
	var collider = CollisionShape.new()
	collider.name = "CollisionShape"
	var shape = BoxShape.new()
	shape.extents = GOLF_COLLIDER_EXTENTS
	collider.shape = shape
	collider.translation.y = HLF_ROAD_SURFACE_Y
	vehicle.add_child(collider)
	return collider

func add_hlf_visual(parent: Node) -> Spatial:
	# The supplied HLF is already authored in metres, but its front points toward
	# +Z and its pivot sits near the front axle. Centre it and match Godot's -Z
	# vehicle-forward convention without modifying the source asset.
	var visual = Spatial.new()
	visual.name = "HLFVisual"
	visual.translation = HLF_VISUAL_OFFSET
	visual.rotation_degrees.y = 180.0
	parent.add_child(visual)
	var model = HLF_SCENE.instance()
	model.name = "HLFModel"
	visual.add_child(model)
	configure_hlf_blue_light(model, "Blaulicht_Vorne")
	configure_hlf_blue_light(model, "Blaulicht_Hinten")
	add_hlf_flash_light(model, "BlueFlashLightFront", HLF_FRONT_LIGHT_POSITION, HLF_BLUE_LIGHT_ENERGY)
	add_hlf_flash_light(model, "BlueFlashLightRearLeft", HLF_REAR_LIGHT_LEFT_POSITION, HLF_BLUE_LIGHT_ENERGY * 0.72)
	add_hlf_flash_light(model, "BlueFlashLightRearRight", HLF_REAR_LIGHT_RIGHT_POSITION, HLF_BLUE_LIGHT_ENERGY * 0.72)
	return visual

func configure_hlf_blue_light(model: Node, mesh_name: String):
	var light_mesh = model.find_node(mesh_name, true, false)
	if not (light_mesh is MeshInstance) or not light_mesh.mesh:
		return null
	var blue_surface = -1
	for surface_index in range(light_mesh.mesh.get_surface_count()):
		var source_material = light_mesh.mesh.surface_get_material(surface_index)
		var material_name = source_material.resource_name if source_material else ""
		if material_name.to_lower().find("blaulicht") >= 0:
			blue_surface = surface_index
			break
	# Both designated HLF beacon meshes use their first surface for blue glass.
	# The fallback also keeps the setup robust if the importer drops material names.
	if blue_surface < 0 and light_mesh.mesh.get_surface_count() > 0:
		blue_surface = 0
	if blue_surface < 0:
		return null
	var light_material = SpatialMaterial.new()
	light_material.resource_name = "%s_Emission" % mesh_name
	light_material.albedo_color = Color("0a35b8")
	light_material.roughness = 0.16
	light_material.emission_enabled = true
	light_material.emission = Color("126dff")
	light_material.emission_energy = 0.05
	light_mesh.set_surface_material(blue_surface, light_material)
	light_mesh.set_meta("blue_light_surface", blue_surface)
	light_mesh.set_meta("blue_light_material", light_material)

	return light_mesh

func add_hlf_flash_light(model: Node, light_name: String, light_position: Vector3, energy: float):
	# Model-level placement uses the actual optical centres. The rear beacon mesh
	# contains two separate lenses, so each receives its own synchronized light.
	var flash_light = OmniLight.new()
	flash_light.name = light_name
	flash_light.translation = light_position
	flash_light.light_color = Color("176dff")
	flash_light.light_energy = energy
	flash_light.omni_range = 9.5
	flash_light.shadow_enabled = false
	flash_light.visible = false
	model.add_child(flash_light)
	return flash_light

func add_hlf_collision(vehicle: KinematicBody) -> CollisionShape:
	var collider = CollisionShape.new()
	collider.name = "CollisionShape"
	var shape = BoxShape.new()
	shape.extents = HLF_COLLIDER_EXTENTS
	collider.shape = shape
	collider.translation = HLF_COLLIDER_OFFSET
	vehicle.add_child(collider)
	return collider

func set_hlf_blue_lights(vehicle: Node, front_on: bool, rear_on: bool):
	var model = vehicle.get_node_or_null("HLFVisual/HLFModel")
	if not model:
		return
	set_hlf_blue_light(model.find_node("Blaulicht_Vorne", true, false), front_on)
	set_hlf_blue_light(model.find_node("Blaulicht_Hinten", true, false), rear_on)
	set_hlf_flash_light(model.get_node_or_null("BlueFlashLightFront"), front_on)
	set_hlf_flash_light(model.get_node_or_null("BlueFlashLightRearLeft"), rear_on)
	set_hlf_flash_light(model.get_node_or_null("BlueFlashLightRearRight"), rear_on)

func set_hlf_blue_light(light_mesh, enabled: bool):
	if not (light_mesh is MeshInstance) or not light_mesh.has_meta("blue_light_material"):
		return
	var light_material = light_mesh.get_meta("blue_light_material")
	if light_material is SpatialMaterial:
		light_material.albedo_color = Color("238dff") if enabled else Color("0a35b8")
		light_material.emission = Color("36a4ff") if enabled else Color("0b2b72")
		light_material.emission_energy = HLF_BLUE_EMISSION_ENERGY if enabled else 0.05

func set_hlf_flash_light(flash_light, enabled: bool):
	if flash_light is OmniLight:
		flash_light.visible = enabled

func add_fire_engine_audio(vehicle: Node):
	# Generate the loops lazily too, so the factory remains safe in preview and
	# isolated test scenes that do not call the main build sequence first.
	if not sound_streams.has("fire_engine"):
		sound_streams["fire_engine"] = create_sound_sample("fire_engine", 1.0, true)
	if not sound_streams.has("martinshorn"):
		sound_streams["martinshorn"] = create_sound_sample("martinshorn", 2.4, true)
	var audio_setup = [
		["EngineAudio", "fire_engine", -8.0, 105.0, 1.08, 7.0],
		["MartinshornAudio", "martinshorn", -3.0, 230.0, 1.0, 24.0]
	]
	for setup in audio_setup:
		var audio = AudioStreamPlayer3D.new()
		audio.name = setup[0]
		audio.stream = sound_streams[setup[1]]
		audio.unit_db = float(setup[2])
		audio.max_distance = float(setup[3])
		audio.pitch_scale = float(setup[4])
		audio.unit_size = float(setup[5])
		if str(setup[0]) == "MartinshornAudio":
			# Keep the cadence running while inaudible, then add motion and a broad
			# forward radiation pattern like roof/front-mounted pneumatic horns.
			audio.out_of_range_mode = AudioStreamPlayer3D.OUT_OF_RANGE_MIX
			audio.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
			audio.emission_angle_enabled = true
			audio.emission_angle_degrees = 80.0
			audio.emission_angle_filter_attenuation_db = -6.0
		else:
			audio.out_of_range_mode = AudioStreamPlayer3D.OUT_OF_RANGE_PAUSE
		audio.autoplay = true
		vehicle.add_child(audio)
		audio.play()

func stop_fire_engine_audio(vehicle: Node):
	for audio_name in ["EngineAudio", "MartinshornAudio"]:
		var audio = vehicle.get_node_or_null(audio_name)
		if audio is AudioStreamPlayer3D:
			audio.stop()

func add_police_golf_livery(vehicle: KinematicBody):
	add_box(vehicle, "LightbarBase", Vector3(0, 0.76, 0), Vector3(1.14, 0.08, 0.30), Color("222a31"), false)
	for side in [-1, 1]:
		add_box(vehicle, "BlueSideStripe", Vector3(side * 1.065, -0.04, 0.05), Vector3(0.035, 0.28, 2.90), Color("1765a2"), false)
		add_box(vehicle, "PoliceDoorPanel", Vector3(side * 1.087, 0.00, 0.05), Vector3(0.018, 0.20, 1.08), Color("edf0f0"), false)
		var door_label = Label3D.new()
		door_label.name = "PoliceDoorLabelLeft" if side < 0 else "PoliceDoorLabelRight"
		door_label.text = "POLIZEI"
		door_label.translation = Vector3(side * 1.105, 0.00, 0.05)
		door_label.rotation_degrees.y = float(side) * 90.0
		door_label.pixel_size = 0.012
		door_label.modulate = Color("175f98")
		vehicle.add_child(door_label)

func place_car_on_ground():
	var origin = car.global_transform.origin
	var excluded = [car]
	if player:
		excluded.append(player)
	var hit = map_surface_ray(origin, excluded)
	if hit:
		var target_transform = car.global_transform
		target_transform.origin.y = hit.position.y + GOLF_GROUND_HEIGHT
		teleport_vehicle(car, target_transform)

func place_helicopter_on_ground():
	if not is_instance_valid(helicopter):
		return
	var origin = helicopter.global_transform.origin
	var excluded = [helicopter]
	if is_instance_valid(player):
		excluded.append(player)
	if is_instance_valid(car):
		excluded.append(car)
	var hit = map_surface_ray(origin, excluded)
	if hit:
		var target_transform = helicopter.global_transform
		target_transform.origin.y = hit.position.y + EC135_GROUND_HEIGHT
		teleport_vehicle(helicopter, target_transform)

func teleport_vehicle(vehicle, target_transform: Transform, reset_motion := true):
	if not is_instance_valid(vehicle):
		return
	if vehicle.has_method("teleport_to"):
		vehicle.teleport_to(target_transform, reset_motion)
	else:
		vehicle.global_transform = target_transform
		if reset_motion and vehicle is RigidBody:
			vehicle.linear_velocity = Vector3.ZERO
			vehicle.angular_velocity = Vector3.ZERO

func configure_driving_surfaces():
	var map = get_berlin_map()
	if not is_instance_valid(map):
		return
	# The segmented-map wrapper owns all visual and collision generation. Main
	# only supplies fallback vehicle coefficients where a semantic collider did
	# not already provide authored values.
	_tag_static_surfaces(map)

func _tile_large_static_box(body: StaticBody, max_tile_size := 180.0):
	var source_collider = body.get_node_or_null("CollisionShape")
	if not (source_collider is CollisionShape) or not (source_collider.shape is BoxShape):
		return
	var source_size = source_collider.shape.extents * 2.0
	var tile_count_x = max(1, int(ceil(source_size.x / max_tile_size)))
	var tile_count_z = max(1, int(ceil(source_size.z / max_tile_size)))
	if tile_count_x == 1 and tile_count_z == 1:
		return
	var tile_size = Vector3(source_size.x / tile_count_x, source_size.y, source_size.z / tile_count_z)
	source_collider.disabled = true
	for tile_x in range(tile_count_x):
		for tile_z in range(tile_count_z):
			var tile_collider = CollisionShape.new()
			tile_collider.name = "DrivingCollisionTile_%02d_%02d" % [tile_x, tile_z]
			tile_collider.translation = source_collider.translation + Vector3(
				-source_size.x * 0.5 + tile_size.x * (float(tile_x) + 0.5),
				0.0,
				-source_size.z * 0.5 + tile_size.z * (float(tile_z) + 0.5)
			)
			var tile_shape = BoxShape.new()
			tile_shape.extents = tile_size * 0.5
			tile_collider.shape = tile_shape
			body.add_child(tile_collider)

func _tag_static_surfaces(node: Node):
	if node is StaticBody:
		var surface_kind = _surface_kind(node)
		if surface_kind.find("road") >= 0 or surface_kind.find("street") >= 0 or surface_kind.find("asphalt") >= 0:
			if not node.has_meta("surface_grip"):
				node.set_meta("surface_grip", 1.02)
			if not node.has_meta("rolling_resistance"):
				node.set_meta("rolling_resistance", 1.0)
		elif surface_kind.find("sidewalk") >= 0 or surface_kind.find("walk") >= 0 or surface_kind.find("pavement") >= 0:
			if not node.has_meta("surface_grip"):
				node.set_meta("surface_grip", 0.78)
			if not node.has_meta("rolling_resistance"):
				node.set_meta("rolling_resistance", 1.35)
		elif surface_kind.find("ground") >= 0 or surface_kind.find("terrain") >= 0 or surface_kind.find("grass") >= 0:
			if not node.has_meta("surface_grip"):
				node.set_meta("surface_grip", 0.52)
			if not node.has_meta("rolling_resistance"):
				node.set_meta("rolling_resistance", 2.4)
		elif node.has_meta("surface_grip") and not node.has_meta("rolling_resistance"):
			node.set_meta("rolling_resistance", 1.0)
	for child in node.get_children():
		_tag_static_surfaces(child)

func _surface_kind(node: Node) -> String:
	for meta_key in ["surface_kind", "surface_type", "map_feature", "feature_kind"]:
		if node.has_meta(meta_key):
			return str(node.get_meta(meta_key)).to_lower()
	for group_name in ["map_road", "map_sidewalk", "map_ground", "map_canal", "map_building"]:
		if node.is_in_group(group_name):
			return group_name.to_lower()
	return str(node.name).to_lower()

func build_npcs():
	var positions = [Vector3(-5, 8, -8), Vector3(8, 8, 5), Vector3(-8, 8, 12)]
	for i in range(positions.size()):
		var npc = StaticBody.new()
		npc.name = "NPC_%d" % (i + 1)
		npc.transform = get_map_spawn_transform(
			"npc_%d" % (i + 1),
			Transform(Basis(), positions[i])
		)
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
	var excluded = [player, car, helicopter]
	for npc in npcs:
		excluded.append(npc)
	for npc in npcs:
		var origin = npc.global_transform.origin
		var hit = map_surface_ray(origin, excluded)
		if hit:
			var grounded_transform = npc.global_transform
			grounded_transform.origin.y = hit.position.y
			npc.global_transform = grounded_transform

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
	help.rect_position = Vector2(18, -72)
	help.text = "WASD Bewegen/Fahren  •  E Ein-/Aussteigen  •  1/2/3 Waffen  •  R Nachladen\nEC135: WASD Cyclic  •  Leertaste/X Collective  •  Q/R Pedale"
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
		look_x = clamp(look_x - event.relative.y * 0.12, -80, 80)
		if in_helicopter:
			helicopter_look_yaw = clamp(helicopter_look_yaw - event.relative.x * 0.12, -115.0, 115.0)
			camera.rotation_degrees = Vector3(look_x, helicopter_look_yaw, 0.0)
		else:
			player.rotate_y(deg2rad(-event.relative.x * 0.12))
			camera.rotation_degrees.x = look_x
	if event is InputEventMouseButton and event.pressed and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		return
	if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if event.is_action_pressed("interact"):
		if not mission_one or not mission_one.handle_interact():
			toggle_nearest_vehicle()
	if event.is_action_pressed("equip") and not is_in_vehicle():
		set_weapon("" if equipped_weapon == "pistol" else "pistol")
	if event.is_action_pressed("equip_bazooka") and not is_in_vehicle():
		set_weapon("" if equipped_weapon == "bazooka" else "bazooka")
	if event.is_action_pressed("equip_rifle") and not is_in_vehicle():
		set_weapon("" if equipped_weapon == "rifle" else "rifle")
	if event.is_action_pressed("reload") and not is_in_vehicle():
		start_reload()
	if event.is_action_pressed("toggle_fire_mode") and equipped_weapon == "rifle" and not is_in_vehicle():
		rifle_fire_mode = "semi" if rifle_fire_mode == "auto" else "auto"
		update_status()
	if event.is_action_pressed("shoot") and equipped_weapon != "" and not is_in_vehicle():
		try_fire_weapon()

func _physics_process(delta):
	car_damage_cooldown = max(0.0, car_damage_cooldown - delta)
	helicopter_damage_cooldown = max(0.0, helicopter_damage_cooldown - delta)
	if player_dying:
		update_player_death(delta)
	var controls_locked = player_dying or (mission_one and mission_one.controls_locked())
	update_weapon_system(delta, controls_locked)
	update_damage_feedback(delta)
	if not controls_locked:
		if in_helicopter:
			fly_helicopter(delta)
		elif in_car:
			drive(delta)
		else:
			walk(delta)
	elif in_car and is_instance_valid(car):
		car.set_driver_active(false)
	elif in_helicopter and is_instance_valid(helicopter):
		helicopter.set_driver_active(false)
	if in_helicopter:
		sync_player_to_helicopter()
	elif in_car:
		sync_player_to_car()
	update_helicopter_audio()
	update_emergency_vehicles(delta)
	update_police_officers(delta)
	update_vehicle_fires(delta)
	update_firefighting_operations(delta)
	if mission_one and not player_dying:
		mission_one.update_mission(delta)
	var car_distance = player.global_transform.origin.distance_to(car.global_transform.origin)
	var helicopter_distance = player.global_transform.origin.distance_to(helicopter.global_transform.origin)
	var near_car = car_distance < 3.5
	var near_helicopter = helicopter_distance < 4.3
	var car_available = can_enter_car(car_distance)
	var helicopter_available = can_enter_helicopter(helicopter_distance)
	var mission_prompt = mission_one.get_context_prompt() if mission_one else ""
	if player_dying:
		prompt.text = ""
	elif mission_prompt != "":
		prompt.text = mission_prompt
	elif in_helicopter:
		prompt.text = "[E] EC135 verlassen"
	elif in_car:
		prompt.text = "[E] Auto verlassen"
	else:
		# A nearer wreck must never hide or block another usable vehicle.
		if helicopter_available and (not car_available or helicopter_distance <= car_distance):
			prompt.text = "[E] EC135 besteigen"
		elif car_available:
			prompt.text = "[E] Auto einsteigen"
		elif near_helicopter and (not near_car or helicopter_distance <= car_distance):
			prompt.text = "EC135 ZERSTÖRT" if bool(helicopter.get_meta("destroyed")) else "EC135 NICHT FLUGFÄHIG"
		elif near_car:
			prompt.text = "FAHRZEUG ZERSTÖRT"
		else:
			prompt.text = ""

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
	var forward_input = Input.get_action_strength("move_forward")
	var reverse_input = Input.get_action_strength("move_back")
	var steering = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var handbrake = Input.get_action_strength("vehicle_handbrake")
	var forward_speed = car.get_forward_speed()
	var throttle = 0.0
	var brake = 0.0
	if forward_input > 0.01:
		if forward_speed < -0.7:
			brake = forward_input
		else:
			throttle = forward_input
	elif reverse_input > 0.01:
		if forward_speed > 0.7:
			brake = reverse_input
		else:
			throttle = -reverse_input
	if car_fuel <= 0.0 or car_health <= 0:
		throttle = 0.0
	consume_car_fuel(throttle, delta)
	car.set_driver_input(throttle, steering, brake, handbrake)
	car_speed = car.get_forward_speed()
	update_status()

func fly_helicopter(_delta):
	if not is_instance_valid(helicopter):
		return
	var cyclic_pitch = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	var cyclic_roll = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	var pedal = Input.get_action_strength("helicopter_yaw_right") - Input.get_action_strength("helicopter_yaw_left")
	var collective_axis = Input.get_action_strength("helicopter_collective_up") - Input.get_action_strength("helicopter_collective_down")
	helicopter.set_driver_input(cyclic_pitch, cyclic_roll, pedal, collective_axis)
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

func sync_player_to_car():
	if not is_instance_valid(car) or not is_instance_valid(player):
		return
	var occupant_basis = _upright_car_basis()
	var occupant_position = car.global_transform.origin + Vector3.UP * 1.2
	player.global_transform = Transform(occupant_basis, occupant_position)

func sync_player_to_helicopter():
	if not is_instance_valid(helicopter) or not is_instance_valid(player):
		return
	var occupant_basis = helicopter.global_transform.basis.orthonormalized()
	var occupant_position = helicopter.global_transform.xform(EC135_COCKPIT_POSITION)
	player.global_transform = Transform(occupant_basis, occupant_position)

func attach_camera_to_helicopter():
	if not is_instance_valid(camera) or not is_instance_valid(helicopter_cockpit_anchor):
		return
	if camera.get_parent() != helicopter_cockpit_anchor:
		var previous_parent = camera.get_parent()
		if is_instance_valid(previous_parent):
			previous_parent.remove_child(camera)
		helicopter_cockpit_anchor.add_child(camera)
	camera.translation = CAMERA_EYE_OFFSET
	camera.current = true

func attach_camera_to_player():
	if not is_instance_valid(camera) or not is_instance_valid(player):
		return
	if camera.get_parent() != player:
		var previous_parent = camera.get_parent()
		if is_instance_valid(previous_parent):
			previous_parent.remove_child(camera)
		player.add_child(camera)
	camera.translation = CAMERA_EYE_OFFSET
	camera.current = true

func _upright_car_basis() -> Basis:
	return _upright_vehicle_basis(car)

func _upright_vehicle_basis(vehicle: Spatial) -> Basis:
	var flat_forward = -vehicle.global_transform.basis.z
	flat_forward.y = 0.0
	if flat_forward.length_squared() < 0.001:
		flat_forward = Vector3(0, 0, -1)
	flat_forward = flat_forward.normalized()
	var flat_right = flat_forward.cross(Vector3.UP).normalized()
	return Basis(flat_right, Vector3.UP, -flat_forward).orthonormalized()

func _on_car_hard_impact(impact_speed: float):
	if car_health > 0:
		apply_car_impact_damage(impact_speed)

func _on_helicopter_hard_impact(impact_speed: float):
	if helicopter_health <= 0 or helicopter_damage_cooldown > 0.0:
		return
	if helicopter.has_method("is_rotor_failed") and helicopter.is_rotor_failed():
		return
	if impact_speed >= 22.0:
		# A roughly 80 km/h impact is a catastrophic airframe crash, even when
		# the rotor itself did not strike first.
		damage_vehicle(helicopter, int(helicopter.get_meta("health")))
		helicopter_damage_cooldown = 0.70
		return
	var damage = int(clamp((impact_speed - 4.5) * 5.0, 5.0, 55.0))
	damage_vehicle(helicopter, damage)
	helicopter_damage_cooldown = 0.70
	if is_instance_valid(prompt):
		prompt.text = "Harte Landung! EC135-Schaden: %d%%" % int(round(float(helicopter_health) / 1.8))

func _on_helicopter_rotor_destroyed(reason := "contact"):
	if not is_instance_valid(helicopter) or bool(helicopter.get_meta("destroyed")):
		return
	# A blade strike destroys lift, not all remaining fuselage HP. Otherwise an
	# incidental follow-up hit would bypass the intended fall-and-impact path.
	# Direct lethal damage has already reduced the metadata to zero.
	if str(reason) == "damage":
		helicopter_health = 0
		helicopter.set_meta("health", 0)
	if is_instance_valid(alert_label):
		alert_label.text = "ROTOR ZERSTÖRT – AUFTRIEB VERLOREN"
	update_status()

func _on_helicopter_fatal_crash(_impact_speed := 0.0):
	if is_instance_valid(helicopter):
		destroy_vehicle(helicopter)

func is_in_vehicle() -> bool:
	return in_car or in_helicopter

func get_active_player_vehicle():
	if in_helicopter and is_instance_valid(helicopter):
		return helicopter
	if in_car and is_instance_valid(car):
		return car
	return null

func can_enter_car(distance: float) -> bool:
	return (
		is_instance_valid(car)
		and distance < 3.5
		and not bool(car.get_meta("destroyed"))
	)

func can_enter_helicopter(distance: float) -> bool:
	return (
		is_instance_valid(helicopter)
		and distance < 4.3
		and not bool(helicopter.get_meta("destroyed"))
		and not (helicopter.has_method("is_rotor_failed") and helicopter.is_rotor_failed())
	)

func toggle_nearest_vehicle():
	if in_helicopter:
		toggle_helicopter()
		return
	if in_car:
		toggle_car()
		return
	var car_distance = player.global_transform.origin.distance_to(car.global_transform.origin)
	var helicopter_distance = player.global_transform.origin.distance_to(helicopter.global_transform.origin)
	var car_available = can_enter_car(car_distance)
	var helicopter_available = can_enter_helicopter(helicopter_distance)
	if helicopter_available and (not car_available or helicopter_distance <= car_distance):
		toggle_helicopter()
	elif car_available:
		toggle_car()

func toggle_car():
	if in_car:
		in_car = false
		car.set_driver_active(false)
		player.translation = car.translation + _upright_car_basis().x * 2.2 + Vector3.UP
		player_collider.disabled = false
		car_body.visible = true
	elif not in_helicopter and player.global_transform.origin.distance_to(car.global_transform.origin) < 3.5 and not bool(car.get_meta("destroyed")):
		in_car = true
		car.set_driver_active(true)
		set_weapon("")
		player_collider.disabled = true
	update_status()

func toggle_helicopter():
	if in_helicopter:
		in_helicopter = false
		helicopter.set_driver_active(false)
		helicopter.set_engine_enabled(false)
		var exit_basis = _upright_vehicle_basis(helicopter)
		var exit_position = helicopter.global_transform.origin + exit_basis.x * 2.55 + Vector3.UP * 0.25
		player.global_transform = Transform(exit_basis, exit_position)
		player_collider.disabled = false
		attach_camera_to_player()
		helicopter_look_yaw = 0.0
		camera.rotation_degrees = Vector3(look_x, 0.0, 0.0)
	elif (
		not in_car
		and player.global_transform.origin.distance_to(helicopter.global_transform.origin) < 4.3
		and not bool(helicopter.get_meta("destroyed"))
		and not (helicopter.has_method("is_rotor_failed") and helicopter.is_rotor_failed())
	):
		in_helicopter = true
		helicopter.set_driver_active(true)
		helicopter.set_engine_enabled(true)
		attach_camera_to_helicopter()
		set_weapon("")
		player_collider.disabled = true
		look_x = 0.0
		helicopter_look_yaw = 0.0
		camera.rotation_degrees = Vector3.ZERO
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
	if equipped_weapon == "rifle" and rifle_fire_mode == "auto" and not is_in_vehicle() and not controls_locked and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("shoot"):
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
	var active_vehicle = get_active_player_vehicle()
	if is_instance_valid(active_vehicle):
		excluded.append(active_vehicle)
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
	casing.linear_damp = 0.1
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
	var active_vehicle = get_active_player_vehicle()
	if is_instance_valid(active_vehicle):
		rocket_excluded.append(active_vehicle)
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
	elif vehicle == helicopter:
		helicopter_health = health
	if health <= 0:
		if vehicle == helicopter and helicopter.has_method("trigger_rotor_failure"):
			# Direct lethal damage destroys the aircraft immediately. Rotor contact
			# uses its separate signal path and keeps the chassis dynamic until impact.
			helicopter.trigger_rotor_failure("damage")
			destroy_vehicle(vehicle, create_blast)
		else:
			destroy_vehicle(vehicle, create_blast)
	else:
		update_status()

func destroy_vehicle(vehicle, create_blast := true):
	if not is_instance_valid(vehicle) or (vehicle.has_meta("destroyed") and bool(vehicle.get_meta("destroyed"))):
		return
	vehicle.set_meta("destroyed", true)
	vehicle.set_meta("health", 0)
	if vehicle.has_meta("vehicle_kind") and str(vehicle.get_meta("vehicle_kind")) == "fire_vehicle":
		set_hlf_blue_lights(vehicle, false, false)
		stop_fire_engine_audio(vehicle)
	destroyed_vehicles.append(vehicle)
	var wreck_position = vehicle.global_transform.origin + Vector3.UP * 0.65
	if create_blast:
		show_explosion(wreck_position, Vector3.UP)
		apply_explosion_damage(wreck_position, 7.0)
	if vehicle == car:
		car_health = 0
		car_speed = 0.0
		car.freeze_as_wreck()
		if in_car:
			in_car = false
			var exit_basis = _upright_car_basis()
			player.global_transform = Transform(exit_basis, car.global_transform.origin + exit_basis.x * 2.8 + Vector3.UP)
			player_collider.disabled = false
			set_weapon("")
			damage_player(35)
		alert_label.text = "FAHRZEUG ZERSTÖRT"
	elif vehicle == helicopter:
		helicopter_health = 0
		helicopter.freeze_as_wreck()
		if is_instance_valid(helicopter_audio):
			helicopter_audio.stop()
		if in_helicopter:
			in_helicopter = false
			var helicopter_exit_basis = _upright_vehicle_basis(helicopter)
			var helicopter_exit_position = helicopter.global_transform.origin + helicopter_exit_basis.x * 3.0 + Vector3.UP * 0.8
			player.global_transform = Transform(helicopter_exit_basis, helicopter_exit_position)
			player_collider.disabled = false
			attach_camera_to_player()
			set_weapon("")
			damage_player(100)
		alert_label.text = "EC135 ZERSTÖRT"
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
	if is_instance_valid(helicopter):
		vehicles.append(helicopter)
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
	if not is_in_vehicle():
		var player_distance = player.global_transform.origin.distance_to(position)
		if player_distance < radius:
			var player_blast_damage = int(90.0 * (1.0 - player_distance / radius))
			if player_blast_damage > 0:
				damage_player(player_blast_damage)

func collapse_building(building):
	if building in destroyed_buildings:
		return
	destroyed_buildings.append(building)
	var world_bounds = get_destructible_building_bounds(building)
	var building_position = world_bounds.position + world_bounds.size * 0.5
	var extents = Vector3(
		max(0.75, world_bounds.size.x * 0.5),
		max(0.50, world_bounds.size.y * 0.5),
		max(0.75, world_bounds.size.z * 0.5)
	)
	var ground_y = world_bounds.position.y
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


func get_destructible_building_bounds(building) -> AABB:
	if building is MeshInstance:
		var local_bounds = building.get_aabb()
		if building.has_meta("destruction_local_aabb"):
			var authored_bounds = building.get_meta("destruction_local_aabb")
			if typeof(authored_bounds) == TYPE_AABB:
				local_bounds = authored_bounds
		return transform_aabb_to_world(local_bounds, building.global_transform)

	var collision_shape = building.get_node_or_null("CollisionShape")
	if collision_shape and collision_shape.shape is BoxShape:
		var extents = collision_shape.shape.extents
		var local_bounds = AABB(-extents, extents * 2.0)
		return transform_aabb_to_world(local_bounds, collision_shape.global_transform)

	var fallback_position = building.global_transform.origin
	return AABB(fallback_position - Vector3(8, 10, 8), Vector3(16, 20, 16))


func transform_aabb_to_world(box: AABB, transform: Transform) -> AABB:
	var first = transform.xform(box.position)
	var minimum = first
	var maximum = first
	for x_side in range(2):
		for y_side in range(2):
			for z_side in range(2):
				var corner = box.position + Vector3(
					box.size.x * float(x_side),
					box.size.y * float(y_side),
					box.size.z * float(z_side)
				)
				var world_corner = transform.xform(corner)
				minimum.x = min(minimum.x, world_corner.x)
				minimum.y = min(minimum.y, world_corner.y)
				minimum.z = min(minimum.z, world_corner.z)
				maximum.x = max(maximum.x, world_corner.x)
				maximum.y = max(maximum.y, world_corner.y)
				maximum.z = max(maximum.z, world_corner.z)
	return AABB(minimum, maximum - minimum)


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
	var map = get_berlin_map()
	if is_instance_valid(map) and map.has_method("get_response_route"):
		var mapped_route = _normalize_response_route(
			map.get_response_route(incident, variant),
			incident
		)
		if mapped_route.size() >= 2:
			return mapped_route
	return _legacy_response_route(incident, variant)

func _normalize_response_route(route_value, incident: Vector3) -> Array:
	var route := []
	if typeof(route_value) == TYPE_DICTIONARY:
		if route_value.has("spawn"):
			_append_route_point(route, route_value["spawn"])
		for points_key in ["waypoints", "route", "path", "points"]:
			if route_value.has(points_key):
				_append_route_points(route, route_value[points_key])
		if route_value.has("target"):
			_append_route_point(route, route_value["target"])
	elif typeof(route_value) == TYPE_ARRAY or typeof(route_value) == typeof(PoolVector3Array()):
		_append_route_points(route, route_value)
	if route.size() == 1:
		_append_route_point(route, incident)
	return route

func _append_route_points(route: Array, points):
	if not (typeof(points) == TYPE_ARRAY or typeof(points) == typeof(PoolVector3Array())):
		return
	for point in points:
		_append_route_point(route, point)

func _append_route_point(route: Array, point):
	if typeof(point) != TYPE_VECTOR3:
		return
	if not route.empty() and route[-1].distance_squared_to(point) < 0.0001:
		return
	route.append(point)

func _legacy_response_route(incident: Vector3, variant: int) -> Array:
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

func _offset_route_laterally(route: Array, lateral_offset: float) -> Array:
	if abs(lateral_offset) < 0.001 or route.size() < 2:
		return route.duplicate()
	var offset_route := []
	for point_index in range(route.size()):
		var previous_point = route[max(0, point_index - 1)]
		var next_point = route[min(route.size() - 1, point_index + 1)]
		var tangent = next_point - previous_point
		tangent.y = 0.0
		if tangent.length_squared() < 0.0001:
			tangent = Vector3.FORWARD
		else:
			tangent = tangent.normalized()
		var lane_right = Vector3(-tangent.z, 0.0, tangent.x)
		offset_route.append(route[point_index] + lane_right * lateral_offset)
	return offset_route

func _route_at_vehicle_height(route: Array, kind: String) -> Array:
	var elevated_route := []
	var ground_height = HLF_GROUND_HEIGHT if kind == "fire" else GOLF_GROUND_HEIGHT
	var height_above_road = ground_height - HLF_ROAD_SURFACE_Y
	for route_point in route:
		var elevated_point: Vector3 = route_point
		if abs(elevated_point.y) < 0.001:
			# Legacy route points describe the old map's y=0 datum.
			elevated_point.y = ground_height
		else:
			# Segmented-map points lie on the actual road surface.
			elevated_point.y += height_above_road
		elevated_route.append(elevated_point)
	return elevated_route

func create_emergency_vehicle(kind: String, spawn_position: Vector3):
	var vehicle = KinematicBody.new()
	vehicle.name = "FireEngine" if kind == "fire" else "PoliceCar"
	vehicle.translation = spawn_position
	register_damageable_vehicle(vehicle, 240 if kind == "fire" else 160, "%s_vehicle" % kind)
	add_child(vehicle)
	if kind == "fire":
		add_hlf_visual(vehicle)
		add_hlf_collision(vehicle)
		set_hlf_blue_lights(vehicle, false, false)
		add_fire_engine_audio(vehicle)
	else:
		add_golf_visual(vehicle, true)
		add_police_golf_livery(vehicle)
		add_golf_collision(vehicle)
	if kind != "fire":
		for light_data in [["BlueLightLeft", -0.36], ["BlueLightRight", 0.36]]:
			var police_light = add_box(vehicle, light_data[0], Vector3(float(light_data[1]), 0.86, 0), Vector3(0.56, 0.16, 0.24), Color("167cff"), false)
			var police_light_mat = police_light.mesh.material as SpatialMaterial
			police_light_mat.emission_enabled = true
			police_light_mat.emission = Color("167cff")
	return vehicle

func dispatch_fire_department(incident: Vector3):
	var route = _route_at_vehicle_height(
		response_route(incident, destroyed_buildings.size()),
		"fire"
	)
	var fire_spawn = route[0]
	var fire_target = route[-1]
	var first_waypoint = route[1]
	var engine = create_emergency_vehicle("fire", fire_spawn)
	engine.look_at(Vector3(first_waypoint.x, fire_spawn.y, first_waypoint.z), Vector3.UP)
	emergency_vehicles.append({
		"node": engine,
		"kind": "fire",
		"target": fire_target,
		"waypoints": route,
		"waypoint_index": 1,
		"incident": incident,
		"arrived": false
	})
	alert_label.text = "FEUERWEHR AUF ANFAHRT"

func dispatch_police(incident: Vector3, severity := 1):
	wanted_level = min(3, wanted_level + int(severity))
	update_status()
	police_dispatch_count += 1
	for unit in range(2):
		var route = response_route(incident, police_dispatch_count + unit)
		# Fire and police are dispatched together after a building collapse. Keep
		# both patrol cars in their own lanes along every graph segment. New-map
		# points must not be clamped to the removed +/-680 metre legacy boundary.
		var lane_offset = (-1.0 if unit == 0 else 1.0) * EMERGENCY_LANE_OFFSET
		route = _route_at_vehicle_height(
			_offset_route_laterally(route, lane_offset),
			"police"
		)
		var police_spawn = route[0]
		var police_target = route[-1]
		var first_waypoint = route[1]
		var police_car = create_emergency_vehicle("police", police_spawn)
		police_car.look_at(Vector3(first_waypoint.x, police_spawn.y, first_waypoint.z), Vector3.UP)
		emergency_vehicles.append({
			"node": police_car,
			"kind": "police",
			"target": police_target,
			"waypoints": route,
			"waypoint_index": 1,
			"incident": incident,
			"arrived": false
		})
	alert_label.text = "POLIZEI ALARMIERT"

func _response_waypoints(response: Dictionary, vehicle: Spatial) -> Array:
	var waypoints := []
	if response.has("waypoints"):
		_append_route_points(waypoints, response["waypoints"])
	if waypoints.empty():
		waypoints.append(vehicle.translation)
		if response.has("target"):
			_append_route_point(waypoints, response["target"])
	if waypoints.size() == 1:
		waypoints.append(waypoints[0])
	return waypoints

func update_emergency_vehicles(delta):
	for response in emergency_vehicles:
		var vehicle = response.node
		if not is_instance_valid(vehicle):
			continue
		if vehicle.has_meta("destroyed") and bool(vehicle.get_meta("destroyed")):
			response.arrived = true
			if response.kind == "fire":
				set_hlf_blue_lights(vehicle, false, false)
				stop_fire_engine_audio(vehicle)
			continue
		if response.kind == "fire":
			update_hlf_emergency_effects(vehicle, not response.arrived)
		if response.arrived:
			continue
		var waypoints = _response_waypoints(response, vehicle)
		response["waypoints"] = waypoints
		var final_waypoint_index = waypoints.size() - 1
		var waypoint_index = int(clamp(
			int(response.get("waypoint_index", 1)),
			1,
			final_waypoint_index
		))
		var intermediate_distance = 4.0
		while waypoint_index < final_waypoint_index:
			var waypoint_offset: Vector3 = waypoints[waypoint_index] - vehicle.translation
			waypoint_offset.y = 0.0
			if waypoint_offset.length() > intermediate_distance:
				break
			waypoint_index += 1
		response["waypoint_index"] = waypoint_index
		var target: Vector3 = waypoints[waypoint_index]
		var offset = target - vehicle.translation
		offset.y = 0
		var arrival_distance = FIRE_ENGINE_ARRIVAL_DISTANCE if response.kind == "fire" else 2.5
		var at_final_waypoint = waypoint_index == final_waypoint_index
		if not at_final_waypoint or offset.length() > arrival_distance:
			var speed = FIRE_ENGINE_SPEED if response.kind == "fire" else POLICE_SPEED
			if vehicle is KinematicBody:
				vehicle.move_and_slide(offset.normalized() * speed, Vector3.UP)
			else:
				vehicle.translation += offset.normalized() * speed * delta
			# The waypoint carries the real road height. This keeps responders on
			# segmented-map streets instead of forcing the old flat-map constant.
			vehicle.translation.y = target.y
			vehicle.look_at(Vector3(target.x, vehicle.translation.y, target.z), Vector3.UP)
		else:
			response.arrived = true
			vehicle.translation.y = target.y
			if response.kind == "police":
				spawn_police_officers(vehicle.global_transform.origin)
				alert_label.text = "POLIZEI: STEHEN BLEIBEN!"
			else:
				# Stop the horn before constructing the hose scene. Even if a future
				# visual asset fails, the arrival state can never leave the siren running.
				update_hlf_emergency_effects(vehicle, false)
				spawn_firefighters(vehicle, response.incident)
				alert_label.text = "FEUERWEHR LÖSCHT – 5 MIN."
		if response.kind == "police":
			var flash = int(OS.get_ticks_msec() / 220) % 2 == 0
			if vehicle.has_node("BlueLightLeft"):
				vehicle.get_node("BlueLightLeft").visible = flash
				vehicle.get_node("BlueLightRight").visible = not flash

func update_hlf_emergency_effects(vehicle: Node, siren_active: bool):
	# Two quick flashes at the front, followed by two at the rear.
	var flash_phase = int(OS.get_ticks_msec() / 110) % 8
	set_hlf_blue_lights(vehicle, flash_phase == 0 or flash_phase == 2, flash_phase == 4 or flash_phase == 6)
	var engine_audio = vehicle.get_node_or_null("EngineAudio")
	if engine_audio is AudioStreamPlayer3D:
		engine_audio.pitch_scale = 1.08 if siren_active else 0.78
		engine_audio.unit_db = -8.0 if siren_active else -12.0
		if not engine_audio.playing:
			engine_audio.play()
	var horn_audio = vehicle.get_node_or_null("MartinshornAudio")
	if horn_audio is AudioStreamPlayer3D:
		if siren_active and not horn_audio.playing:
			horn_audio.play()
		elif not siren_active and horn_audio.playing:
			horn_audio.stop()

func spawn_police_officers(vehicle_position: Vector3):
	for side in [-1, 1]:
		var officer = KinematicBody.new()
		officer.name = "PoliceOfficer"
		var road_surface_y = vehicle_position.y - GOLF_GROUND_HEIGHT + HLF_ROAD_SURFACE_Y
		officer.translation = Vector3(vehicle_position.x + side * 2.0, road_surface_y, vehicle_position.z)
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
		var active_vehicle = get_active_player_vehicle()
		var target_body = active_vehicle if is_instance_valid(active_vehicle) else player
		var target_position = target_body.global_transform.origin
		var target_delta = target_position - officer.global_transform.origin
		var horizontal_offset = target_delta
		horizontal_offset.y = 0
		if horizontal_offset.length() > 7.0:
			officer.move_and_slide(horizontal_offset.normalized() * OFFICER_SPEED + Vector3.DOWN * 4.0, Vector3.UP)
		if horizontal_offset.length() > 0.2:
			officer.look_at(Vector3(target_position.x, officer.global_transform.origin.y, target_position.z), Vector3.UP)
		var cooldown = float(officer.get_meta("shoot_cooldown")) - delta
		if cooldown <= 0.0 and target_delta.length() < 38.0 and abs(target_delta.y) < 14.0:
			police_shoot(officer)
			cooldown = 1.15
		officer.set_meta("shoot_cooldown", cooldown)

func police_shoot(officer):
	if not is_instance_valid(officer) or player_dying:
		return
	var active_vehicle = get_active_player_vehicle()
	var target_body = active_vehicle if is_instance_valid(active_vehicle) else player
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
	var target_delta = aim_point - from
	if target_delta.length() >= 40.0 or abs(target_delta.y) >= 14.0:
		return
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
	if target_body != player:
		damage_vehicle(target_body, 6)
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
	if is_instance_valid(car):
		car.set_driver_active(false)
	if is_instance_valid(helicopter):
		helicopter.set_driver_active(false)
		helicopter.set_engine_enabled(false)
	if mission_one and mission_one.is_overlay_open():
		mission_one.close_dialogue()
	if in_helicopter:
		in_helicopter = false
		var helicopter_exit_basis = _upright_vehicle_basis(helicopter)
		var helicopter_exit_position = helicopter.global_transform.origin + helicopter_exit_basis.x * 2.8 + Vector3.UP * 0.8
		player.global_transform = Transform(helicopter_exit_basis, helicopter_exit_position)
	elif in_car:
		in_car = false
		var exit_basis = _upright_car_basis()
		var exit_position = car.global_transform.origin + exit_basis.x * 2.6 + Vector3.UP * 0.8
		player.global_transform = Transform(exit_basis, exit_position)
	else:
		player.rotation_degrees = Vector3(0, player.rotation_degrees.y, 0)
	# Death can be entered from scripted or stale states as well as the normal
	# vehicle branches, so always restore the first-person camera ownership.
	attach_camera_to_player()
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
	in_car = false
	in_helicopter = false
	attach_camera_to_player()
	player.global_transform = get_map_spawn_transform(
		"respawn",
		Transform(Basis(), Vector3(3, 4, 8))
	)
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

func spawn_firefighters(vehicle: Spatial, incident: Vector3):
	if not is_instance_valid(vehicle):
		return null
	var operation = Spatial.new()
	operation.name = "FirefightingOperation"
	operation.set_meta("duration_seconds", FIRE_SUPPRESSION_DURATION)
	operation.set_meta("elapsed_seconds", 0.0)
	add_child(operation)

	var vehicle_position = vehicle.global_transform.origin
	var right = vehicle.global_transform.basis.x.normalized()
	var forward = -vehicle.global_transform.basis.z.normalized()
	var to_incident = incident - vehicle_position
	to_incident.y = 0.0
	var incident_side = 1.0 if to_incident.dot(right) >= 0.0 else -1.0
	var incident_forward = 1.0 if to_incident.dot(forward) >= 0.0 else -1.0
	var side_position = vehicle_position + right * incident_side * FIREFIGHTER_SIDE_DISTANCE
	var firefighter_ground_y = vehicle_position.y - HLF_GROUND_HEIGHT + FIREFIGHTER_FOOT_HEIGHT
	var firefighter_positions = [
		side_position + forward * incident_forward * 0.72,
		side_position - forward * incident_forward * 0.72
	]
	var firefighters = []
	for firefighter_index in range(firefighter_positions.size()):
		var firefighter_position = firefighter_positions[firefighter_index]
		firefighter_position.y = firefighter_ground_y
		var firefighter = Spatial.new()
		firefighter.name = "FirefighterNozzle" if firefighter_index == 0 else "FirefighterBackup"
		operation.add_child(firefighter)
		firefighter.global_transform = Transform(Basis(), firefighter_position)
		var human = HUMAN_SCENE.instance()
		human.name = "FirefighterModel"
		firefighter.add_child(human)
		add_box(firefighter, "SafetyJacket", Vector3(0, 1.05, 0), Vector3(0.76, 0.62, 0.44), Color("d7bf21"), false)
		add_box(firefighter, "ReflectiveStripe", Vector3(0, 1.0, -0.24), Vector3(0.70, 0.10, 0.03), Color("eff6dc"), false)
		var look_target = Vector3(incident.x, firefighter_position.y, incident.z)
		if firefighter_position.distance_to(look_target) > 0.01:
			firefighter.look_at(look_target, Vector3.UP)
		firefighters.append(firefighter)

	# A single attack line is handled by a two-person crew: the first responder
	# holds the nozzle while the second supports the hose immediately behind.
	var operator_position = firefighters[0].global_transform.origin
	var backup_position = firefighters[1].global_transform.origin
	var spray_target = incident + Vector3.UP * 1.65
	var aim_direction = (spray_target - (operator_position + Vector3.UP * 1.22)).normalized()
	var nozzle_start = operator_position + Vector3.UP * 1.22 + aim_direction * 0.16
	var nozzle_end = nozzle_start + aim_direction * 0.34
	add_cylinder_between(operation, "Nozzle", nozzle_start, nozzle_end, 0.035, Color("333a3e"))

	var road_surface_y = vehicle_position.y - HLF_GROUND_HEIGHT + HLF_ROAD_SURFACE_Y
	var pump_connection = vehicle_position + right * incident_side * 1.08 - forward * incident_forward * 0.35 + Vector3.UP * 0.25
	var hose_points = [
		pump_connection,
		Vector3(vehicle_position.x, road_surface_y + 0.045, vehicle_position.z) + right * incident_side * 1.55 - forward * incident_forward * 0.25,
		Vector3(backup_position.x, road_surface_y + 0.045, backup_position.z),
		Vector3(operator_position.x, road_surface_y + 0.045, operator_position.z) - forward * incident_forward * 0.24,
		nozzle_start
	]
	var hose_root = Spatial.new()
	hose_root.name = "AttackHose"
	operation.add_child(hose_root)
	for hose_index in range(hose_points.size() - 1):
		add_cylinder_between(hose_root, "HoseSegment%02d" % hose_index, hose_points[hose_index], hose_points[hose_index + 1], 0.045, Color("263c32"))

	var water_spray = ImmediateGeometry.new()
	water_spray.name = "WaterSpray"
	water_spray.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	var water_material = SpatialMaterial.new()
	water_material.flags_unshaded = true
	water_material.flags_transparent = true
	water_material.vertex_color_use_as_albedo = true
	water_material.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	water_material.emission_enabled = true
	water_material.emission = Color("75cfff")
	water_material.emission_energy = 1.7
	water_spray.material_override = water_material
	operation.add_child(water_spray)
	var droplets = []
	for droplet_index in range(WATER_DROPLET_COUNT):
		var droplet = add_sphere(operation, "WaterDroplet%02d" % droplet_index, nozzle_end, 0.045, Color("9be3ff"))
		droplet.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		var droplet_material = droplet.mesh.material as SpatialMaterial
		droplet_material.flags_unshaded = true
		droplet_material.flags_transparent = true
		droplet_material.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
		droplet_material.emission_enabled = true
		droplet_material.emission = Color("75cfff")
		droplet_material.emission_energy = 1.25
		droplets.append(droplet)

	var spray_data = {
		"node": water_spray,
		"start": nozzle_end,
		"target": spray_target,
		"phase": 0.37,
		"droplets": droplets
	}
	var operation_state = {
		"root": operation,
		"incident": incident,
		"elapsed": 0.0,
		"duration": FIRE_SUPPRESSION_DURATION,
		"sprays": [spray_data]
	}
	firefighting_operations.append(operation_state)
	update_water_spray(spray_data, 0.0)

	var timer = Timer.new()
	timer.name = "SuppressionTimer"
	timer.one_shot = true
	timer.wait_time = FIRE_SUPPRESSION_DURATION
	operation.add_child(timer)
	timer.connect("timeout", self, "extinguish_fire", [incident, operation])
	timer.start()
	return operation

func update_firefighting_operations(delta: float):
	for operation_state in firefighting_operations.duplicate():
		var operation = operation_state.get("root", null)
		if not is_instance_valid(operation):
			firefighting_operations.erase(operation_state)
			continue
		operation_state["elapsed"] = float(operation_state.get("elapsed", 0.0)) + delta
		operation.set_meta("elapsed_seconds", operation_state["elapsed"])
		for spray_data in operation_state.get("sprays", []):
			update_water_spray(spray_data, operation_state["elapsed"])

func update_water_spray(spray_data: Dictionary, elapsed: float):
	var spray = spray_data.get("node", null)
	if not is_instance_valid(spray):
		return
	var start = spray_data.get("start", Vector3.ZERO)
	var target = spray_data.get("target", Vector3.ZERO)
	var phase = float(spray_data.get("phase", 0.0))
	var stream_direction = (target - start).normalized()
	var lateral = stream_direction.cross(Vector3.UP)
	if lateral.length_squared() < 0.0001:
		lateral = Vector3.RIGHT
	else:
		lateral = lateral.normalized()
	spray.clear()
	spray.begin(Mesh.PRIMITIVE_LINES)
	for strand_index in range(4):
		var strand_offset = (float(strand_index) - 1.5) * 0.018
		for segment_index in range(WATER_SPRAY_SEGMENTS):
			var from_t = float(segment_index) / float(WATER_SPRAY_SEGMENTS)
			var to_t = float(segment_index + 1) / float(WATER_SPRAY_SEGMENTS)
			var from_point = water_spray_point(start, target, from_t, elapsed, phase, lateral, strand_offset)
			var to_point = water_spray_point(start, target, to_t, elapsed, phase, lateral, strand_offset)
			spray.set_color(Color("d9f6ff").linear_interpolate(Color("63bfff"), from_t))
			spray.add_vertex(spray.to_local(from_point))
			spray.set_color(Color("d9f6ff").linear_interpolate(Color("63bfff"), to_t))
			spray.add_vertex(spray.to_local(to_point))
	spray.end()

	var droplets = spray_data.get("droplets", [])
	for droplet_index in range(droplets.size()):
		var droplet = droplets[droplet_index]
		if not is_instance_valid(droplet):
			continue
		var droplet_t = fmod(elapsed * 1.55 + float(droplet_index) / float(max(1, droplets.size())) + phase, 1.0)
		var droplet_offset = sin(float(droplet_index) * 2.13) * 0.025
		var droplet_position = water_spray_point(start, target, droplet_t, elapsed, phase + droplet_index, lateral, droplet_offset)
		droplet.global_transform = Transform(Basis(), droplet_position)

func water_spray_point(start: Vector3, target: Vector3, progress: float, elapsed: float, phase: float, lateral: Vector3, strand_offset: float) -> Vector3:
	var point = start.linear_interpolate(target, progress)
	var arc_height = clamp(start.distance_to(target) * 0.075, 0.45, 2.6)
	var arc_weight = sin(progress * PI)
	point.y += arc_weight * arc_height
	point += lateral * (strand_offset + sin(elapsed * 11.0 + phase + progress * 19.0) * 0.028 * arc_weight)
	return point

func extinguish_fire(incident: Vector3, operation):
	for operation_state in firefighting_operations.duplicate():
		if operation_state.get("root", null) == operation:
			firefighting_operations.erase(operation_state)
	if is_instance_valid(operation):
		operation.queue_free()
	for child in get_children():
		if child.name.begins_with("Rubble_") and child.global_transform.origin.distance_to(incident) < 12.0:
			for rubble_child in child.get_children():
				if rubble_child.name.begins_with("Fire"):
					rubble_child.queue_free()
	if is_instance_valid(alert_label):
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
	var mode_text = "ZU FUSS"
	if in_helicopter and is_instance_valid(helicopter):
		mode_text = "IM EC135"
		var rotor_rpm = int(round(helicopter.get_rotor_rpm()))
		var collective_percent = int(round(helicopter.get_collective() * 100.0))
		var helicopter_speed = int(round(helicopter.get_speed_kph()))
		var helicopter_health_percent = int(round(float(helicopter_health) / 1.8))
		var rotor_state = " · ROTOR DEFEKT" if helicopter.is_rotor_failed() else ""
		vehicle_text = " | %d km/h · %d RPM · COL %d%% | EC135 %d%%%s" % [
			helicopter_speed,
			rotor_rpm,
			collective_percent,
			helicopter_health_percent,
			rotor_state
		]
	elif in_car:
		mode_text = "IM AUTO"
		var speed_kph = int(round(car.get_speed_kph())) if is_instance_valid(car) else int(round(abs(car_speed) * 3.6))
		var gear = car.get_current_gear() if is_instance_valid(car) else 0
		var gear_text = "R" if gear < 0 else str(gear)
		vehicle_text = " | %d km/h · GANG %s | BENZIN %d%% | AUTO %d%%" % [speed_kph, gear_text, int(ceil(car_fuel)), car_health]
	status.text = mode_text + " | HP %d%s%s | Waffe: %s%s" % [player_health, vehicle_text, wanted_text, weapon_name, ammo_text]
