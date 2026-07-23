extends SceneTree

const MAIN_SCRIPT = preload("res://scripts/main.gd")
const HELICOPTER_SCENE = preload("res://scenes/PlayerHelicopter.tscn")


func _init():
	call_deferred("_render_preview")


func _render_preview():
	var stage = Spatial.new()
	get_root().add_child(stage)

	var world_environment = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("8ea9bf")
	environment.ambient_light_color = Color("dce8ef")
	environment.ambient_light_energy = 0.74
	world_environment.environment = environment
	stage.add_child(world_environment)

	var sun = DirectionalLight.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.20
	sun.shadow_enabled = true
	stage.add_child(sun)

	var ground = MeshInstance.new()
	var ground_mesh = PlaneMesh.new()
	ground_mesh.size = Vector2(28, 28)
	var ground_material = SpatialMaterial.new()
	ground_material.albedo_color = Color("454b50")
	ground_material.roughness = 0.96
	ground_mesh.material = ground_material
	ground.mesh = ground_mesh
	stage.add_child(ground)

	var helicopter = HELICOPTER_SCENE.instance()
	helicopter.name = "PreviewEC135"
	helicopter.translation = Vector3(0, 1.50, 0)
	stage.add_child(helicopter)
	helicopter.set_simulation_enabled(false)
	var helper = MAIN_SCRIPT.new()
	var visual = helper.add_ec135_visual(helicopter)
	helicopter.bind_visuals(visual.get_node_or_null("EC135Model"))
	helicopter.set_collective(0.64)

	var camera = Camera.new()
	camera.translation = Vector3(11.8, 5.7, -15.0)
	camera.look_at_from_position(camera.translation, Vector3(0, 1.6, 0.5), Vector3.UP)
	camera.current = true
	camera.fov = 49.0
	stage.add_child(camera)

	for _frame in range(5):
		yield(self, "idle_frame")
	VisualServer.sync()
	var image = get_root().get_texture().get_data()
	image.flip_y()
	var error = image.save_png("/tmp/ec135_preview.png")
	if error != OK:
		printerr("FAIL: could not save EC135 preview (%d)" % error)
		quit(1)
		return

	# Match sync_player_to_helicopter(): cockpit anchor plus the Camera's
	# 0.65-metre local eye offset, looking along the model's -Z forward axis.
	camera.translation = helicopter.translation + Vector3(0.38, 0.35, -1.90)
	camera.look_at_from_position(camera.translation, camera.translation + Vector3(0, 0, -10), Vector3.UP)
	for _frame in range(3):
		yield(self, "idle_frame")
	VisualServer.sync()
	var cockpit_image = get_root().get_texture().get_data()
	cockpit_image.flip_y()
	var cockpit_error = cockpit_image.save_png("/tmp/ec135_cockpit_preview.png")
	if cockpit_error != OK:
		printerr("FAIL: could not save EC135 cockpit preview (%d)" % cockpit_error)
		quit(1)
		return

	stage.queue_free()
	helper.free()
	yield(self, "idle_frame")
	print("PASS: rendered EC135 exterior and cockpit previews")
	quit(0)
