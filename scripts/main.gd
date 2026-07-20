extends Spatial

const BERLIN_MAP_SCENE = preload("res://scenes/BerlinMap.tscn")
const HUMAN_SCENE = preload("res://Assets/HumanV2.glb")
const WALK_SPEED = 8.0
const DRIVE_SPEED = 22.0
const GRAVITY = 24.0

var player: KinematicBody
var camera: Camera
var car: KinematicBody
var car_body: MeshInstance
var pistol_model: Spatial
var velocity = Vector3.ZERO
var car_speed = 0.0
var look_x = 0.0
var in_car = false
var pistol_equipped = false
var prompt: Label
var status: Label
var crosshair: Label
var npcs = []

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	build_world()
	build_player()
	build_car()
	build_npcs()
	build_ui()

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
	status.text = "ZU FUSS | Pistole: nicht ausgerüstet"
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
	var help = Label.new()
	help.anchor_top = 1.0
	help.rect_position = Vector2(18, -48)
	help.text = "WASD Bewegen/Fahren  •  Maus Umsehen  •  E Ein-/Aussteigen  •  1 Pistole  •  Klick Schießen  •  Esc Maus lösen"
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
		pistol_equipped = not pistol_equipped
		pistol_model.visible = pistol_equipped
		crosshair.visible = pistol_equipped
		update_status()
	if event.is_action_pressed("shoot") and pistol_equipped and not in_car:
		shoot()

func _physics_process(delta):
	if in_car:
		drive(delta)
	else:
		walk(delta)
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
		pistol_equipped = false
		pistol_model.visible = false
		crosshair.visible = false
		player.get_node("CollisionShape").disabled = true
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
		var health = int(target.get_meta("health")) - 1
		target.set_meta("health", health)
		prompt.text = "Treffer!"
		if health <= 0:
			npcs.erase(target)
			target.queue_free()
			prompt.text = "NPC ausgeschaltet"

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
	status.text = ("IM AUTO" if in_car else "ZU FUSS") + " | Pistole: " + ("ausgerüstet" if pistol_equipped else "nicht ausgerüstet")
