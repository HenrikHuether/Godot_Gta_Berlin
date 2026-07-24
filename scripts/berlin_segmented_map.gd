extends Spatial
class_name BerlinSegmentedMap

# The source GLB stores its geometry in metre-based, absolute coordinates.
# Street's source origin is used as the playable world origin.
const SOURCE_ANCHOR := Vector3(5809.403809, 0.0, 4220.549805)
const NETWORK_FILE := "res://Assets/Maps/berlin_network.json"
const WALK_SURFACE_ELEVATION := 0.0
const GROUND_COLLISION_DEPTH := 4.0
const FACADE_SHADER = preload("res://shaders/berlin_building_facade.shader")
const FACADE_TEXTURES := [
	preload("res://Assets/Textures/berlin_facade.png"),
	preload("res://Assets/Textures/berlin_facade_rose.png"),
	preload("res://Assets/Textures/berlin_facade_brick.png"),
	preload("res://Assets/Textures/berlin_facade_postwar.png")
]

const LOCAL_MAP_BOUNDS := AABB(
	Vector3(-15953.458496, -0.08, -10712.976074),
	Vector3(22057.772461, 115.08, 14737.533691)
)

const SPAWN_OFFSETS := {
	"player": Vector3(3.0, 0.0, 8.0),
	"car": Vector3(2.8, 0.0, -4.0),
	"helicopter": Vector3(45.0, 0.0, 55.0),
	"npc_1": Vector3(-5.0, 0.0, -8.0),
	"npc_2": Vector3(8.0, 0.0, 5.0),
	"npc_3": Vector3(-8.0, 0.0, 12.0),
	"respawn": Vector3(3.0, 0.0, 8.0)
}

const SPAWN_HEIGHTS := {
	"player": 1.0,
	"car": 0.72,
	"helicopter": 1.50,
	"npc_1": 1.0,
	"npc_2": 1.0,
	"npc_3": 1.0,
	"respawn": 1.0
}

var _source_root: Spatial
var _generator: Node
var _building_chunks := []
var _ground_chunks := []
var _building_materials := []
var _building_signatures := {}
var _deduplicated_buildings := 0
var _aggregate_components_created := 0
var _is_ready := false


func _ready():
	_source_root = get_node_or_null("Source")
	_generator = get_node_or_null("Generator")
	_building_materials = _make_building_materials()
	_expand_aggregate_building()
	_classify_imported_chunks()
	_configure_ground_surface()
	if is_instance_valid(_generator) and _generator.has_method("build_from_file"):
		_generator.build_from_file(NETWORK_FILE)
	_is_ready = true


func _make_building_materials() -> Array:
	var materials = []
	var tints = [
		Color("f4e3c7"),
		Color("e4c6bc"),
		Color("f1d4bd"),
		Color("e8eadf")
	]
	var roof_colors = [
		Color("3c3430"),
		Color("443835"),
		Color("342f2d"),
		Color("4a4b47")
	]
	for index in range(FACADE_TEXTURES.size()):
		var texture = _make_repeat_facade_texture(
			FACADE_TEXTURES[index],
			"Berlin Facade Runtime %02d" % index
		)
		var material = ShaderMaterial.new()
		material.resource_name = "Berlin_Facade_%02d" % index
		material.shader = FACADE_SHADER
		material.set_shader_param("facade_texture", texture)
		material.set_shader_param("facade_tint", tints[index])
		material.set_shader_param("roof_color", roof_colors[index])
		material.set_shader_param("horizontal_scale", 0.052 + float(index) * 0.003)
		material.set_shader_param("vertical_scale", 0.031)
		material.set_shader_param("horizontal_offset", float(index) * 0.173)
		materials.append(material)
	return materials


func _make_repeat_facade_texture(source_texture: Texture, texture_name: String) -> Texture:
	var image = source_texture.get_data()
	if image == null or image.get_width() <= 0:
		return source_texture
	if image.is_compressed():
		image.decompress()
	# GLES2 does not guarantee repeating non-power-of-two textures. The generated
	# source stays untouched; only its runtime GPU copy is resized.
	if image.get_width() != 1024 or image.get_height() != 1024:
		image.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	if not image.has_mipmaps():
		image.generate_mipmaps()
	var texture = ImageTexture.new()
	texture.resource_name = texture_name
	texture.create_from_image(
		image,
		Texture.FLAG_MIPMAPS
		| Texture.FLAG_REPEAT
		| Texture.FLAG_FILTER
		| Texture.FLAG_ANISOTROPIC_FILTER
	)
	return texture


# The source export contains one legacy aggregate with 76 disconnected houses.
# Split it once at runtime so the complete imported city follows the same
# one-node-per-destructible-building contract.
func _expand_aggregate_building():
	if not is_instance_valid(_source_root):
		return
	var aggregate = _find_aggregate_building(_source_root)
	if not is_instance_valid(aggregate) or aggregate.mesh == null:
		return
	var component_meshes = _split_mesh_by_welded_position(aggregate.mesh)
	if component_meshes.size() <= 1:
		return
	var parent = aggregate.get_parent()
	var original_transform = aggregate.transform
	for index in range(component_meshes.size()):
		var component = MeshInstance.new()
		component.name = "Areasbuilding_aggregate_%03d" % index
		component.transform = original_transform
		component.mesh = component_meshes[index]
		parent.add_child(component)
	_aggregate_components_created = component_meshes.size()
	parent.remove_child(aggregate)
	aggregate.queue_free()


func _find_aggregate_building(node: Node) -> MeshInstance:
	if node is MeshInstance:
		var normalized_name = _normalized_import_name(node.name)
		if normalized_name == "areasbuilding" and node.get_aabb().size.x > 500.0:
			return node as MeshInstance
	for child in node.get_children():
		var result = _find_aggregate_building(child)
		if is_instance_valid(result):
			return result
	return null


func _split_mesh_by_welded_position(mesh: Mesh) -> Array:
	if mesh.get_surface_count() != 1:
		return [mesh]
	if mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
		return [mesh]
	var arrays = mesh.surface_get_arrays(0)
	if arrays.size() != Mesh.ARRAY_MAX:
		return [mesh]
	var vertices = arrays[Mesh.ARRAY_VERTEX]
	var normals = arrays[Mesh.ARRAY_NORMAL]
	if vertices == null or vertices.size() < 3:
		return [mesh]
	var indices = arrays[Mesh.ARRAY_INDEX]
	if indices == null or indices.size() < 3:
		indices = PoolIntArray()
		indices.resize(vertices.size())
		for index in range(vertices.size()):
			indices[index] = index

	var parents = []
	var ranks = []
	parents.resize(vertices.size())
	ranks.resize(vertices.size())
	for index in range(vertices.size()):
		parents[index] = index
		ranks[index] = 0

	var vertices_by_position := {}
	for index in range(vertices.size()):
		var key = _quantized_position_key(vertices[index])
		if vertices_by_position.has(key):
			_union_components(parents, ranks, index, int(vertices_by_position[key]))
		else:
			vertices_by_position[key] = index

	var triangle_count = int(indices.size() / 3)
	for triangle_index in range(triangle_count):
		var offset = triangle_index * 3
		var index_a = int(indices[offset])
		var index_b = int(indices[offset + 1])
		var index_c = int(indices[offset + 2])
		_union_components(parents, ranks, index_a, index_b)
		_union_components(parents, ranks, index_a, index_c)

	var component_indices := {}
	for triangle_index in range(triangle_count):
		var offset = triangle_index * 3
		var root = _find_component(parents, int(indices[offset]))
		if not component_indices.has(root):
			component_indices[root] = PoolIntArray()
		var triangle_indices: PoolIntArray = component_indices[root]
		triangle_indices.append(int(indices[offset]))
		triangle_indices.append(int(indices[offset + 1]))
		triangle_indices.append(int(indices[offset + 2]))
		component_indices[root] = triangle_indices

	var component_meshes = []
	var source_material = mesh.surface_get_material(0)
	for root in component_indices:
		var surface_tool = SurfaceTool.new()
		surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		if source_material != null:
			surface_tool.set_material(source_material)
		for vertex_index in component_indices[root]:
			if normals != null and normals.size() == vertices.size():
				surface_tool.add_normal(normals[int(vertex_index)])
			surface_tool.add_vertex(vertices[int(vertex_index)])
		var component_mesh = surface_tool.commit()
		if component_mesh != null:
			component_meshes.append(component_mesh)
	return component_meshes


func _quantized_position_key(position: Vector3) -> String:
	return "%d:%d:%d" % [
		int(round(position.x * 1000.0)),
		int(round(position.y * 1000.0)),
		int(round(position.z * 1000.0))
	]


func _classify_imported_chunks():
	_building_chunks.clear()
	_ground_chunks.clear()
	_building_signatures.clear()
	_deduplicated_buildings = 0
	if not is_instance_valid(_source_root):
		push_error("BerlinSegmentedMap requires its Source GLB child")
		return
	_classify_node_recursive(_source_root)


func _classify_node_recursive(node: Node):
	if node is MeshInstance:
		var normalized_name = _normalized_import_name(node.name)
		if normalized_name.begins_with("export_google_sat_wm"):
			_configure_ground_chunk(node)
		elif normalized_name.begins_with("areasbuilding"):
			_configure_building_chunk(node)
	for child in node.get_children():
		_classify_node_recursive(child)


func _normalized_import_name(node_name: String) -> String:
	return node_name.to_lower().replace(":", "").replace(".", "").replace(" ", "")


func _configure_ground_chunk(chunk: MeshInstance):
	_ground_chunks.append(chunk)
	chunk.add_to_group("map_ground")
	chunk.set_meta("map_feature", "ground")
	chunk.set_meta("source_chunk", true)
	chunk.set_meta("surface_grip", 0.52)
	chunk.set_meta("rolling_resistance", 2.4)


func _configure_building_chunk(chunk: MeshInstance):
	var signature = _building_signature(chunk)
	if _building_signatures.has(signature):
		var canonical_signature = _canonical_mesh_signature(chunk.mesh)
		var signature_bucket: Array = _building_signatures[signature]
		for existing in signature_bucket:
			if str(existing.canonical).empty():
				existing.canonical = _canonical_mesh_signature(existing.chunk.mesh)
			if str(existing.canonical) != canonical_signature:
				continue
			_deduplicated_buildings += 1
			chunk.visible = false
			var duplicate_parent = chunk.get_parent()
			if is_instance_valid(duplicate_parent):
				duplicate_parent.remove_child(chunk)
			chunk.queue_free()
			return
		signature_bucket.append({"chunk": chunk, "canonical": canonical_signature})
		_building_signatures[signature] = signature_bucket
	else:
		_building_signatures[signature] = [{"chunk": chunk, "canonical": ""}]

	_building_chunks.append(chunk)
	chunk.add_to_group("map_building")
	chunk.add_to_group("destructible")
	chunk.set_meta("map_feature", "building")
	chunk.set_meta("source_chunk", true)
	chunk.set_meta("destructible_building", true)
	chunk.set_meta("destruction_local_aabb", chunk.get_aabb())
	var material_index = _stable_name_hash(chunk.name) % int(max(1, _building_materials.size()))
	chunk.set_meta("facade_variant", material_index)
	if not _building_materials.empty():
		chunk.material_override = _building_materials[material_index]
	_create_or_update_building_collision(chunk)


func _building_signature(chunk: MeshInstance) -> String:
	var bounds = chunk.get_aabb()
	var vertex_count = 0
	var index_count = 0
	if chunk.mesh != null:
		for surface_index in range(chunk.mesh.get_surface_count()):
			var arrays = chunk.mesh.surface_get_arrays(surface_index)
			if arrays.size() != Mesh.ARRAY_MAX:
				continue
			var vertices = arrays[Mesh.ARRAY_VERTEX]
			var indices = arrays[Mesh.ARRAY_INDEX]
			if vertices != null:
				vertex_count += vertices.size()
			if indices != null:
				index_count += indices.size()
	return "%s|%s|%d|%d" % [
		_quantized_position_key(bounds.position),
		_quantized_position_key(bounds.size),
		vertex_count,
		index_count
	]


func _canonical_mesh_signature(mesh: Mesh) -> String:
	var triangle_keys = []
	for surface_index in range(mesh.get_surface_count()):
		if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arrays = mesh.surface_get_arrays(surface_index)
		if arrays.size() != Mesh.ARRAY_MAX:
			continue
		var vertices = arrays[Mesh.ARRAY_VERTEX]
		var normals = arrays[Mesh.ARRAY_NORMAL]
		var uvs = arrays[Mesh.ARRAY_TEX_UV]
		var indices = arrays[Mesh.ARRAY_INDEX]
		if vertices == null or vertices.size() < 3:
			continue
		if indices == null or indices.size() < 3:
			indices = PoolIntArray()
			indices.resize(vertices.size())
			for vertex_index in range(vertices.size()):
				indices[vertex_index] = vertex_index
		for triangle_index in range(int(indices.size() / 3)):
			var offset = triangle_index * 3
			var corners = []
			for corner_offset in range(3):
				var vertex_index = int(indices[offset + corner_offset])
				var normal = (
					normals[vertex_index]
					if normals != null and normals.size() == vertices.size()
					else Vector3.ZERO
				)
				var uv = (
					uvs[vertex_index]
					if uvs != null and uvs.size() == vertices.size()
					else Vector2.ZERO
				)
				corners.append(_canonical_vertex_key(vertices[vertex_index], normal, uv))
			var rotations = [
				"%s>%s>%s" % [corners[0], corners[1], corners[2]],
				"%s>%s>%s" % [corners[1], corners[2], corners[0]],
				"%s>%s>%s" % [corners[2], corners[0], corners[1]]
			]
			rotations.sort()
			triangle_keys.append(rotations[0])
	triangle_keys.sort()

	var primary_hash = 5381
	var secondary_hash = 7919
	for triangle_key in triangle_keys:
		for character_index in range(triangle_key.length()):
			var code = triangle_key.ord_at(character_index)
			primary_hash = _signature_hash_mix(primary_hash, code, 65599)
			secondary_hash = _signature_hash_mix(secondary_hash, code, 131071)
	return "%d:%d:%d" % [triangle_keys.size(), primary_hash, secondary_hash]


func _canonical_vertex_key(position: Vector3, normal: Vector3, uv: Vector2) -> String:
	return "%d,%d,%d;%d,%d,%d;%d,%d" % [
		int(round(position.x * 1000.0)),
		int(round(position.y * 1000.0)),
		int(round(position.z * 1000.0)),
		int(round(normal.x * 10000.0)),
		int(round(normal.y * 10000.0)),
		int(round(normal.z * 10000.0)),
		int(round(uv.x * 10000.0)),
		int(round(uv.y * 10000.0))
	]


func _signature_hash_mix(current: int, value: int, multiplier: int) -> int:
	var mixed = int((current * multiplier + value) % 2147483647)
	return mixed if mixed >= 0 else mixed + 2147483647


func _stable_name_hash(value: String) -> int:
	var result = 5381
	for index in range(value.length()):
		result = int((result * 33 + value.ord_at(index)) % 2147483647)
	return result


func _configure_ground_surface():
	var ground_surface = get_node_or_null("GroundSurface")
	if not is_instance_valid(ground_surface):
		return
	ground_surface.add_to_group("map_ground")
	ground_surface.set_meta("map_feature", "ground")
	ground_surface.set_meta("surface_grip", 0.52)
	ground_surface.set_meta("rolling_resistance", 2.4)
	ground_surface.collision_layer = 1
	ground_surface.collision_mask = 1
	var collision_shape = ground_surface.get_node_or_null("CollisionShape")
	if not is_instance_valid(collision_shape):
		return
	var minimum = LOCAL_MAP_BOUNDS.position
	var maximum = LOCAL_MAP_BOUNDS.position + LOCAL_MAP_BOUNDS.size
	var horizontal_size = Vector2(maximum.x - minimum.x, maximum.z - minimum.z)
	var ground_shape = BoxShape.new()
	ground_shape.extents = Vector3(
		horizontal_size.x * 0.5,
		GROUND_COLLISION_DEPTH * 0.5,
		horizontal_size.y * 0.5
	)
	collision_shape.translation = Vector3(
		(minimum.x + maximum.x) * 0.5,
		WALK_SURFACE_ELEVATION - GROUND_COLLISION_DEPTH * 0.5,
		(minimum.z + maximum.z) * 0.5
	)
	collision_shape.shape = ground_shape


func _create_or_update_building_collision(chunk: MeshInstance):
	var collision_body = chunk.get_node_or_null("ChunkPhysics")
	if not is_instance_valid(collision_body):
		collision_body = StaticBody.new()
		collision_body.name = "ChunkPhysics"
		chunk.add_child(collision_body)
	collision_body.add_to_group("map_building")
	collision_body.set_meta("map_feature", "building")
	collision_body.set_meta("source_chunk", true)
	collision_body.collision_layer = 1
	collision_body.collision_mask = 1

	var collision_shape = collision_body.get_node_or_null("CollisionShape")
	if not is_instance_valid(collision_shape):
		collision_shape = CollisionShape.new()
		collision_shape.name = "CollisionShape"
		collision_body.add_child(collision_shape)

	var mesh = chunk.mesh
	if mesh != null and mesh.get_surface_count() > 0:
		collision_shape.shape = mesh.create_trimesh_shape()
		collision_shape.disabled = collision_shape.shape == null
	else:
		collision_shape.shape = null
		collision_shape.disabled = true


func get_map_bounds() -> AABB:
	return _transform_aabb(LOCAL_MAP_BOUNDS, global_transform)


func get_spawn_transform(spawn_id: String) -> Transform:
	var id = spawn_id.to_lower()
	if not SPAWN_OFFSETS.has(id):
		id = "player"
	var desired_world = global_transform.xform(SPAWN_OFFSETS[id])
	if id != "helicopter":
		desired_world = get_nearest_road_point(desired_world)
	var surface_point = project_to_surface(desired_world)
	var up = global_transform.basis.y.normalized()
	var basis = global_transform.basis.orthonormalized()
	return Transform(basis, surface_point + up * float(SPAWN_HEIGHTS[id]))


func get_nearest_road_point(world_position: Vector3) -> Vector3:
	if is_instance_valid(_generator) and _generator.has_method("get_nearest_road_point"):
		var result = _generator.get_nearest_road_point(world_position)
		if typeof(result) == TYPE_VECTOR3:
			return result
	var local_position = global_transform.affine_inverse().xform(world_position)
	local_position.x = clamp(
		local_position.x,
		LOCAL_MAP_BOUNDS.position.x,
		LOCAL_MAP_BOUNDS.position.x + LOCAL_MAP_BOUNDS.size.x
	)
	local_position.z = clamp(
		local_position.z,
		LOCAL_MAP_BOUNDS.position.z,
		LOCAL_MAP_BOUNDS.position.z + LOCAL_MAP_BOUNDS.size.z
	)
	local_position.y = 0.0
	return global_transform.xform(local_position)


func get_response_route(target_position: Vector3, variant := 0) -> Array:
	if is_instance_valid(_generator) and _generator.has_method("get_response_route"):
		var route = _generator.get_response_route(target_position, int(variant))
		if typeof(route) == TYPE_ARRAY and route.size() >= 2:
			return route

	var target_on_road = get_nearest_road_point(target_position)
	var local_target = global_transform.affine_inverse().xform(target_on_road)
	var best_spawn = target_on_road
	var best_distance = -1.0
	var approach_distance = 180.0 + 25.0 * float(int(abs(int(variant))) % 3)
	for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var candidate_local = local_target + direction * approach_distance
		var candidate_world = get_nearest_road_point(global_transform.xform(candidate_local))
		var candidate_distance = candidate_world.distance_to(target_on_road)
		if candidate_distance > best_distance:
			best_distance = candidate_distance
			best_spawn = candidate_world
	return [best_spawn, target_on_road]


func project_to_surface(world_position: Vector3, height_offset := 0.0, excluded := []) -> Vector3:
	if is_inside_tree() and get_world() != null:
		var bounds = get_map_bounds()
		var ray_top = max(
			world_position.y + 250.0,
			bounds.position.y + bounds.size.y + 50.0
		)
		var ray_bottom = min(world_position.y - 250.0, bounds.position.y - 50.0)
		var exclusions = excluded if excluded is Array else [excluded]
		var hit = get_world().direct_space_state.intersect_ray(
			Vector3(world_position.x, ray_top, world_position.z),
			Vector3(world_position.x, ray_bottom, world_position.z),
			exclusions
		)
		if hit:
			return hit.position + global_transform.basis.y.normalized() * height_offset

	var local_position = global_transform.affine_inverse().xform(world_position)
	local_position.y = 0.0
	return global_transform.xform(local_position) + global_transform.basis.y.normalized() * height_offset


func source_to_world(source_position: Vector3) -> Vector3:
	if is_instance_valid(_source_root):
		return _source_root.global_transform.xform(source_position)
	return global_transform.xform(source_position - SOURCE_ANCHOR)


func world_to_source(world_position: Vector3) -> Vector3:
	if is_instance_valid(_source_root):
		return _source_root.global_transform.affine_inverse().xform(world_position)
	return global_transform.affine_inverse().xform(world_position) + SOURCE_ANCHOR


func get_building_count() -> int:
	var count = 0
	for chunk in _building_chunks:
		if is_instance_valid(chunk) and not chunk.is_queued_for_deletion():
			count += 1
	return count


func get_facade_variant_count() -> int:
	return _building_materials.size()


func get_deduplicated_building_count() -> int:
	return _deduplicated_buildings


func get_aggregate_component_count() -> int:
	return _aggregate_components_created


# Removes complete individual building nodes which touch the requested world
# region. This is also used for mission set pieces that replace source houses.
func clear_region(world_aabb: AABB, feature_kind := "building") -> int:
	if feature_kind.to_lower() != "building":
		if is_instance_valid(_generator) and _generator.has_method("clear_region"):
			return int(_generator.clear_region(world_aabb, feature_kind))
		return 0

	var region = _normalized_aabb(world_aabb)
	var removed_building_count = 0
	for chunk in _building_chunks.duplicate():
		if not is_instance_valid(chunk) or chunk.mesh == null:
			continue
		var chunk_bounds = _transform_aabb(chunk.get_aabb(), chunk.global_transform)
		if not chunk_bounds.intersects(region):
			continue
		chunk.visible = false
		var collision_body = chunk.get_node_or_null("ChunkPhysics")
		if is_instance_valid(collision_body):
			collision_body.collision_layer = 0
			collision_body.collision_mask = 0
		_building_chunks.erase(chunk)
		chunk.queue_free()
		removed_building_count += 1
	return removed_building_count


func _find_component(parents: Array, index: int) -> int:
	var root = index
	while int(parents[root]) != root:
		root = int(parents[root])
	while int(parents[index]) != index:
		var next = int(parents[index])
		parents[index] = root
		index = next
	return root


func _union_components(parents: Array, ranks: Array, first: int, second: int):
	var first_root = _find_component(parents, first)
	var second_root = _find_component(parents, second)
	if first_root == second_root:
		return
	if int(ranks[first_root]) < int(ranks[second_root]):
		parents[first_root] = second_root
	elif int(ranks[first_root]) > int(ranks[second_root]):
		parents[second_root] = first_root
	else:
		parents[second_root] = first_root
		ranks[first_root] = int(ranks[first_root]) + 1


func _normalized_aabb(box: AABB) -> AABB:
	var opposite = box.position + box.size
	var minimum = Vector3(
		min(box.position.x, opposite.x),
		min(box.position.y, opposite.y),
		min(box.position.z, opposite.z)
	)
	var maximum = Vector3(
		max(box.position.x, opposite.x),
		max(box.position.y, opposite.y),
		max(box.position.z, opposite.z)
	)
	return AABB(minimum, maximum - minimum)


func _transform_aabb(box: AABB, transform: Transform) -> AABB:
	var first = transform.xform(box.position)
	var minimum = first
	var maximum = first
	for x_side in range(2):
		for y_side in range(2):
			for z_side in range(2):
				var corner = box.position + Vector3(
					box.size.x * float(x_side),
					box.size.y * float(y_side),
					box.size.z * float(z_side)
				)
				var transformed_corner = transform.xform(corner)
				minimum.x = min(minimum.x, transformed_corner.x)
				minimum.y = min(minimum.y, transformed_corner.y)
				minimum.z = min(minimum.z, transformed_corner.z)
				maximum.x = max(maximum.x, transformed_corner.x)
				maximum.y = max(maximum.y, transformed_corner.y)
				maximum.z = max(maximum.z, transformed_corner.z)
	return AABB(minimum, maximum - minimum)
