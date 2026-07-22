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
	ground_mesh.size = Vector2(22, 22)
	var ground_material = SpatialMaterial.new()
	ground_material.albedo_color = Color("4f5962")
	ground_material.roughness = 0.95
	ground_mesh.material = ground_material
	ground.mesh = ground_mesh
	ground.translation.y = 0.05
	stage.add_child(ground)

	var helper = MAIN_SCRIPT.new()
	helper.build_audio()
	var fire_engine = helper.create_emergency_vehicle("fire", Vector3(0, helper.HLF_GROUND_HEIGHT, 0))
	helper.remove_child(fire_engine)
	stage.add_child(fire_engine)
	helper.set_hlf_blue_lights(fire_engine, true, false)

	var camera = Camera.new()
	camera.translation = Vector3(8.6, 4.8, -11.8)
	camera.look_at_from_position(camera.translation, Vector3(0, 1.25, 0), Vector3.UP)
	camera.current = true
	camera.fov = 48.0
	stage.add_child(camera)

	for _frame in range(4):
		yield(self, "idle_frame")
	VisualServer.sync()
	var image = get_root().get_texture().get_data()
	image.flip_y()
	var error = image.save_png("/tmp/hlf_preview.png")
	if error == OK:
		print("PASS: rendered HLF preview")
		quit(0)
	else:
		printerr("FAIL: could not save HLF preview (%d)" % error)
		quit(1)
