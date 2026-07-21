extends SceneTree

const MAIN_SCRIPT = preload("res://scripts/main.gd")


func _init():
	call_deferred("_render_preview")


func _render_preview():
	var stage = Spatial.new()
	get_root().add_child(stage)

	var world_environment = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("91abc2")
	environment.ambient_light_color = Color("dce8f2")
	environment.ambient_light_energy = 0.72
	world_environment.environment = environment
	stage.add_child(world_environment)

	var sun = DirectionalLight.new()
	sun.rotation_degrees = Vector3(-52, -28, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	stage.add_child(sun)

	var ground = MeshInstance.new()
	var ground_mesh = PlaneMesh.new()
	ground_mesh.size = Vector2(16, 16)
	var ground_material = SpatialMaterial.new()
	ground_material.albedo_color = Color("4f5962")
	ground_material.roughness = 0.95
	ground_mesh.material = ground_material
	ground.mesh = ground_mesh
	stage.add_child(ground)

	var helper = MAIN_SCRIPT.new()
	var normal_golf = KinematicBody.new()
	normal_golf.translation = Vector3(-2.25, helper.GOLF_GROUND_HEIGHT, 0)
	stage.add_child(normal_golf)
	helper.add_golf_visual(normal_golf)
	helper.add_golf_collision(normal_golf)

	var police_golf = helper.create_emergency_vehicle("police", Vector3(2.25, helper.GOLF_GROUND_HEIGHT, 0))
	helper.remove_child(police_golf)
	stage.add_child(police_golf)

	var camera = Camera.new()
	camera.translation = Vector3(7.6, 4.1, -10.4)
	camera.look_at_from_position(camera.translation, Vector3(0, 0.62, 0), Vector3.UP)
	camera.current = true
	camera.fov = 48.0
	stage.add_child(camera)

	for _frame in range(4):
		yield(self, "idle_frame")
	VisualServer.sync()
	var image = get_root().get_texture().get_data()
	image.flip_y()
	var error = image.save_png("/tmp/golf7_preview.png")
	if error == OK:
		print("PASS: rendered Golf7 preview")
		quit(0)
	else:
		printerr("FAIL: could not save Golf7 preview (%d)" % error)
		quit(1)
