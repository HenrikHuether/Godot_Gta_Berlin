extends SceneTree

const MAIN_SCENE = preload("res://main.tscn")
const MISSION_SCRIPT = preload("res://scripts/mission_one.gd")

var failures = []


func _init():
	call_deferred("_run")


func _run():
	var main = MAIN_SCENE.instance()
	get_root().add_child(main)
	yield(self, "idle_frame")
	main.car.set_simulation_enabled(false)

	_expect(main.mission_one != null, "main should create the Mission 1 controller")
	_test_expanded_map_and_site_cleanup(main)
	_test_guard_route(main, main.mission_one)

	var first_mission = main.mission_one
	main.mission_one = null
	if is_instance_valid(first_mission.briefcase_model):
		first_mission.briefcase_model.queue_free()
	first_mission.queue_free()
	yield(self, "idle_frame")

	var hidden_route_mission = MISSION_SCRIPT.new()
	hidden_route_mission.name = "HiddenRouteMissionTest"
	main.add_child(hidden_route_mission)
	hidden_route_mission.setup(main)
	main.mission_one = hidden_route_mission
	_test_hidden_route(main, hidden_route_mission)
	_test_vehicle_and_wanted_systems(main)
	yield(_test_responder_movement(main), "completed")

	if failures.empty():
		print("PASS: Mission 1 state flow, expanded map, clear site, vehicle resources, damage, and wanted level")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)


func _test_expanded_map_and_site_cleanup(main):
	_expect(main.map_expansion != null, "main should create the runtime map expansion")
	if main.map_expansion:
		var bounds = main.map_expansion.get_map_bounds()
		_expect(bounds.position.x == -700.0 and bounds.position.z == -700.0, "expanded map should begin at -700 m on both axes")
		_expect(bounds.size.x == 1400.0 and bounds.size.z == 1400.0, "expanded map should cover 1.4 km on both axes")
		_expect(main.map_expansion.has_node("ExpandedRoadNetwork"), "expanded map should contain its ring and outbound roads")
		_expect(main.map_expansion.has_node("ExpandedDistricts"), "expanded map should contain outer districts")
		var ring_road = main.map_expansion.get_node_or_null("ExpandedRoadNetwork/RingNorth")
		_expect(ring_road is StaticBody and ring_road.has_meta("surface_grip"), "expanded asphalt should provide a tagged physics surface")
		_expect(ring_road.get_node_or_null("CollisionShape") is CollisionShape, "long roads should preserve their primary collider path")
		if ring_road:
			for child in ring_road.get_children():
				if child is CollisionShape and child.shape is BoxShape:
					_expect(max(child.shape.extents.x, child.shape.extents.z) <= 90.1, "large map surfaces should use Bullet-safe collision tiles")
	for incident in [Vector3(650, 0, 0), Vector3(650, 0, 650)]:
		for variant in range(2):
			var route = main.response_route(incident, variant)
			for route_point in route:
				_expect(
					abs(route_point.x) <= 680.0 and abs(route_point.z) <= 680.0,
					"expanded-map responder routes should remain inside the boundary"
				)

	var berlin_map = main.get_node("BerlinMap")
	_expect(berlin_map.has_node("Block_01/Sidewalk"), "Bundestag cleanup should retain the original sidewalk surface")
	_expect(berlin_map.has_node("Block_01/Courtyard"), "Bundestag cleanup should retain the original courtyard surface")
	for removed_path in [
		"Block_02/Building_02_00",
		"Block_02/Building_02_02",
		"Block_02/Building_02_04",
		"Block_06/Building_06_00"
	]:
		_expect(not berlin_map.has_node(removed_path), "%s should be removed because its facade overlaps the Bundestag" % removed_path)
	_expect(berlin_map.has_node("Block_02/Building_02_01"), "non-overlapping neighbouring buildings should remain")
	_expect(berlin_map.has_node("BrandenburgGate"), "Bundestag cleanup should preserve the Brandenburg Gate")


func _test_guard_route(main, mission):
	_expect(mission.state == 0, "mission should begin with the enter-car objective")
	main.in_car = true
	mission.update_mission(0.016)
	_expect(mission.state == 1, "entering the car should start the drive objective")

	var parked_transform = main.car.global_transform
	parked_transform.origin = mission.PARKING_POSITION + Vector3.UP * 0.65
	main.teleport_vehicle(main.car, parked_transform)
	main.player.translation = main.car.translation + Vector3.UP
	mission.update_mission(0.016)
	_expect(mission.state == 2, "arriving in the occupied car should start access search")

	main.in_car = false
	main.player.translation = mission.GUARD_POSITION + Vector3.UP * 0.95
	_expect(mission.handle_interact(), "interacting near the guard should open the dialogue")
	_expect(mission.is_overlay_open(), "guard interaction should display the free-text panel")
	mission._on_dialogue_submitted("Guten Tag, ich bringe den Aktenkoffer zur Uebergabe in den Bundestag.")
	mission._on_dialogue_submitted("Bitte pruefen Sie meinen Dienstausweis und rufen Sie die Dienststelle an.")
	_expect(mission.front_door_open, "two complementary free-text arguments should open the main door")
	mission.update_mission(0.016)
	_expect(mission.state == 3, "approved access should advance to entering the building")

	mission.close_dialogue()
	main.player.translation = mission.DELIVERY_POSITION + Vector3.UP * 0.8
	mission.update_mission(0.016)
	_expect(mission.state == 4, "reaching the interior should enable case delivery")
	_expect(mission.handle_interact(), "delivery interaction should be consumed by the mission")
	_expect(mission.mission_completed and not mission.has_briefcase, "delivery should complete exactly once and consume the case")


func _test_hidden_route(main, mission):
	main.in_car = false
	mission.set_state(2)
	mission.push_crate.translation = mission.CRATE_START + Vector3(0, 0, 3.2)
	mission.check_hidden_passage()
	_expect(mission.hidden_door_open, "moving the crate should reveal the service passage")
	_expect(mission.access_route == "Geheimgang", "hidden entry should be recorded as the chosen route")
	mission.update_mission(0.016)
	_expect(mission.state == 3, "the revealed passage should grant building access")

	main.player.translation = mission.DELIVERY_POSITION + Vector3.UP * 0.8
	mission.update_mission(0.016)
	_expect(mission.state == 4, "hidden route should converge on the same delivery state")
	mission.handle_interact()
	_expect(mission.mission_completed and not mission.has_briefcase, "hidden route should complete the same delivery")


func _test_vehicle_and_wanted_systems(main):
	var previous_fuel = main.car_fuel
	main.consume_car_fuel(1.0, 2.0)
	_expect(main.car_fuel < previous_fuel, "active throttle should consume fuel")

	var previous_health = main.car_health
	main.car_damage_cooldown = 0.0
	var damage = main.apply_car_impact_damage(16.0)
	_expect(damage > 0 and main.car_health < previous_health, "a hard impact should damage the vehicle")

	var previous_wanted = main.wanted_level
	main.dispatch_police(Vector3.ZERO)
	_expect(main.wanted_level == min(3, previous_wanted + 1), "a police dispatch should raise the wanted level")
	var police_car = main.emergency_vehicles[-1].node
	var police_collider = police_car.get_node_or_null("CollisionShape")
	if police_collider is CollisionShape and police_collider.shape is BoxShape:
		var collider_bottom = police_car.translation.y + police_collider.translation.y - police_collider.shape.extents.y
		_expect(abs(collider_bottom - main.HLF_ROAD_SURFACE_Y) < 0.001, "police collider should rest on the new road physics surface")


func _test_responder_movement(main):
	var police_car = main.emergency_vehicles[-1].node
	main.dispatch_fire_department(Vector3(-120, 0, 80))
	var fire_engine = main.emergency_vehicles[-1].node
	var police_start = police_car.translation
	var fire_start = fire_engine.translation
	for _frame in range(90):
		yield(self, "physics_frame")
	var police_travel = Vector2(police_car.translation.x - police_start.x, police_car.translation.z - police_start.z).length()
	var fire_travel = Vector2(fire_engine.translation.x - fire_start.x, fire_engine.translation.z - fire_start.z).length()
	_expect(police_travel > 1.0, "police cars should move across the raised road colliders")
	_expect(fire_travel > 1.0, "the HLF should move across the raised road colliders")
	_expect(abs(police_car.translation.y - main.GOLF_GROUND_HEIGHT) < 0.001, "moving police cars should retain their authored road height")
	_expect(abs(fire_engine.translation.y - main.HLF_GROUND_HEIGHT) < 0.001, "the moving HLF should retain its authored road height")


func _expect(condition: bool, message: String):
	if not condition:
		failures.append(message)
