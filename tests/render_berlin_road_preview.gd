extends SceneTree

const GENERATOR_SCRIPT = preload("res://scripts/berlin_surface_generator.gd")


func _init():
	call_deferred("_render_preview")


func _render_preview():
	var stage = Spatial.new()
	get_root().add_child(stage)

	var environment_node = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("91a6b5")
	environment.ambient_light_color = Color("dfe5e8")
	environment.ambient_light_energy = 0.64
	environment_node.environment = environment
	stage.add_child(environment_node)

	var sun = DirectionalLight.new()
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	stage.add_child(sun)

	var generator = GENERATOR_SCRIPT.new()
	stage.add_child(generator)
	if not generator.build_from_file():
		printerr("FAIL: street graph could not be generated")
		quit(1)
		return

	var intersection = _nearest_major_intersection(generator)
	var ground = MeshInstance.new()
	var ground_mesh = PlaneMesh.new()
	ground_mesh.size = Vector2(240.0, 240.0)
	var ground_material = SpatialMaterial.new()
	ground_material.albedo_color = Color("596552")
	ground_material.roughness = 0.96
	ground_mesh.material = ground_material
	ground.mesh = ground_mesh
	ground.translation = intersection + Vector3.DOWN * 0.02
	stage.add_child(ground)

	var camera = Camera.new()
	var camera_position = intersection + Vector3(34.0, 24.0, 38.0)
	camera.look_at_from_position(camera_position, intersection + Vector3.UP * 0.2, Vector3.UP)
	camera.current = true
	camera.fov = 55.0
	camera.near = 0.2
	camera.far = 3000.0
	stage.add_child(camera)

	for _frame in range(10):
		yield(self, "idle_frame")
	VisualServer.sync()
	var image = get_root().get_texture().get_data()
	image.flip_y()
	var error = image.save_png("/tmp/berlin_road_preview.png")
	if error != OK:
		printerr("FAIL: could not save Berlin road preview (%d)" % error)
		quit(1)
		return
	print("PASS: rendered realistic Berlin intersection at %s" % intersection)
	quit(0)


func _nearest_major_intersection(generator) -> Vector3:
	var best = Vector3.ZERO
	var best_distance = INF
	for point_index in range(generator._street_points.size()):
		if int(generator._street_degrees[point_index]) < 3:
			continue
		var point = generator._street_points[point_index]
		var distance = Vector2(point.x, point.z).length()
		if distance < best_distance:
			best_distance = distance
			best = point
	return best
