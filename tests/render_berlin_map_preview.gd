extends SceneTree

const MAP_SCENE = preload("res://scenes/BerlinSegmentedMap.tscn")


func _init():
	call_deferred("_render_preview")


func _render_preview():
	var stage = Spatial.new()
	get_root().add_child(stage)

	var world_environment = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("8baac3")
	environment.ambient_light_color = Color("dce7ed")
	environment.ambient_light_energy = 0.78
	world_environment.environment = environment
	stage.add_child(world_environment)

	var sun = DirectionalLight.new()
	sun.rotation_degrees = Vector3(-52, -34, 0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	stage.add_child(sun)

	var berlin_map = MAP_SCENE.instance()
	stage.add_child(berlin_map)

	var camera = Camera.new()
	camera.translation = Vector3(1180, 1320, 1650)
	camera.look_at_from_position(camera.translation, Vector3(-260, 0, -380), Vector3.UP)
	camera.current = true
	camera.fov = 58.0
	camera.near = 1.0
	camera.far = 20000.0
	stage.add_child(camera)

	for _frame in range(8):
		yield(self, "idle_frame")
	VisualServer.sync()
	var image = get_root().get_texture().get_data()
	image.flip_y()
	var error = image.save_png("/tmp/berlin_map_preview.png")
	if error != OK:
		printerr("FAIL: could not save Berlin map preview (%d)" % error)
		quit(1)
		return

	var generator = berlin_map.get_node_or_null("Generator")
	var diagnostics = generator.get_diagnostics() if is_instance_valid(generator) else {}
	print(
		"PASS: rendered segmented Berlin map (%d road chunks, %d canal chunks)"
		% [
			int(diagnostics.get("road_chunk_count", 0)),
			int(diagnostics.get("canal_chunk_count", 0))
		]
	)
	quit(0)
