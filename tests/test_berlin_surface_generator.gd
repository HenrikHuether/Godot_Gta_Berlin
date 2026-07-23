extends SceneTree

const GENERATOR_SCRIPT = preload("res://scripts/berlin_surface_generator.gd")
const NETWORK_PATH = "res://Assets/Maps/berlin_network.json"

var failures := []


func _init():
	call_deferred("_run")


func _run():
	var generator = GENERATOR_SCRIPT.new()
	generator.name = "Generator"
	get_root().add_child(generator)

	_expect(generator.build_from_file(NETWORK_PATH), "network JSON should build successfully")
	var diagnostics = generator.get_diagnostics()
	_expect(diagnostics.built, "diagnostics should report a completed build")
	_expect(int(diagnostics.street_vertex_count) == 231, "Street graph should retain all 231 vertices")
	_expect(int(diagnostics.street_edge_count) == 285, "Street graph should retain all 285 edges")
	_expect(bool(diagnostics.street_connected), "Street graph should remain connected")
	_expect(int(diagnostics.street_intersection_count) == 102, "Street graph should expose all 102 intersections")
	_expect(abs(float(diagnostics.street_total_length_m) - 76600.0) < 300.0, "Street length should remain approximately 76.6 km")
	_expect(int(diagnostics.canal_vertex_count) == 57, "Kanal graph should retain all 57 vertices")
	_expect(int(diagnostics.canal_edge_count) == 56, "Kanal graph should retain all 56 edges")
	_expect(bool(diagnostics.canal_connected), "Kanal graph should remain connected")
	_expect(abs(float(diagnostics.canal_total_length_m) - 19400.0) < 300.0, "Kanal length should remain approximately 19.4 km")
	_expect(int(diagnostics.road_chunk_count) > 0, "road generation should create chunks")
	_expect(int(diagnostics.canal_chunk_count) > 0, "canal generation should create chunks")
	_expect(int(diagnostics.road_triangle_count) > 285 * 2, "roads should include subdivided bands and round joints")
	_expect(int(diagnostics.road_detail_triangle_count) > int(diagnostics.road_surface_triangle_count), "realistic road details should add more geometry than the asphalt base")
	_expect(int(diagnostics.road_sidewalk_triangle_count) > 0, "roads should generate paired sidewalks")
	_expect(int(diagnostics.road_curb_triangle_count) > 0, "roads should generate raised curbs")
	_expect(int(diagnostics.road_marking_triangle_count) > 1000, "roads should generate repeated German lane markings")
	_expect(int(diagnostics.road_crosswalk_count) > 0, "major intersections should generate zebra crossings")
	_expect(int(diagnostics.canal_triangle_count) > 56 * 2, "canal should include subdivided bands and round joints")

	var road_root = generator.get_node_or_null("RoadChunks")
	var canal_root = generator.get_node_or_null("CanalChunks")
	_expect(road_root is Spatial and road_root.get_child_count() == int(diagnostics.road_chunk_count), "RoadChunks should own every generated road chunk")
	_expect(canal_root is Spatial and canal_root.get_child_count() == int(diagnostics.canal_chunk_count), "CanalChunks should own every generated canal chunk")

	var road_body = _find_first_type(road_root, "StaticBody")
	_expect(road_body is StaticBody, "road chunks should contain StaticBody collisions")
	if road_body is StaticBody:
		_expect(road_body.collision_layer == 2, "road collision should use its dedicated non-player layer")
		_expect(road_body.collision_mask == 0, "road collision should not detect the player or snag its capsule")
		_expect(abs(float(road_body.get_meta("surface_grip")) - 1.02) < 0.001, "road collision should expose asphalt grip")
		_expect(abs(float(road_body.get_meta("rolling_resistance")) - 1.0) < 0.001, "road collision should expose rolling resistance")
		var road_collision = _find_first_type(road_body, "CollisionShape")
		_expect(road_collision is CollisionShape and road_collision.shape is ConcavePolygonShape, "road collision should use a generated trimesh")

	var detailed_road_mesh = _find_mesh_with_surfaces(road_root, 4)
	_expect(detailed_road_mesh is MeshInstance, "road chunks should batch asphalt, sidewalk, curb, and markings as mesh surfaces")
	if detailed_road_mesh is MeshInstance:
		var material_names = []
		for surface_index in range(detailed_road_mesh.mesh.get_surface_count()):
			var surface_material = detailed_road_mesh.mesh.surface_get_material(surface_index)
			material_names.append(surface_material.resource_name if surface_material else "")
		_expect(material_names.has("Generated Berlin Asphalt"), "road visual should retain the asphalt material")
		_expect(material_names.has("Generated Berlin Sidewalk Pavers"), "road visual should include paved sidewalks")
		_expect(material_names.has("Generated Berlin Granite Curbs"), "road visual should include granite curbs")
		_expect(material_names.has("Generated German Road Markings"), "road visual should include white German markings")
		var asphalt_material = detailed_road_mesh.mesh.surface_get_material(0)
		_expect(asphalt_material is SpatialMaterial and asphalt_material.albedo_texture is Texture, "asphalt should use a repeatable detailed aggregate texture")
		if asphalt_material is SpatialMaterial and asphalt_material.albedo_texture is Texture:
			_expect(asphalt_material.albedo_texture.resource_name == "Berlin Asphalt Generated Asset", "asphalt should use the generated Berlin texture asset")
			_expect(asphalt_material.albedo_texture.get_width() >= 1024, "Berlin asphalt texture should retain enough detail for close street views")
			_expect(bool(asphalt_material.albedo_texture.get_flags() & Texture.FLAG_REPEAT), "asphalt texture should repeat instead of stretching over Berlin")
			_expect(asphalt_material.params_cull_mode == SpatialMaterial.CULL_DISABLED, "thin asphalt bands should remain visible from above")
		_expect(detailed_road_mesh.get_aabb().size.y >= 0.13, "raised curbs should give road chunks visible vertical relief")

	var water_area = _find_first_type(canal_root, "Area")
	_expect(water_area is Area, "canal chunks should contain water trigger Areas")
	_expect(_find_first_type(canal_root, "StaticBody") == null, "canal must never create a solid StaticBody")
	if water_area is Area:
		_expect(water_area.collision_layer == 16, "water Area should use its dedicated collision layer")
		_expect(_find_first_type(water_area, "CollisionShape") is CollisionShape, "water Area should contain BoxShape triggers")

	var nearest = generator.get_nearest_road_point(Vector3(0.0, 120.0, 0.0))
	_expect(abs(nearest.y) < 0.001, "nearest road projection should return the graph elevation")
	var route = generator.get_route(Vector3(2.8, 0.0, -0.3), Vector3(-5509.8, 0.0, 1060.0))
	_expect(route.size() > 2, "AStar should return a multi-point route across Berlin")
	var response_route = generator.get_response_route(Vector3.ZERO, 0)
	_expect(response_route.size() >= 2, "response route should return its complete waypoint path")
	if response_route.size() >= 2:
		var response_distance = 0.0
		for route_index in range(1, response_route.size()):
			response_distance += response_route[route_index - 1].distance_to(response_route[route_index])
		_expect(response_distance > 10.0 and response_distance <= 65.1, "response spawn should be approximately 65 m along the road network")
		var expected_target = generator.get_nearest_road_point(Vector3.ZERO)
		_expect(response_route[-1].distance_to(expected_target) < 0.01, "response route should end at the road point nearest the incident")

	var road_count_before = road_root.get_child_count() if road_root else -1
	var canal_count_before = canal_root.get_child_count() if canal_root else -1
	_expect(generator.build_from_file(NETWORK_PATH), "a second build request should be a successful no-op")
	_expect(road_root.get_child_count() == road_count_before, "idempotent build should not duplicate road chunks")
	_expect(canal_root.get_child_count() == canal_count_before, "idempotent build should not duplicate canal chunks")

	if failures.empty():
		print("PASS: Berlin street graph, chunked asphalt, canal water, collisions, and AStar routing")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)


func _find_first_type(root, class_name_value: String):
	if root == null:
		return null
	if root.get_class() == class_name_value:
		return root
	for child in root.get_children():
		var found = _find_first_type(child, class_name_value)
		if found != null:
			return found
	return null


func _find_mesh_with_surfaces(root, minimum_surface_count: int):
	if root == null:
		return null
	if root is MeshInstance and root.mesh != null and root.mesh.get_surface_count() >= minimum_surface_count:
		return root
	for child in root.get_children():
		var found = _find_mesh_with_surfaces(child, minimum_surface_count)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String):
	if not condition:
		failures.append(message)
