extends SceneTree

const MAIN_SCENE = preload("res://main.tscn")

var failures := []


func _init():
	call_deferred("_run")


func _run():
	var main = MAIN_SCENE.instance()
	get_root().add_child(main)
	yield(self, "idle_frame")
	main.set_process(false)
	main.set_physics_process(false)
	main.car.set_simulation_enabled(false)
	if is_instance_valid(main.helicopter):
		main.helicopter.set_simulation_enabled(false)

	var berlin_map = main.get_node_or_null("BerlinMap")
	var building = _find_imported_building()
	_expect(building is MeshInstance, "the live map should expose an imported destructible building")
	if building == null:
		_finish()
		return

	var collision_body = building.get_node_or_null("ChunkPhysics")
	_expect(collision_body is StaticBody, "the imported building should own its individual collider")
	_expect(
		main.find_destructible_building(collision_body) == building,
		"rocket collision lookup should resolve the collider back to exactly one imported house"
	)

	var world_bounds = main.get_destructible_building_bounds(building)
	_expect(
		world_bounds.size.x > 0.1 and world_bounds.size.y > 0.1 and world_bounds.size.z > 0.1,
		"imported destruction bounds should come from the real mesh"
	)
	var expected_center = world_bounds.position + world_bounds.size * 0.5
	var building_count_before = berlin_map.get_building_count()
	main.collapse_building(building)

	_expect(building.is_queued_for_deletion(), "a direct rocket hit should queue only the struck house for deletion")
	_expect(main.destroyed_buildings.has(building), "collapsed imported house should enter the destruction registry")
	_expect(
		berlin_map.get_building_count() == building_count_before - 1,
		"one collapse should remove exactly one building from the active map count"
	)
	var rubble = main.get_node_or_null("Rubble_%s" % building.name)
	_expect(is_instance_valid(rubble), "the imported house should be replaced by rubble")
	if is_instance_valid(rubble):
		_expect(
			Vector2(
				rubble.global_transform.origin.x - expected_center.x,
				rubble.global_transform.origin.z - expected_center.z
			).length() < 0.05,
			"rubble should appear at the imported mesh centre rather than the GLB source origin"
		)
		_expect(
			abs(rubble.global_transform.origin.y - world_bounds.position.y) < 0.05,
			"rubble should rest at the imported building footprint"
		)
		_expect(rubble.get_child_count() >= 20, "collapse should create debris and fire effects")

	yield(self, "idle_frame")
	_expect(not is_instance_valid(building), "the struck imported building and its collider should be freed")
	_finish()


func _find_imported_building():
	for candidate in get_nodes_in_group("destructible"):
		if (
			candidate is MeshInstance
			and candidate.has_meta("destructible_building")
			and not candidate.is_queued_for_deletion()
		):
			return candidate
	return null


func _expect(condition: bool, message: String):
	if not condition:
		failures.append(message)


func _finish():
	if failures.empty():
		print("PASS: imported Berlin building collapses individually into correctly placed rubble")
		quit(0)
		return
	for failure in failures:
		printerr("FAIL: %s" % failure)
	quit(1)
