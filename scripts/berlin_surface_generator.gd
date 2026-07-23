extends Spatial
class_name BerlinSurfaceGenerator

const DEFAULT_NETWORK_PATH := "res://Assets/Maps/berlin_network.json"
const ROAD_ASPHALT_TEXTURE_PATH := "res://Assets/Textures/berlin_asphalt.png"

const ROAD_WIDTH := 14.0
const ROAD_ELEVATION := 0.06
const ROAD_COLLISION_LAYER := 2
const ROAD_COLLISION_MASK := 0
const ROAD_SURFACE_GRIP := 1.02
const ROAD_ROLLING_RESISTANCE := 1.0
const SIDEWALK_WIDTH := 2.45
const CURB_HEIGHT := 0.14
const CURB_FACE_OFFSET := 0.008
const SIDEWALK_JOINT_TRIM := 0.35
const INTERSECTION_SIDEWALK_SETBACK := 10.5
const MARKING_ELEVATION := 0.018
const MARKING_WIDTH := 0.16
const MARKING_DASH_LENGTH := 3.0
const MARKING_DASH_GAP := 6.0
const INTERSECTION_MARKING_SETBACK := 12.0
const CROSSWALK_OFFSET := 8.8
const CROSSWALK_STRIPE_WIDTH := 0.48
const CROSSWALK_STRIPE_GAP := 0.42
const CROSSWALK_STRIPE_COUNT := 5
const CROSSWALK_SIDE_MARGIN := 0.7

const CANAL_WIDTH := 48.0
const CANAL_ELEVATION := 0.035
const WATER_COLLISION_LAYER := 16
const WATER_COLLISION_MASK := 1
const WATER_TRIGGER_DEPTH := 4.0
const WATER_TRIGGER_TOP_OFFSET := 0.20

const CHUNK_SIZE := 512.0
const MAX_SEGMENT_LENGTH := 96.0
const JOINT_SEGMENTS := 16
const ROAD_UV_SCALE := 0.08
const RESPONSE_SPAWN_DISTANCE := 65.0
const POINT_EPSILON_SQUARED := 0.0001

var _built := false
var _source_path := ""
var _last_error := ""

var _street_points := PoolVector3Array()
var _street_edges := []
var _street_degrees := []
var _street_adjacency := []
var _canal_points := PoolVector3Array()
var _canal_edges := []
var _canal_degrees := []
var _road_astar := AStar.new()

var _road_chunks_root: Spatial
var _canal_chunks_root: Spatial
var _road_material: SpatialMaterial
var _sidewalk_material: SpatialMaterial
var _curb_material: SpatialMaterial
var _road_marking_material: SpatialMaterial
var _water_material: SpatialMaterial
var _road_physics_material: PhysicsMaterial
var _diagnostics := {"built": false, "error": ""}


func build_from_file(path: String = DEFAULT_NETWORK_PATH) -> bool:
	if _built:
		return true

	_last_error = ""
	var file = File.new()
	if not file.file_exists(path):
		return _fail("Berlin network file does not exist: %s" % path)
	var open_error = file.open(path, File.READ)
	if open_error != OK:
		return _fail("Berlin network file could not be opened (%d): %s" % [open_error, path])
	var json_text = file.get_as_text()
	file.close()

	var parse_result = JSON.parse(json_text)
	if parse_result.error != OK:
		return _fail(
			"Berlin network JSON error on line %d: %s"
			% [parse_result.error_line, parse_result.error_string]
		)
	if typeof(parse_result.result) != TYPE_DICTIONARY:
		return _fail("Berlin network root must be a Dictionary")

	var document: Dictionary = parse_result.result
	var graphs = document.get("graphs", null)
	if typeof(graphs) != TYPE_DICTIONARY:
		return _fail("Berlin network JSON has no graphs Dictionary")

	var street_graph = _parse_graph(graphs.get("street", null), "street")
	if street_graph.empty():
		return false
	var canal_graph = _parse_graph(graphs.get("kanal", null), "kanal")
	if canal_graph.empty():
		return false

	_street_points = street_graph.points
	_street_edges = street_graph.edges
	_street_degrees = street_graph.degrees
	_street_adjacency = street_graph.adjacency
	_canal_points = canal_graph.points
	_canal_edges = canal_graph.edges
	_canal_degrees = canal_graph.degrees
	_build_road_astar()

	_source_path = path
	_create_resources()
	_create_generated_roots()

	var road_builders = {}
	var road_segment_count = _emit_graph_bands(
		road_builders,
		_street_points,
		_street_edges,
		ROAD_WIDTH,
		ROAD_ELEVATION,
		_road_material,
		false
	)
	_emit_graph_joints(
		road_builders,
		_street_points,
		_street_degrees,
		ROAD_WIDTH,
		ROAD_ELEVATION,
		_road_material,
		false
	)
	var road_detail_result = _emit_road_details(
		road_builders,
		_street_points,
		_street_edges,
		_street_degrees
	)
	var road_result = _commit_road_chunks(road_builders)
	if not road_result.ok:
		clear_generated()
		return _fail(road_result.error)

	var canal_builders = {}
	var canal_segment_count = _emit_graph_bands(
		canal_builders,
		_canal_points,
		_canal_edges,
		CANAL_WIDTH,
		CANAL_ELEVATION,
		_water_material,
		true
	)
	_emit_graph_joints(
		canal_builders,
		_canal_points,
		_canal_degrees,
		CANAL_WIDTH,
		CANAL_ELEVATION,
		_water_material,
		true
	)
	var canal_result = _commit_canal_chunks(canal_builders)
	if not canal_result.ok:
		clear_generated()
		return _fail(canal_result.error)

	_built = true
	_diagnostics = {
		"built": true,
		"error": "",
		"source_path": path,
		"street_vertex_count": _street_points.size(),
		"street_edge_count": _street_edges.size(),
		"street_total_length_m": street_graph.total_length,
		"street_connected": street_graph.connected,
		"street_intersection_count": _count_intersections(_street_degrees),
		"road_segment_count": road_segment_count,
		"road_triangle_count": road_result.triangle_count,
		"road_surface_triangle_count": road_result.surface_triangle_count,
		"road_detail_triangle_count": road_result.detail_triangle_count,
		"road_chunk_count": road_result.chunk_count,
		"road_sidewalk_triangle_count": road_detail_result.sidewalk_triangle_count,
		"road_curb_triangle_count": road_detail_result.curb_triangle_count,
		"road_marking_triangle_count": road_detail_result.marking_triangle_count,
		"road_crosswalk_count": road_detail_result.crosswalk_count,
		"canal_vertex_count": _canal_points.size(),
		"canal_edge_count": _canal_edges.size(),
		"canal_total_length_m": canal_graph.total_length,
		"canal_connected": canal_graph.connected,
		"canal_segment_count": canal_segment_count,
		"canal_triangle_count": canal_result.triangle_count,
		"canal_chunk_count": canal_result.chunk_count,
		"water_trigger_count": canal_result.trigger_count
	}
	return true


func clear_generated() -> void:
	for generated_root in [_road_chunks_root, _canal_chunks_root]:
		if is_instance_valid(generated_root):
			if generated_root.get_parent() == self:
				remove_child(generated_root)
			generated_root.queue_free()

	_road_chunks_root = null
	_canal_chunks_root = null
	_road_material = null
	_sidewalk_material = null
	_curb_material = null
	_road_marking_material = null
	_water_material = null
	_road_physics_material = null
	_street_points = PoolVector3Array()
	_street_edges.clear()
	_street_degrees.clear()
	_street_adjacency.clear()
	_canal_points = PoolVector3Array()
	_canal_edges.clear()
	_canal_degrees.clear()
	_road_astar = AStar.new()
	_built = false
	_source_path = ""
	_last_error = ""
	_diagnostics = {"built": false, "error": ""}


func is_built() -> bool:
	return _built


func get_nearest_road_point(world_position: Vector3) -> Vector3:
	if not _built or _street_edges.empty():
		return world_position
	var nearest = _nearest_street_edge(to_local(world_position))
	if int(nearest.edge_index) < 0:
		return world_position
	return to_global(nearest.point)


func get_route(world_start: Vector3, world_end: Vector3) -> PoolVector3Array:
	var result = PoolVector3Array()
	if not _built or _street_edges.empty():
		return result

	var start_info = _nearest_street_edge(to_local(world_start))
	var end_info = _nearest_street_edge(to_local(world_end))
	if int(start_info.edge_index) < 0 or int(end_info.edge_index) < 0:
		return result

	if int(start_info.edge_index) == int(end_info.edge_index):
		result.append(to_global(start_info.point))
		if start_info.point.distance_squared_to(end_info.point) > POINT_EPSILON_SQUARED:
			result.append(to_global(end_info.point))
		return result

	var start_ids = [int(start_info.a_id), int(start_info.b_id)]
	var end_ids = [int(end_info.a_id), int(end_info.b_id)]
	var best_cost = INF
	var best_points = []

	for start_id in start_ids:
		for end_id in end_ids:
			var graph_path = PoolVector3Array()
			if start_id == end_id:
				graph_path.append(_street_points[start_id])
			else:
				graph_path = _road_astar.get_point_path(start_id, end_id)
			if graph_path.empty():
				continue

			var cost = start_info.point.distance_to(_street_points[start_id])
			cost += _pool_path_length(graph_path)
			cost += end_info.point.distance_to(_street_points[end_id])
			if cost >= best_cost:
				continue

			best_cost = cost
			best_points.clear()
			_append_unique(best_points, start_info.point)
			for path_point in graph_path:
				_append_unique(best_points, path_point)
			_append_unique(best_points, end_info.point)

	for local_point in best_points:
		result.append(to_global(local_point))
	return result


func get_response_route(incident: Vector3, variant: int) -> Array:
	if not _built or _street_edges.empty():
		return [incident, incident]

	var nearest = _nearest_street_edge(to_local(incident))
	if int(nearest.edge_index) < 0:
		return [incident, incident]

	var first_walk = _walk_from_projection(
		nearest.point,
		int(nearest.a_id),
		int(nearest.b_id),
		RESPONSE_SPAWN_DISTANCE,
		variant
	)
	var second_walk = _walk_from_projection(
		nearest.point,
		int(nearest.b_id),
		int(nearest.a_id),
		RESPONSE_SPAWN_DISTANCE,
		variant + 1
	)

	var even_variant = int(abs(variant)) % 2 == 0
	var chosen = first_walk if even_variant else second_walk
	var alternate = second_walk if even_variant else first_walk
	if float(chosen.travelled) < RESPONSE_SPAWN_DISTANCE - 0.01 and float(alternate.travelled) > float(chosen.travelled):
		chosen = alternate

	var spawn_world = to_global(chosen.point)
	var target_world = to_global(nearest.point)
	var graph_path = get_route(spawn_world, incident)
	if graph_path.size() >= 2:
		var response_path = []
		for route_point in graph_path:
			response_path.append(route_point)
		return response_path
	return [spawn_world, target_world]


func get_diagnostics() -> Dictionary:
	var result = _diagnostics.duplicate(true)
	result["built"] = _built
	result["error"] = _last_error
	return result


func _parse_graph(raw_graph, graph_name: String) -> Dictionary:
	if typeof(raw_graph) != TYPE_DICTIONARY:
		_fail("Berlin network graph '%s' is missing or invalid" % graph_name)
		return {}

	var raw_vertices = raw_graph.get("vertices", null)
	var raw_edges = raw_graph.get("edges", null)
	if typeof(raw_vertices) != TYPE_ARRAY or raw_vertices.empty():
		_fail("Berlin network graph '%s' has no vertices" % graph_name)
		return {}
	if typeof(raw_edges) != TYPE_ARRAY or raw_edges.empty():
		_fail("Berlin network graph '%s' has no edges" % graph_name)
		return {}

	var points = PoolVector3Array()
	for vertex_index in range(raw_vertices.size()):
		var raw_vertex = raw_vertices[vertex_index]
		if typeof(raw_vertex) != TYPE_ARRAY or raw_vertex.size() < 3:
			_fail("Graph '%s' vertex %d is not a three-component Array" % [graph_name, vertex_index])
			return {}
		if not _is_number(raw_vertex[0]) or not _is_number(raw_vertex[1]) or not _is_number(raw_vertex[2]):
			_fail("Graph '%s' vertex %d contains a non-numeric component" % [graph_name, vertex_index])
			return {}
		points.append(Vector3(float(raw_vertex[0]), float(raw_vertex[1]), float(raw_vertex[2])))

	var edges = []
	var degrees = []
	var adjacency = []
	degrees.resize(points.size())
	adjacency.resize(points.size())
	for point_index in range(points.size()):
		degrees[point_index] = 0
		adjacency[point_index] = []

	var edge_keys = {}
	var total_length = 0.0
	for edge_index in range(raw_edges.size()):
		var raw_edge = raw_edges[edge_index]
		if typeof(raw_edge) != TYPE_ARRAY or raw_edge.size() < 2:
			_fail("Graph '%s' edge %d is not a two-component Array" % [graph_name, edge_index])
			return {}
		if not _is_number(raw_edge[0]) or not _is_number(raw_edge[1]):
			_fail("Graph '%s' edge %d contains a non-numeric index" % [graph_name, edge_index])
			return {}
		var a_id = int(raw_edge[0])
		var b_id = int(raw_edge[1])
		if a_id < 0 or b_id < 0 or a_id >= points.size() or b_id >= points.size() or a_id == b_id:
			_fail("Graph '%s' edge %d has invalid vertex indices" % [graph_name, edge_index])
			return {}

		var edge_key = _edge_key(a_id, b_id)
		if edge_keys.has(edge_key):
			continue
		edge_keys[edge_key] = true
		edges.append([a_id, b_id])
		degrees[a_id] = int(degrees[a_id]) + 1
		degrees[b_id] = int(degrees[b_id]) + 1
		adjacency[a_id].append(b_id)
		adjacency[b_id].append(a_id)
		total_length += points[a_id].distance_to(points[b_id])

	if edges.empty():
		_fail("Berlin network graph '%s' has no usable edges" % graph_name)
		return {}
	for neighbors in adjacency:
		neighbors.sort()

	return {
		"points": points,
		"edges": edges,
		"degrees": degrees,
		"adjacency": adjacency,
		"total_length": total_length,
		"connected": _is_graph_connected(adjacency)
	}


func _is_number(value) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_REAL


func _is_graph_connected(adjacency: Array) -> bool:
	if adjacency.empty():
		return false
	var visited = {}
	var stack = [0]
	while not stack.empty():
		var point_id = int(stack.pop_back())
		if visited.has(point_id):
			continue
		visited[point_id] = true
		for neighbor in adjacency[point_id]:
			if not visited.has(int(neighbor)):
				stack.append(int(neighbor))
	return visited.size() == adjacency.size()


func _build_road_astar() -> void:
	_road_astar = AStar.new()
	for point_id in range(_street_points.size()):
		_road_astar.add_point(point_id, _street_points[point_id])
	for edge in _street_edges:
		var a_id = int(edge[0])
		var b_id = int(edge[1])
		if not _road_astar.are_points_connected(a_id, b_id):
			_road_astar.connect_points(a_id, b_id, true)


func _create_resources() -> void:
	_road_material = SpatialMaterial.new()
	_road_material.resource_name = "Generated Berlin Asphalt"
	_road_material.albedo_color = Color("d2d2d0")
	_road_material.albedo_texture = _create_asphalt_texture()
	_road_material.uv1_scale = Vector3(5.5, 5.5, 5.5)
	_road_material.roughness = 0.94
	_road_material.metallic = 0.0
	_road_material.params_cull_mode = SpatialMaterial.CULL_DISABLED

	_sidewalk_material = SpatialMaterial.new()
	_sidewalk_material.resource_name = "Generated Berlin Sidewalk Pavers"
	_sidewalk_material.albedo_color = Color("a4a29b")
	_sidewalk_material.albedo_texture = _create_sidewalk_texture()
	_sidewalk_material.uv1_scale = Vector3(24.0, 24.0, 24.0)
	_sidewalk_material.roughness = 0.91
	_sidewalk_material.metallic = 0.0
	_sidewalk_material.params_cull_mode = SpatialMaterial.CULL_DISABLED

	_curb_material = SpatialMaterial.new()
	_curb_material.resource_name = "Generated Berlin Granite Curbs"
	_curb_material.albedo_color = Color("aaa9a3")
	_curb_material.roughness = 0.87
	_curb_material.metallic = 0.0
	_curb_material.params_cull_mode = SpatialMaterial.CULL_DISABLED

	_road_marking_material = SpatialMaterial.new()
	_road_marking_material.resource_name = "Generated German Road Markings"
	_road_marking_material.albedo_color = Color("e9e7dc")
	_road_marking_material.roughness = 0.76
	_road_marking_material.metallic = 0.0
	_road_marking_material.params_cull_mode = SpatialMaterial.CULL_DISABLED

	_water_material = SpatialMaterial.new()
	_water_material.resource_name = "Generated Berlin Water"
	_water_material.flags_transparent = true
	_water_material.albedo_color = Color(0.045, 0.22, 0.31, 0.76)
	_water_material.roughness = 0.18
	_water_material.metallic = 0.04
	_water_material.params_cull_mode = SpatialMaterial.CULL_DISABLED
	_water_material.params_depth_draw_mode = SpatialMaterial.DEPTH_DRAW_ALPHA_OPAQUE_PREPASS

	_road_physics_material = PhysicsMaterial.new()
	_road_physics_material.resource_name = "Generated Berlin Asphalt Physics"
	_road_physics_material.friction = 1.0
	_road_physics_material.rough = true
	_road_physics_material.bounce = 0.0


func _create_asphalt_texture() -> ImageTexture:
	if ResourceLoader.exists(ROAD_ASPHALT_TEXTURE_PATH):
		var imported_texture = load(ROAD_ASPHALT_TEXTURE_PATH) as Texture
		if imported_texture != null:
			var imported_image = imported_texture.get_data()
			if imported_image != null and imported_image.get_width() > 0:
				if imported_image.is_compressed():
					imported_image.decompress()
				if imported_image.get_width() != 1024 or imported_image.get_height() != 1024:
					imported_image.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
				if not imported_image.has_mipmaps():
					imported_image.generate_mipmaps()
				var imported_repeat_texture = ImageTexture.new()
				imported_repeat_texture.resource_name = "Berlin Asphalt Generated Asset"
				imported_repeat_texture.create_from_image(
					imported_image,
					Texture.FLAG_MIPMAPS
					| Texture.FLAG_REPEAT
					| Texture.FLAG_FILTER
					| Texture.FLAG_ANISOTROPIC_FILTER
				)
				return imported_repeat_texture

	var size = 128
	var image = Image.new()
	image.create(size, size, false, Image.FORMAT_RGB8)
	image.lock()
	for y in range(size):
		for x in range(size):
			var broad = sin(TAU * float(x) / 64.0) * 0.035
			broad += cos(TAU * float(y) / 43.0) * 0.025
			broad += sin(TAU * float(x + y) / 31.0) * 0.018
			var grain = _texture_hash(x, y)
			var shade = 0.76 + broad + (grain - 0.5) * 0.105
			var fleck = _texture_hash(x * 7 + 19, y * 11 + 31)
			if fleck > 0.985:
				shade += 0.12
			elif fleck < 0.012:
				shade -= 0.10
			shade = clamp(shade, 0.55, 0.96)
			image.set_pixel(x, y, Color(shade * 0.93, shade * 0.96, shade))
	image.unlock()

	var texture = ImageTexture.new()
	texture.resource_name = "Procedural Asphalt Aggregate"
	texture.create_from_image(
		image,
		Texture.FLAG_MIPMAPS | Texture.FLAG_REPEAT | Texture.FLAG_FILTER | Texture.FLAG_ANISOTROPIC_FILTER
	)
	return texture


func _create_sidewalk_texture() -> ImageTexture:
	var size = 128
	var image = Image.new()
	image.create(size, size, false, Image.FORMAT_RGB8)
	image.lock()
	for y in range(size):
		var row = int(floor(float(y) / 16.0))
		for x in range(size):
			var shifted_x = (x + (16 if row % 2 != 0 else 0)) % 32
			var mortar = shifted_x < 2 or y % 16 < 2
			var grain = _texture_hash(x + 211, y + 467)
			var shade = 0.37 if mortar else 0.70 + (grain - 0.5) * 0.09
			image.set_pixel(x, y, Color(shade * 0.98, shade * 0.97, shade * 0.94))
	image.unlock()

	var texture = ImageTexture.new()
	texture.resource_name = "Procedural Berlin Sidewalk Pavers"
	texture.create_from_image(
		image,
		Texture.FLAG_MIPMAPS | Texture.FLAG_REPEAT | Texture.FLAG_FILTER | Texture.FLAG_ANISOTROPIC_FILTER
	)
	return texture


func _texture_hash(x: int, y: int) -> float:
	var value = int(x) * 374761393 + int(y) * 668265263 + 1442695041
	value = (value ^ (value >> 13)) * 1274126177
	value = value ^ (value >> 16)
	return float(value & 0x7fffffff) / 2147483647.0


func _create_generated_roots() -> void:
	_road_chunks_root = Spatial.new()
	_road_chunks_root.name = "RoadChunks"
	add_child(_road_chunks_root)

	_canal_chunks_root = Spatial.new()
	_canal_chunks_root.name = "CanalChunks"
	add_child(_canal_chunks_root)


func _emit_graph_bands(
	builders: Dictionary,
	points: PoolVector3Array,
	edges: Array,
	width: float,
	elevation: float,
	surface_material: SpatialMaterial,
	add_water_triggers: bool
) -> int:
	var emitted_segments = 0
	for edge in edges:
		var edge_start: Vector3 = points[int(edge[0])]
		var edge_end: Vector3 = points[int(edge[1])]
		var horizontal_length = Vector2(edge_end.x - edge_start.x, edge_end.z - edge_start.z).length()
		if horizontal_length < 0.001:
			continue
		var part_count = max(1, int(ceil(horizontal_length / MAX_SEGMENT_LENGTH)))
		for part_index in range(part_count):
			var start_weight = float(part_index) / float(part_count)
			var end_weight = float(part_index + 1) / float(part_count)
			var part_start = edge_start.linear_interpolate(edge_end, start_weight)
			var part_end = edge_start.linear_interpolate(edge_end, end_weight)
			var midpoint = (part_start + part_end) * 0.5
			var builder = _get_chunk_builder(builders, midpoint, surface_material)
			_emit_band_segment(builder, part_start, part_end, width, elevation)
			if add_water_triggers:
				builder.trigger_segments.append([part_start, part_end])
			builders[builder.key] = builder
			emitted_segments += 1
	return emitted_segments


func _emit_band_segment(builder: Dictionary, start: Vector3, finish: Vector3, width: float, elevation: float) -> void:
	var horizontal = Vector3(finish.x - start.x, 0.0, finish.z - start.z)
	if horizontal.length_squared() < 0.000001:
		return
	var side = Vector3(-horizontal.z, 0.0, horizontal.x).normalized() * width * 0.5
	var raised_start = start + Vector3.UP * elevation
	var raised_finish = finish + Vector3.UP * elevation
	_emit_triangle(builder, raised_start + side, raised_finish + side, raised_finish - side)
	_emit_triangle(builder, raised_start + side, raised_finish - side, raised_start - side)


func _emit_road_details(
	builders: Dictionary,
	points: PoolVector3Array,
	edges: Array,
	degrees: Array
) -> Dictionary:
	var sidewalk_triangle_count = 0
	var curb_triangle_count = 0
	var marking_triangle_count = 0
	var crosswalk_count = 0
	var dash_period = MARKING_DASH_LENGTH + MARKING_DASH_GAP

	for edge in edges:
		var a_id = int(edge[0])
		var b_id = int(edge[1])
		var edge_start: Vector3 = points[a_id]
		var edge_end: Vector3 = points[b_id]
		var horizontal = Vector3(edge_end.x - edge_start.x, 0.0, edge_end.z - edge_start.z)
		var length = horizontal.length()
		if length < 0.001:
			continue
		var forward = horizontal / length
		var part_count = max(1, int(ceil(length / MAX_SEGMENT_LENGTH)))
		var start_sidewalk_trim = (
			INTERSECTION_SIDEWALK_SETBACK
			if int(degrees[a_id]) >= 3
			else SIDEWALK_JOINT_TRIM if int(degrees[a_id]) == 2 else 0.0
		)
		var end_sidewalk_trim = (
			INTERSECTION_SIDEWALK_SETBACK
			if int(degrees[b_id]) >= 3
			else SIDEWALK_JOINT_TRIM if int(degrees[b_id]) == 2 else 0.0
		)
		var marking_start = INTERSECTION_MARKING_SETBACK if int(degrees[a_id]) >= 3 else 0.0
		var marking_end = length - (INTERSECTION_MARKING_SETBACK if int(degrees[b_id]) >= 3 else 0.0)

		for part_index in range(part_count):
			var part_start_distance = length * float(part_index) / float(part_count)
			var part_end_distance = length * float(part_index + 1) / float(part_count)
			var part_start = edge_start.linear_interpolate(edge_end, float(part_index) / float(part_count))
			var part_end = edge_start.linear_interpolate(edge_end, float(part_index + 1) / float(part_count))
			var builder = _get_chunk_builder(builders, (part_start + part_end) * 0.5, _road_material)

			var sidewalk_start_distance = max(part_start_distance, start_sidewalk_trim)
			var sidewalk_end_distance = min(part_end_distance, length - end_sidewalk_trim)
			if sidewalk_end_distance - sidewalk_start_distance > 0.05:
				var sidewalk_start = edge_start.linear_interpolate(
					edge_end,
					sidewalk_start_distance / length
				)
				var sidewalk_end = edge_start.linear_interpolate(
					edge_end,
					sidewalk_end_distance / length
				)
				sidewalk_triangle_count += _emit_sidewalk_pair(
					builder,
					sidewalk_start,
					sidewalk_end
				)
				curb_triangle_count += _emit_curb_pair(builder, sidewalk_start, sidewalk_end)

			var first_dash_index = int(floor(part_start_distance / dash_period)) - 1
			var last_dash_index = int(ceil(part_end_distance / dash_period)) + 1
			for dash_index in range(first_dash_index, last_dash_index + 1):
				var dash_start = float(dash_index) * dash_period + MARKING_DASH_GAP * 0.5
				var dash_end = dash_start + MARKING_DASH_LENGTH
				var clipped_start = max(max(dash_start, part_start_distance), marking_start)
				var clipped_end = min(min(dash_end, part_end_distance), marking_end)
				if clipped_end - clipped_start <= 0.05:
					continue
				var line_start = edge_start.linear_interpolate(edge_end, clipped_start / length)
				var line_end = edge_start.linear_interpolate(edge_end, clipped_end / length)
				marking_triangle_count += _emit_center_marking(builder, line_start, line_end)
			builders[builder.key] = builder

		if int(degrees[a_id]) >= 3 and length > CROSSWALK_OFFSET + 3.0:
			var start_builder = _get_edge_part_builder(builders, edge_start, edge_end, 0, part_count)
			var start_center = edge_start.linear_interpolate(edge_end, CROSSWALK_OFFSET / length)
			marking_triangle_count += _emit_crosswalk(start_builder, start_center, forward)
			crosswalk_count += 1
			builders[start_builder.key] = start_builder
		if int(degrees[b_id]) >= 3 and length > CROSSWALK_OFFSET + 3.0:
			var end_builder = _get_edge_part_builder(builders, edge_start, edge_end, part_count - 1, part_count)
			var end_center = edge_start.linear_interpolate(edge_end, (length - CROSSWALK_OFFSET) / length)
			marking_triangle_count += _emit_crosswalk(end_builder, end_center, forward)
			crosswalk_count += 1
			builders[end_builder.key] = end_builder

	return {
		"sidewalk_triangle_count": sidewalk_triangle_count,
		"curb_triangle_count": curb_triangle_count,
		"marking_triangle_count": marking_triangle_count,
		"crosswalk_count": crosswalk_count
	}


func _get_edge_part_builder(
	builders: Dictionary,
	edge_start: Vector3,
	edge_end: Vector3,
	part_index: int,
	part_count: int
) -> Dictionary:
	var start_weight = float(part_index) / float(part_count)
	var end_weight = float(part_index + 1) / float(part_count)
	var part_start = edge_start.linear_interpolate(edge_end, start_weight)
	var part_end = edge_start.linear_interpolate(edge_end, end_weight)
	return _get_chunk_builder(builders, (part_start + part_end) * 0.5, _road_material)


func _emit_sidewalk_pair(builder: Dictionary, start: Vector3, finish: Vector3) -> int:
	var triangle_count = 0
	for side_sign in [-1.0, 1.0]:
		var horizontal = Vector3(finish.x - start.x, 0.0, finish.z - start.z)
		if horizontal.length_squared() < 0.000001:
			continue
		var side = Vector3(-horizontal.z, 0.0, horizontal.x).normalized()
		var inner_offset = side * ROAD_WIDTH * 0.5 * side_sign
		var outer_offset = side * (ROAD_WIDTH * 0.5 + SIDEWALK_WIDTH) * side_sign
		var height = Vector3.UP * (ROAD_ELEVATION + CURB_HEIGHT)
		triangle_count += _emit_detail_quad(
			builder,
			"sidewalk",
			_sidewalk_material,
			start + inner_offset + height,
			finish + inner_offset + height,
			finish + outer_offset + height,
			start + outer_offset + height
		)
	return triangle_count


func _emit_curb_pair(builder: Dictionary, start: Vector3, finish: Vector3) -> int:
	var triangle_count = 0
	for side_sign in [-1.0, 1.0]:
		var horizontal = Vector3(finish.x - start.x, 0.0, finish.z - start.z)
		if horizontal.length_squared() < 0.000001:
			continue
		var side = Vector3(-horizontal.z, 0.0, horizontal.x).normalized()
		var inner_offset = side * ROAD_WIDTH * 0.5 * side_sign
		var bottom = Vector3.UP * (ROAD_ELEVATION + CURB_FACE_OFFSET)
		var top = Vector3.UP * (ROAD_ELEVATION + CURB_HEIGHT)
		triangle_count += _emit_detail_quad(
			builder,
			"curb",
			_curb_material,
			start + inner_offset + bottom,
			finish + inner_offset + bottom,
			finish + inner_offset + top,
			start + inner_offset + top
		)
	return triangle_count


func _emit_center_marking(builder: Dictionary, start: Vector3, finish: Vector3) -> int:
	var horizontal = Vector3(finish.x - start.x, 0.0, finish.z - start.z)
	if horizontal.length_squared() < 0.000001:
		return 0
	var side = Vector3(-horizontal.z, 0.0, horizontal.x).normalized() * MARKING_WIDTH * 0.5
	var lift = Vector3.UP * (ROAD_ELEVATION + MARKING_ELEVATION)
	return _emit_detail_quad(
		builder,
		"marking",
		_road_marking_material,
		start + side + lift,
		finish + side + lift,
		finish - side + lift,
		start - side + lift
	)


func _emit_crosswalk(builder: Dictionary, center: Vector3, forward: Vector3) -> int:
	var triangle_count = 0
	var right = Vector3(-forward.z, 0.0, forward.x)
	var full_depth = (
		float(CROSSWALK_STRIPE_COUNT) * CROSSWALK_STRIPE_WIDTH
		+ float(CROSSWALK_STRIPE_COUNT - 1) * CROSSWALK_STRIPE_GAP
	)
	var first_offset = -full_depth * 0.5 + CROSSWALK_STRIPE_WIDTH * 0.5
	var half_road_width = max(0.5, ROAD_WIDTH * 0.5 - CROSSWALK_SIDE_MARGIN)
	var lift = Vector3.UP * (ROAD_ELEVATION + MARKING_ELEVATION + 0.002)
	for stripe_index in range(CROSSWALK_STRIPE_COUNT):
		var offset = first_offset + float(stripe_index) * (
			CROSSWALK_STRIPE_WIDTH + CROSSWALK_STRIPE_GAP
		)
		var stripe_center = center + forward * offset + lift
		var along = forward * CROSSWALK_STRIPE_WIDTH * 0.5
		var across = right * half_road_width
		triangle_count += _emit_detail_quad(
			builder,
			"marking",
			_road_marking_material,
			stripe_center - along + across,
			stripe_center + along + across,
			stripe_center + along - across,
			stripe_center - along - across
		)
	return triangle_count


func _emit_graph_joints(
	builders: Dictionary,
	points: PoolVector3Array,
	degrees: Array,
	width: float,
	elevation: float,
	surface_material: SpatialMaterial,
	add_water_triggers: bool
) -> void:
	for point_index in range(points.size()):
		if int(degrees[point_index]) <= 0:
			continue
		var center: Vector3 = points[point_index] + Vector3.UP * elevation
		var radius = width * (0.58 if int(degrees[point_index]) >= 3 else 0.5)
		var builder = _get_chunk_builder(builders, points[point_index], surface_material)
		for segment_index in range(JOINT_SEGMENTS):
			var first_angle = TAU * float(segment_index) / float(JOINT_SEGMENTS)
			var second_angle = TAU * float(segment_index + 1) / float(JOINT_SEGMENTS)
			var first = center + Vector3(cos(first_angle) * radius, 0.0, sin(first_angle) * radius)
			var second = center + Vector3(cos(second_angle) * radius, 0.0, sin(second_angle) * radius)
			_emit_triangle(builder, center, second, first)
		if add_water_triggers:
			builder.trigger_joints.append(points[point_index])
		builders[builder.key] = builder


func _get_chunk_builder(builders: Dictionary, point: Vector3, surface_material: SpatialMaterial) -> Dictionary:
	var chunk_x = int(floor(point.x / CHUNK_SIZE))
	var chunk_z = int(floor(point.z / CHUNK_SIZE))
	var key = "%d:%d" % [chunk_x, chunk_z]
	if builders.has(key):
		return builders[key]

	var tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(surface_material)
	var builder = {
		"key": key,
		"chunk_x": chunk_x,
		"chunk_z": chunk_z,
		"origin": Vector3(float(chunk_x) * CHUNK_SIZE, 0.0, float(chunk_z) * CHUNK_SIZE),
		"tool": tool,
		"triangle_count": 0,
		"detail_triangle_count": 0,
		"detail_tools": {},
		"trigger_segments": [],
		"trigger_joints": []
	}
	builders[key] = builder
	return builder


func _emit_triangle(builder: Dictionary, a: Vector3, b: Vector3, c: Vector3) -> void:
	if _emit_triangle_to_tool(builder.tool, builder.origin, a, b, c):
		builder.triangle_count = int(builder.triangle_count) + 1


func _emit_detail_quad(
	builder: Dictionary,
	detail_key: String,
	material: SpatialMaterial,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	d: Vector3
) -> int:
	var tool = _get_detail_tool(builder, detail_key, material)
	var triangle_count = 0
	if _emit_triangle_to_tool(tool, builder.origin, a, b, c):
		triangle_count += 1
	if _emit_triangle_to_tool(tool, builder.origin, a, c, d):
		triangle_count += 1
	builder.detail_triangle_count = int(builder.detail_triangle_count) + triangle_count
	return triangle_count


func _get_detail_tool(
	builder: Dictionary,
	detail_key: String,
	material: SpatialMaterial
) -> SurfaceTool:
	var detail_tools: Dictionary = builder.detail_tools
	if detail_tools.has(detail_key):
		return detail_tools[detail_key]
	var tool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_material(material)
	detail_tools[detail_key] = tool
	builder.detail_tools = detail_tools
	return tool


func _emit_triangle_to_tool(
	surface_tool: SurfaceTool,
	chunk_origin: Vector3,
	a: Vector3,
	b: Vector3,
	c: Vector3
) -> bool:
	var normal = (b - a).cross(c - a)
	if normal.length_squared() < 0.0000001:
		return false
	if normal.y < 0.0:
		var temporary = b
		b = c
		c = temporary
		normal = (b - a).cross(c - a)
	normal = normal.normalized()

	for vertex in [a, b, c]:
		surface_tool.add_normal(normal)
		surface_tool.add_uv(Vector2(vertex.x, vertex.z) * ROAD_UV_SCALE)
		surface_tool.add_vertex(vertex - chunk_origin)
	return true


func _commit_road_chunks(builders: Dictionary) -> Dictionary:
	var keys = builders.keys()
	keys.sort()
	var chunk_count = 0
	var triangle_count = 0
	var surface_triangle_count = 0
	var detail_triangle_count = 0

	for key in keys:
		var builder: Dictionary = builders[key]
		var tool: SurfaceTool = builder.tool
		tool.index()
		var mesh = tool.commit()
		if not (mesh is ArrayMesh) or mesh.get_surface_count() == 0:
			return {"ok": false, "error": "Road chunk %s produced no triangle mesh" % key}

		mesh = _commit_detail_surface(mesh, builder, "sidewalk")
		mesh = _commit_detail_surface(mesh, builder, "curb")
		var collision_shape_resource = mesh.create_trimesh_shape()
		if collision_shape_resource == null:
			return {"ok": false, "error": "Road chunk %s produced no trimesh collision" % key}
		mesh = _commit_detail_surface(mesh, builder, "marking")

		var chunk = Spatial.new()
		chunk.name = "RoadChunk_%d_%d" % [int(builder.chunk_x), int(builder.chunk_z)]
		chunk.translation = builder.origin
		chunk.add_to_group("map_road")
		chunk.set_meta("chunk_x", int(builder.chunk_x))
		chunk.set_meta("chunk_z", int(builder.chunk_z))
		chunk.set_meta("map_feature", "road")

		var mesh_instance = MeshInstance.new()
		mesh_instance.name = "RoadMesh"
		mesh_instance.mesh = mesh
		mesh_instance.add_to_group("map_road")
		chunk.add_child(mesh_instance)

		var road_body = StaticBody.new()
		road_body.name = "RoadSurface"
		road_body.collision_layer = ROAD_COLLISION_LAYER
		road_body.collision_mask = ROAD_COLLISION_MASK
		road_body.physics_material_override = _road_physics_material
		road_body.set_meta("surface_kind", "street")
		road_body.set_meta("surface_grip", ROAD_SURFACE_GRIP)
		road_body.set_meta("rolling_resistance", ROAD_ROLLING_RESISTANCE)
		road_body.add_to_group("map_road")
		chunk.add_child(road_body)

		var collision = CollisionShape.new()
		collision.name = "CollisionShape"
		collision.shape = collision_shape_resource
		road_body.add_child(collision)

		_road_chunks_root.add_child(chunk)
		chunk_count += 1
		surface_triangle_count += int(builder.triangle_count)
		detail_triangle_count += int(builder.detail_triangle_count)
		triangle_count += int(builder.triangle_count) + int(builder.detail_triangle_count)

	return {
		"ok": true,
		"error": "",
		"chunk_count": chunk_count,
		"triangle_count": triangle_count,
		"surface_triangle_count": surface_triangle_count,
		"detail_triangle_count": detail_triangle_count
	}


func _commit_detail_surface(
	mesh: ArrayMesh,
	builder: Dictionary,
	detail_key: String
) -> ArrayMesh:
	var detail_tools: Dictionary = builder.detail_tools
	if not detail_tools.has(detail_key):
		return mesh
	var tool: SurfaceTool = detail_tools[detail_key]
	tool.index()
	return tool.commit(mesh)


func _commit_canal_chunks(builders: Dictionary) -> Dictionary:
	var keys = builders.keys()
	keys.sort()
	var chunk_count = 0
	var triangle_count = 0
	var trigger_count = 0

	for key in keys:
		var builder: Dictionary = builders[key]
		var tool: SurfaceTool = builder.tool
		tool.index()
		var mesh = tool.commit()
		if not (mesh is ArrayMesh) or mesh.get_surface_count() == 0:
			return {"ok": false, "error": "Canal chunk %s produced no triangle mesh" % key}

		var chunk = Spatial.new()
		chunk.name = "CanalChunk_%d_%d" % [int(builder.chunk_x), int(builder.chunk_z)]
		chunk.translation = builder.origin
		chunk.add_to_group("map_canal")
		chunk.set_meta("chunk_x", int(builder.chunk_x))
		chunk.set_meta("chunk_z", int(builder.chunk_z))
		chunk.set_meta("map_feature", "canal")

		var water_mesh = MeshInstance.new()
		water_mesh.name = "WaterMesh"
		water_mesh.mesh = mesh
		water_mesh.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
		water_mesh.add_to_group("map_canal")
		chunk.add_child(water_mesh)

		var water_area = Area.new()
		water_area.name = "WaterArea"
		water_area.collision_layer = WATER_COLLISION_LAYER
		water_area.collision_mask = WATER_COLLISION_MASK
		water_area.monitoring = true
		water_area.monitorable = true
		water_area.set_meta("surface_kind", "water")
		water_area.set_meta("generated_from", "Kanal")
		water_area.add_to_group("map_canal")
		chunk.add_child(water_area)

		var shape_index = 0
		for segment in builder.trigger_segments:
			var start: Vector3 = segment[0]
			var finish: Vector3 = segment[1]
			var horizontal = Vector3(finish.x - start.x, 0.0, finish.z - start.z)
			var length = horizontal.length()
			if length < 0.001:
				continue
			var forward = horizontal / length
			var right = Vector3(forward.z, 0.0, -forward.x)
			var trigger_top = (start.y + finish.y) * 0.5 + CANAL_ELEVATION - WATER_TRIGGER_TOP_OFFSET
			var center = (start + finish) * 0.5
			center.y = trigger_top - WATER_TRIGGER_DEPTH * 0.5

			var box = BoxShape.new()
			box.extents = Vector3(CANAL_WIDTH * 0.5, WATER_TRIGGER_DEPTH * 0.5, length * 0.5)
			var collision = CollisionShape.new()
			collision.name = "SegmentShape_%04d" % shape_index
			collision.shape = box
			collision.transform = Transform(Basis(right, Vector3.UP, forward), center - builder.origin)
			water_area.add_child(collision)
			shape_index += 1
			trigger_count += 1

		for joint_position in builder.trigger_joints:
			var joint_box = BoxShape.new()
			joint_box.extents = Vector3(
				CANAL_WIDTH * 0.5,
				WATER_TRIGGER_DEPTH * 0.5,
				CANAL_WIDTH * 0.5
			)
			var joint_collision = CollisionShape.new()
			joint_collision.name = "JointShape_%04d" % shape_index
			joint_collision.shape = joint_box
			var joint_center: Vector3 = joint_position - builder.origin
			joint_center.y += CANAL_ELEVATION - WATER_TRIGGER_TOP_OFFSET - WATER_TRIGGER_DEPTH * 0.5
			joint_collision.translation = joint_center
			water_area.add_child(joint_collision)
			shape_index += 1
			trigger_count += 1

		_canal_chunks_root.add_child(chunk)
		water_area.add_to_group("water")
		chunk_count += 1
		triangle_count += int(builder.triangle_count)

	return {
		"ok": true,
		"error": "",
		"chunk_count": chunk_count,
		"triangle_count": triangle_count,
		"trigger_count": trigger_count
	}


func _nearest_street_edge(local_position: Vector3) -> Dictionary:
	var best = {
		"edge_index": -1,
		"a_id": -1,
		"b_id": -1,
		"point": local_position,
		"distance_squared": INF
	}
	for edge_index in range(_street_edges.size()):
		var edge = _street_edges[edge_index]
		var a_id = int(edge[0])
		var b_id = int(edge[1])
		var closest = _closest_point_on_segment(local_position, _street_points[a_id], _street_points[b_id])
		var distance_squared = local_position.distance_squared_to(closest)
		if distance_squared < float(best.distance_squared):
			best = {
				"edge_index": edge_index,
				"a_id": a_id,
				"b_id": b_id,
				"point": closest,
				"distance_squared": distance_squared
			}
	return best


func _closest_point_on_segment(point: Vector3, start: Vector3, finish: Vector3) -> Vector3:
	var segment = finish - start
	var length_squared = segment.length_squared()
	if length_squared < 0.0000001:
		return start
	var weight = clamp((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return start + segment * weight


func _pool_path_length(path: PoolVector3Array) -> float:
	var result = 0.0
	for point_index in range(1, path.size()):
		result += path[point_index - 1].distance_to(path[point_index])
	return result


func _append_unique(points: Array, point: Vector3) -> void:
	if points.empty() or points[-1].distance_squared_to(point) > POINT_EPSILON_SQUARED:
		points.append(point)


func _walk_from_projection(
	projection: Vector3,
	first_id: int,
	blocked_id: int,
	requested_distance: float,
	variant: int
) -> Dictionary:
	var first_point: Vector3 = _street_points[first_id]
	var initial_distance = projection.distance_to(first_point)
	if initial_distance >= requested_distance and initial_distance > 0.0001:
		return {
			"point": projection.linear_interpolate(first_point, requested_distance / initial_distance),
			"travelled": requested_distance
		}

	var travelled = initial_distance
	var remaining = requested_distance - initial_distance
	var current_id = first_id
	var used_edges = {_edge_key(first_id, blocked_id): true}
	var guard = 0

	while remaining > 0.001 and guard < _street_points.size() * 2:
		var candidates = []
		for neighbor_value in _street_adjacency[current_id]:
			var neighbor_id = int(neighbor_value)
			if not used_edges.has(_edge_key(current_id, neighbor_id)):
				candidates.append(neighbor_id)
		if candidates.empty():
			break
		candidates.sort()
		var selected_index = (int(abs(variant)) + guard) % candidates.size()
		var next_id = int(candidates[selected_index])
		used_edges[_edge_key(current_id, next_id)] = true

		var current_point: Vector3 = _street_points[current_id]
		var next_point: Vector3 = _street_points[next_id]
		var edge_length = current_point.distance_to(next_point)
		if edge_length < 0.0001:
			current_id = next_id
			guard += 1
			continue
		if remaining <= edge_length:
			return {
				"point": current_point.linear_interpolate(next_point, remaining / edge_length),
				"travelled": requested_distance
			}
		remaining -= edge_length
		travelled += edge_length
		current_id = next_id
		guard += 1

	return {"point": _street_points[current_id], "travelled": travelled}


func _edge_key(a_id: int, b_id: int) -> String:
	return "%d:%d" % [min(a_id, b_id), max(a_id, b_id)]


func _count_intersections(degrees: Array) -> int:
	var count = 0
	for degree in degrees:
		if int(degree) >= 3:
			count += 1
	return count


func _fail(message: String) -> bool:
	_last_error = message
	_diagnostics = {"built": false, "error": message}
	push_error(message)
	return false
