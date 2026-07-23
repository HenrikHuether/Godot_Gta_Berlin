extends SceneTree

const MAP_SCENE = preload("res://scenes/BerlinSegmentedMap.tscn")

var failures := []


func _init():
	call_deferred("_run")


func _run():
	var berlin_map = MAP_SCENE.instance()
	get_root().add_child(berlin_map)
	yield(self, "idle_frame")

	var building_count = berlin_map.get_building_count()
	var duplicate_count = berlin_map.get_deduplicated_building_count()
	var aggregate_count = berlin_map.get_aggregate_component_count()
	_expect(building_count == 5340, "the individual export should retain all 5,340 unique building meshes")
	_expect(berlin_map.get_facade_variant_count() == 4, "Berlin buildings should share four facade variants")
	_expect(duplicate_count == 154, "all 154 overlapping duplicate exports should be deduplicated")
	_expect(aggregate_count == 76, "the remaining aggregate should split into its 76 individual components")

	var buildings = get_nodes_in_group("destructible")
	var facade_usage := {}
	var colliding_buildings = 0
	var sample_building = null
	for building in buildings:
		if not (building is MeshInstance) or not building.has_meta("destructible_building"):
			continue
		var variant = int(building.get_meta("facade_variant"))
		facade_usage[variant] = int(facade_usage.get(variant, 0)) + 1
		var body = building.get_node_or_null("ChunkPhysics")
		var shape = body.get_node_or_null("CollisionShape") if is_instance_valid(body) else null
		if (
			body is StaticBody
			and shape is CollisionShape
			and shape.shape is ConcavePolygonShape
		):
			colliding_buildings += 1
		if sample_building == null:
			sample_building = building

	_expect(buildings.size() == building_count, "every retained building should be in the destructible group")
	_expect(colliding_buildings == building_count, "every retained building should have its own trimesh collider")
	for variant in range(4):
		_expect(
			int(facade_usage.get(variant, 0)) > 0,
			"facade variant %d should be assigned to at least one building" % variant
		)

	var ground = berlin_map.get_node_or_null("GroundSurface/CollisionShape")
	_expect(
		ground is CollisionShape and ground.shape is BoxShape,
		"walkable ground should use one continuous solid shape rather than PlaneShape"
	)

	if sample_building != null:
		var count_before = berlin_map.get_building_count()
		var local_bounds = sample_building.get_aabb()
		var world_center = sample_building.global_transform.xform(
			local_bounds.position + local_bounds.size * 0.5
		)
		var removed = berlin_map.clear_region(
			AABB(world_center - Vector3(0.05, 0.05, 0.05), Vector3(0.10, 0.10, 0.10)),
			"building"
		)
		_expect(removed >= 1, "semantic cleanup should remove complete individual buildings")
		_expect(
			berlin_map.get_building_count() == count_before - removed,
			"building registry should shrink by the number of cleared individual houses"
		)

	if failures.empty():
		print(
			"PASS: %d individual buildings, %d duplicates removed, %d aggregate components, four random facades"
			% [building_count, duplicate_count, aggregate_count]
		)
		quit(0)
		return
	for failure in failures:
		printerr("FAIL: %s" % failure)
	quit(1)


func _expect(condition: bool, message: String):
	if not condition:
		failures.append(message)
