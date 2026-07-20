extends Spatial

const BERLIN_MAP_SCENE = preload("res://scenes/BerlinMap.tscn")
const HUMAN_SCENE = preload("res://Assets/HumanV2.glb")
const WALK_SPEED = 8.0
const DRIVE_SPEED = 22.0
const GRAVITY = 24.0
const POLICE_SPEED = 16.0
const OFFICER_SPEED = 5.2
const FIRE_ENGINE_SPEED = 13.0

var player: KinematicBody
var camera: Camera
var car: KinematicBody
var car_body: MeshInstance
var pistol_model: Spatial
var bazooka_model: Spatial
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

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	build_world()
	build_player()
	build_car()
	build_npcs()
	build_ui()
	tag_destructible_buildings(get_node("BerlinMap"))

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
	var collider = CollisionShape.new()
	var capsule = CapsuleShape.new()
	capsule.radius = 0.45
	capsule.height = 1.0
	collider.shape = capsule
	player.add_child(collider)
	camera = Camera.new()
	camera.translation = Vector3(0, 0.65, 0)
	camera.far = 10000.0
	camera.current = true
	player.add_child(camera)
	build_pistol()
	build_bazooka()
	add_child(player)

func build_pistol():
	pistol_model = Spatial.new()
	pistol_model.name = "Pistol"
	pistol_model.translation = Vector3(0.34, -0.28, -0.62)
	pistol_model.rotation_degrees = Vector3(-4, -5, 0)
	# Slide, barrel, grip, trigger guard and front sight form a readable first-person pistol.
	add_box(pistol_model, "Slide", Vector3(0, 0, -0.12), Vector3(0.16, 0.15, 0.55), Color("25282d"), false)
	add_box(pistol_model, "Frame", Vector3(0, -0.10, -0.02), Vector3(0.14, 0.10, 0.36), Color("3f444b"), false)
	var grip = add_box(pistol_model, "Grip", Vector3(0, -0.28, 0.07), Vector3(0.14, 0.38, 0.20), Color("17191c"), false)
	grip.rotation_degrees.x = -12
	add_cylinder(pistol_model, "Barrel", Vector3(0, 0.0, -0.43), 0.045, 0.10, Color("0d0e10"), Vector3(90, 0, 0))
	add_box(pistol_model, "Sight", Vector3(0, 0.10, -0.35), Vector3(0.035, 0.045, 0.07), Color("d9d9d0"), false)
	var flash = add_sphere(pistol_model, "MuzzleFlash", Vector3(0, 0, -0.52), 0.10, Color("ffdf62"))
	flash.scale = Vector3(0.65, 0.65, 1.8)
	flash.visible = false
	pistol_model.visible = false
	camera.add_child(pistol_model)

func build_bazooka():
	bazooka_model = Spatial.new()
	bazooka_model.name = "Bazooka"
	bazooka_model.translation = Vector3(0.42, -0.30, -0.78)
	bazooka_model.rotation_degrees = Vector3(-3, -4, 0)
	add_cylinder(bazooka_model, "LauncherTube", Vector3(0, 0, -0.12), 0.12, 1.15, Color("46513b"), Vector3(90, 0, 0))
	add_cylinder(bazooka_model, "RearRing", Vector3(0, 0, 0.43), 0.17, 0.08, Color("242a22"), Vector3(90, 0, 0))
	add_cylinder(bazooka_model, "FrontRing", Vector3(0, 0, -0.68), 0.16, 0.08, Color("242a22"), Vector3(90, 0, 0))
	add_box(bazooka_model, "Grip", Vector3(0, -0.22, 0.12), Vector3(0.12, 0.36, 0.16), Color("20231e"), false)
	add_box(bazooka_model, "Sight", Vector3(0, 0.16, -0.30), Vector3(0.08, 0.10, 0.18), Color("171a16"), false)
	bazooka_model.visible = false
	camera.add_child(bazooka_model)

func tag_destructible_buildings(node: Node):
	if node is StaticBody and node.name.begins_with("Building_"):
		node.set_meta("destructible_building", true)
	for child in node.get_children():
		tag_destructible_buildings(child)

func build_car():
	car = KinematicBody.new()
	car.name = "Car"
	car.translation = Vector3(2.8, 8, -4)
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
		npc.set_meta("health", 2)
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
	help.rect_position = Vector2(18, -48)
	help.text = "WASD Bewegen/Fahren  •  E Auto  •  1 Pistole  •  2 Bazooka  •  Klick Schießen  •  Esc Maus lösen"
	layer.add_child(help)

func _unhandled_input(event):
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		player.rotate_y(deg2rad(-event.relative.x * 0.12))
		look_x = clamp(look_x - event.relative.y * 0.12, -80, 80)
		camera.rotation_degrees.x = look_x
	if event is InputEventMouseButton and event.pressed:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if event.is_action_pressed("interact"):
		toggle_car()
	if event.is_action_pressed("equip") and not in_car:
		set_weapon("" if equipped_weapon == "pistol" else "pistol")
	if event.is_action_pressed("equip_bazooka") and not in_car:
		set_weapon("" if equipped_weapon == "bazooka" else "bazooka")
	if event.is_action_pressed("shoot") and equipped_weapon != "" and not in_car:
		if equipped_weapon == "bazooka":
			fire_bazooka()
		else:
			shoot()

func _physics_process(delta):
	if in_car:
		drive(delta)
	else:
		walk(delta)
	update_emergency_vehicles(delta)
	update_police_officers(delta)
	var near_car = player.global_transform.origin.distance_to(car.global_transform.origin) < 3.5
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
	velocity = player.move_and_slide(velocity, Vector3.UP)

func drive(delta):
	var input = input_vector()
	var throttle = -input.y
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
	car.move_and_slide(motion, Vector3.UP, true, 4, deg2rad(48))
	if car.get_slide_count() > 0 and car.global_transform.origin.distance_to(previous_position) < abs(car_speed) * delta * 0.2:
		car_speed *= 0.45
	align_car_to_ground(delta)
	player.global_transform = car.global_transform
	player.translation.y += 1.2

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
		player.get_node("CollisionShape").disabled = false
		car_body.visible = true
	elif player.global_transform.origin.distance_to(car.global_transform.origin) < 3.5:
		in_car = true
		set_weapon("")
		player.get_node("CollisionShape").disabled = true
	update_status()

func set_weapon(weapon: String):
	equipped_weapon = weapon
	pistol_model.visible = weapon == "pistol"
	bazooka_model.visible = weapon == "bazooka"
	crosshair.visible = weapon != ""
	update_status()

func shoot():
	var from = camera.global_transform.origin
	var to = from + -camera.global_transform.basis.z * 100.0
	var hit = get_world().direct_space_state.intersect_ray(from, to, [player, car])
	var end = hit.position if hit else to
	show_shot_trace(from + -camera.global_transform.basis.z * 0.55, end)
	var flash = pistol_model.get_node("MuzzleFlash")
	flash.visible = true
	get_tree().create_timer(0.055).connect("timeout", flash, "set_visible", [false])
	if hit:
		show_impact(hit.position, hit.normal)
	if hit and hit.collider.has_meta("health"):
		var target = hit.collider
		if str(target.get_meta("role")) == "civilian" and not target.has_meta("police_called"):
			target.set_meta("police_called", true)
			dispatch_police(target.global_transform.origin)
		var health = int(target.get_meta("health")) - 1
		target.set_meta("health", health)
		prompt.text = "Treffer!"
		if health <= 0:
			if str(target.get_meta("role")) == "civilian":
				npcs.erase(target)
			else:
				police_officers.erase(target)
			target.queue_free()
			prompt.text = "Ziel ausgeschaltet"

func fire_bazooka():
	if not bazooka_ready:
		return
	bazooka_ready = false
	var from = camera.global_transform.origin + -camera.global_transform.basis.z * 0.8
	var to = camera.global_transform.origin + -camera.global_transform.basis.z * 300.0
	var hit = get_world().direct_space_state.intersect_ray(camera.global_transform.origin, to, [player, car])
	var end = hit.position if hit else to
	var target = hit.collider if hit else null
	var normal = hit.normal if hit else Vector3.UP
	var rocket = add_sphere(self, "BazookaRocket", from, 0.13, Color("ff9d32"))
	var rocket_mat = rocket.mesh.material as SpatialMaterial
	rocket_mat.emission_enabled = true
	rocket_mat.emission = Color("ff6d20")
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

func nearest_road(value: float) -> float:
	var result = -180.0
	var best_distance = INF
	for road in [-180.0, -90.0, 0.0, 90.0, 180.0]:
		var distance = abs(value - road)
		if distance < best_distance:
			best_distance = distance
			result = road
	return result

func response_route(incident: Vector3, variant: int) -> Array:
	var road_x = nearest_road(incident.x)
	var road_z = nearest_road(incident.z)
	var target
	var spawn
	if abs(incident.x - road_x) < abs(incident.z - road_z):
		target = Vector3(road_x, 0.0, incident.z)
		spawn = target + Vector3(0, 0, 65.0 if variant % 2 == 0 else -65.0)
	else:
		target = Vector3(incident.x, 0.0, road_z)
		spawn = target + Vector3(65.0 if variant % 2 == 0 else -65.0, 0, 0)
	return [spawn, target]

func create_emergency_vehicle(kind: String, spawn_position: Vector3):
	var vehicle = Spatial.new()
	vehicle.name = "FireEngine" if kind == "fire" else "PoliceCar"
	vehicle.translation = spawn_position
	add_child(vehicle)
	if kind == "fire":
		add_box(vehicle, "Body", Vector3(0, 0.55, 0), Vector3(2.6, 1.45, 5.8), Color("c52520"), false)
		add_box(vehicle, "Cab", Vector3(0, 1.42, -1.62), Vector3(2.4, 1.25, 2.15), Color("e43a31"), false)
		add_box(vehicle, "Windshield", Vector3(0, 1.55, -2.72), Vector3(2.0, 0.65, 0.08), Color("315b6d"), false)
		add_box(vehicle, "Ladder", Vector3(0, 1.55, 0.95), Vector3(0.65, 0.18, 3.0), Color("d8d7cc"), false)
		for side in [-1, 1]:
			for z in [-1.7, 1.75]:
				add_cylinder(vehicle, "Wheel", Vector3(side * 1.34, -0.05, z), 0.52, 0.30, Color("111214"), Vector3(0, 0, 90))
	else:
		add_box(vehicle, "Body", Vector3(0, 0.35, 0), Vector3(2.1, 0.70, 4.5), Color("e7e9eb"), false)
		add_box(vehicle, "Cab", Vector3(0, 0.94, 0.15), Vector3(1.75, 0.75, 2.0), Color("18477b"), false)
		add_box(vehicle, "BlueStripe", Vector3(0, 0.47, -0.05), Vector3(2.14, 0.25, 3.5), Color("1f5d9b"), false)
		for side in [-1, 1]:
			for z in [-1.35, 1.35]:
				add_cylinder(vehicle, "Wheel", Vector3(side * 1.07, -0.08, z), 0.42, 0.25, Color("111214"), Vector3(0, 0, 90))
	var red_light = add_sphere(vehicle, "RedLight", Vector3(-0.30, 1.85 if kind == "fire" else 1.42, 0), 0.14, Color("ff2020"))
	var blue_light = add_sphere(vehicle, "BlueLight", Vector3(0.30, 1.85 if kind == "fire" else 1.42, 0), 0.14, Color("248dff"))
	for light_mesh in [red_light, blue_light]:
		var light_mat = light_mesh.mesh.material as SpatialMaterial
		light_mat.emission_enabled = true
		light_mat.emission = light_mat.albedo_color
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

func dispatch_police(incident: Vector3):
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
		var target = response.target
		var offset = target - vehicle.translation
		offset.y = 0
		if offset.length() > 2.5:
			var speed = FIRE_ENGINE_SPEED if response.kind == "fire" else POLICE_SPEED
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
		if vehicle.has_node("RedLight"):
			vehicle.get_node("RedLight").visible = flash
		if vehicle.has_node("BlueLight"):
			vehicle.get_node("BlueLight").visible = not flash

func spawn_police_officers(vehicle_position: Vector3):
	for side in [-1, 1]:
		var officer = KinematicBody.new()
		officer.name = "PoliceOfficer"
		officer.translation = Vector3(vehicle_position.x + side * 2.0, 0.05, vehicle_position.z)
		officer.set_meta("health", 3)
		officer.set_meta("role", "police")
		officer.set_meta("shoot_cooldown", 0.4 + float(side + 1) * 0.25)
		var human = HUMAN_SCENE.instance()
		human.name = "OfficerModel"
		officer.add_child(human)
		add_box(officer, "PoliceVest", Vector3(0, 1.05, 0), Vector3(0.72, 0.58, 0.42), Color("173e6f"), false)
		add_box(officer, "PoliceMark", Vector3(0, 1.05, -0.22), Vector3(0.42, 0.12, 0.03), Color("d8e7f2"), false)
		var collision = CollisionShape.new()
		var shape = CapsuleShape.new()
		shape.radius = 0.42
		shape.height = 1.2
		collision.shape = shape
		collision.translation.y = 1.0
		officer.add_child(collision)
		add_child(officer)
		police_officers.append(officer)

func update_police_officers(delta):
	for officer in police_officers.duplicate():
		if not is_instance_valid(officer):
			police_officers.erase(officer)
			continue
		var target_position = player.global_transform.origin
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
	var from = officer.global_transform.origin + Vector3.UP * 1.35
	var to = camera.global_transform.origin
	var hit = get_world().direct_space_state.intersect_ray(from, to, [officer])
	show_shot_trace(from, hit.position if hit else to)
	if hit and (hit.collider == player or (in_car and hit.collider == car)):
		damage_player(10)

func damage_player(amount: int):
	player_health = max(0, player_health - amount)
	prompt.text = "Du wirst beschossen!"
	update_status()
	if player_health <= 0:
		in_car = false
		player.get_node("CollisionShape").disabled = false
		set_weapon("")
		player.translation = Vector3(3, 4, 8)
		velocity = Vector3.ZERO
		player_health = 100
		alert_label.text = "ERWISCHT – ZURÜCK AM START"
		update_status()

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
	elif equipped_weapon == "bazooka":
		weapon_name = "Bazooka"
	status.text = ("IM AUTO" if in_car else "ZU FUSS") + " | HP %d | Waffe: %s" % [player_health, weapon_name]
