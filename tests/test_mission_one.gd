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
	if is_instance_valid(main.helicopter) and main.helicopter.has_method("set_simulation_enabled"):
		main.helicopter.set_simulation_enabled(false)

	_expect(main.mission_one != null, "main should create the Mission 1 controller")
	_test_segmented_map_and_site_cleanup(main)
	_test_helicopter_shortcut_conflict(main)
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
		print("PASS: Mission 1 state flow, segmented Berlin map, clear site, vehicle resources, damage, and wanted level")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)


func _test_segmented_map_and_site_cleanup(main):
	_expect(main.map_expansion == null, "the obsolete procedural map expansion should remain disabled")
	var berlin_map = main.get_node("BerlinMap")
	_expect(berlin_map.has_method("get_map_bounds"), "segmented Berlin map should expose its playable bounds")
	_expect(berlin_map.has_method("clear_region"), "segmented Berlin map should expose semantic building cleanup")
	var bounds = berlin_map.get_map_bounds()
	_expect(bounds.size.x > 22000.0, "satellite map should span more than 22 km east-west")
	_expect(bounds.size.z > 14600.0, "satellite map should span more than 14.6 km north-south")
	_expect(bounds.size.y >= 115.0, "map bounds should include the tallest imported building")

	var source = berlin_map.get_node_or_null("Source")
	var generator = berlin_map.get_node_or_null("Generator")
	var ground_surface = berlin_map.get_node_or_null("GroundSurface")
	_expect(is_instance_valid(source), "Berlin map should retain the imported GLB source root")
	_expect(
		is_instance_valid(source) and source.get_child_count() >= 280,
		"segmented GLB should retain all terrain, building, and reference nodes after mission cleanup"
	)
	_expect(ground_surface is StaticBody, "segmented map should provide a stable terrain collider")
	if ground_surface is StaticBody:
		_expect(abs(float(ground_surface.get_meta("surface_grip")) - 0.52) < 0.001, "terrain should expose its authored driving grip")
		var ground_collision = ground_surface.get_node_or_null("CollisionShape")
		_expect(
			ground_collision is CollisionShape and ground_collision.shape is BoxShape,
			"walkable terrain should use one continuous solid shape rather than the KinematicBody-breaking PlaneShape"
		)
	_expect(main.player.collision_layer == 1 and main.player.collision_mask == 1, "player should ignore thin road-edge collision meshes")
	_expect(bool(main.car.collision_mask & 2), "vehicle suspension should still query the dedicated asphalt layer")

	_expect(is_instance_valid(generator) and generator.has_method("get_diagnostics"), "map should own its street and canal generator")
	if is_instance_valid(generator) and generator.has_method("get_diagnostics"):
		var diagnostics = generator.get_diagnostics()
		_expect(bool(diagnostics.get("built", false)), "street and canal generation should finish during map startup")
		_expect(int(diagnostics.get("street_vertex_count", 0)) == 231, "Street graph should retain all source vertices")
		_expect(int(diagnostics.get("street_edge_count", 0)) == 285, "Street graph should retain all source edges")
		_expect(int(diagnostics.get("canal_vertex_count", 0)) == 57, "Kanal graph should retain all source vertices")
		_expect(int(diagnostics.get("canal_edge_count", 0)) == 56, "Kanal graph should retain all source edges")
		_expect(int(diagnostics.get("road_chunk_count", 0)) > 0, "Street graph should generate colliding road chunks")
		_expect(int(diagnostics.get("canal_chunk_count", 0)) > 0, "Kanal graph should generate visible water chunks")

	var road_body = _find_first_type(generator.get_node_or_null("RoadChunks"), "StaticBody") if is_instance_valid(generator) else null
	_expect(road_body is StaticBody, "generated asphalt should contain a StaticBody")
	if road_body is StaticBody:
		_expect(road_body.collision_layer == 2, "asphalt should use the dedicated non-player collision layer")
		_expect(abs(float(road_body.get_meta("surface_grip")) - 1.02) < 0.001, "generated asphalt should expose road grip")
		var road_collision = _find_first_type(road_body, "CollisionShape")
		_expect(
			road_collision is CollisionShape and road_collision.shape is ConcavePolygonShape,
			"generated asphalt should use a triangle-mesh collision"
		)
	var canal_root = generator.get_node_or_null("CanalChunks") if is_instance_valid(generator) else null
	_expect(_find_first_type(canal_root, "Area") is Area, "generated canal should contain water trigger Areas")
	_expect(_find_first_type(canal_root, "StaticBody") == null, "canal water should not be a solid driving surface")

	for incident in [Vector3(650, 0, 0), Vector3(650, 0, 650)]:
		for variant in range(2):
			var route = main.response_route(incident, variant)
			_expect(route.size() >= 2, "road graph should return a responder route")
			for route_point in route:
				_expect(
					route_point.x >= bounds.position.x
					and route_point.x <= bounds.position.x + bounds.size.x
					and route_point.z >= bounds.position.z
					and route_point.z <= bounds.position.z + bounds.size.z,
					"responder graph waypoints should remain inside the imported map"
				)

	var mission_building = main.mission_one.get_node_or_null("BundestagMissionBuilding")
	_expect(is_instance_valid(mission_building), "mission should build the Bundestag shell")
	if is_instance_valid(mission_building):
		var roof_terrace = mission_building.get_node_or_null("RoofTerrace")
		_expect(roof_terrace is StaticBody, "Bundestag roof terrace should support helicopter landings")
		var dome_hull = mission_building.get_node_or_null("DomeCollisionHull")
		_expect(dome_hull is StaticBody, "the visible Reichstag dome should have a solid rotor collision hull")
		if dome_hull is StaticBody:
			var dome_collision = dome_hull.get_node_or_null("CollisionShape")
			_expect(
				dome_collision is CollisionShape and dome_collision.shape is ConvexPolygonShape,
				"dome collision should use the same convex profile as the visible glass"
			)
			if dome_collision is CollisionShape and dome_collision.shape is ConvexPolygonShape:
				var dome_points = dome_collision.shape.points
				var highest_point = -100000.0
				var widest_radius = 0.0
				for dome_point in dome_points:
					highest_point = max(highest_point, dome_point.y)
					widest_radius = max(widest_radius, Vector2(dome_point.x, dome_point.z).length())
				_expect(highest_point >= main.mission_one.BUILDING_HEIGHT + main.mission_one.DOME_HEIGHT, "dome hull should reach the full visible glass height")
				_expect(widest_radius >= main.mission_one.DOME_RADIUS, "dome hull should cover the full visible base radius")


func _test_helicopter_shortcut_conflict(main):
	var restart_event = InputEventKey.new()
	restart_event.pressed = true
	restart_event.scancode = KEY_R
	var previous_state = main.mission_one.state
	main.mission_one.state = main.mission_one.MissionState.COMPLETE
	main.in_helicopter = true
	_expect(
		not main.mission_one.handle_shortcut(restart_event),
		"right-pedal R input must not restart the mission while flying the EC135"
	)
	_expect(
		main.mission_one.get_context_prompt() == "",
		"mission restart prompt must not hide the helicopter exit prompt while flying"
	)
	main.mission_one.state = main.mission_one.MissionState.ENTER_BUILDING
	main.player.global_transform = Transform(Basis(), main.mission_one.BUILDING_CENTER + Vector3(0, 35, 0))
	main.mission_one.update_mission(0.0)
	_expect(
		main.mission_one.state == main.mission_one.MissionState.ENTER_BUILDING,
		"flying over the Bundestag must not skip the enter-building objective"
	)
	main.in_helicopter = false
	main.mission_one.state = previous_state


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


func _expect(condition: bool, message: String):
	if not condition:
		failures.append(message)
