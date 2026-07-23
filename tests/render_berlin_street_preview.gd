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
	environment.background_color = Color("91a6b5")
	environment.ambient_light_color = Color("e3e7e8")
	environment.ambient_light_energy = 0.72
	world_environment.environment = environment
	stage.add_child(world_environment)

	var sun = DirectionalLight.new()
	sun.rotation_degrees = Vector3(-48, -38, 0)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	stage.add_child(sun)

	var berlin_map = MAP_SCENE.instance()
	stage.add_child(berlin_map)
	var sample = _find_street_facing_building(berlin_map)
	if sample == null:
		printerr("FAIL: no street-facing facade sample found")
		quit(1)
		return

	var bounds = sample.get_aabb()
	var building_center = sample.global_transform.xform(bounds.position + bounds.size * 0.5)
	var road_point = berlin_map.get_nearest_road_point(building_center)
	var building_direction = Vector3(
		building_center.x - road_point.x,
		0.0,
		building_center.z - road_point.z
	).normalized()
	var camera_position = road_point - building_direction * 1.5 + Vector3.UP * 4.8
	var look_target = Vector3(
		building_center.x,
		min(building_center.y, bounds.size.y * 0.38 + 2.0),
		building_center.z
	)

	var camera = Camera.new()
	camera.look_at_from_position(camera_position, look_target, Vector3.UP)
	camera.current = true
	camera.fov = 65.0
	camera.near = 0.2
	camera.far = 2000.0
	stage.add_child(camera)

	for _frame in range(12):
		yield(self, "idle_frame")
	VisualServer.sync()
	var image = get_root().get_texture().get_data()
	image.flip_y()
	var error = image.save_png("/tmp/berlin_street_preview.png")
	if error != OK:
		printerr("FAIL: could not save Berlin street preview (%d)" % error)
		quit(1)
		return
	print(
		"PASS: rendered Berlin street facade %s with variant %d"
		% [sample.name, int(sample.get_meta("facade_variant"))]
	)
	quit(0)


func _find_street_facing_building(berlin_map):
	var best = null
	var best_distance = INF
	for candidate in get_nodes_in_group("destructible"):
		if not (candidate is MeshInstance):
			continue
		var bounds = candidate.get_aabb()
		if bounds.size.y < 12.0 or bounds.size.x < 4.0 or bounds.size.z < 4.0:
			continue
		var center = candidate.global_transform.xform(bounds.position + bounds.size * 0.5)
		var road = berlin_map.get_nearest_road_point(center)
		var road_distance = Vector2(center.x - road.x, center.z - road.z).length()
		if road_distance < 8.0 or road_distance > 28.0:
			continue
		var origin_distance = Vector2(center.x, center.z).length()
		if origin_distance < best_distance:
			best_distance = origin_distance
			best = candidate
	return best
