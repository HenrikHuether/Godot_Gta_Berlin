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

	_expect(main.mission_one != null, "main should create the Mission 1 controller")
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

	if failures.empty():
		print("PASS: Mission 1 state flow, vehicle resources, damage, and wanted level")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)


func _test_guard_route(main, mission):
	_expect(mission.state == 0, "mission should begin with the enter-car objective")
	main.in_car = true
	mission.update_mission(0.016)
	_expect(mission.state == 1, "entering the car should start the drive objective")

	main.car.translation = Vector3(-218.0, 0.75, -84.0)
	main.player.translation = main.car.translation + Vector3.UP
	mission.update_mission(0.016)
	_expect(mission.state == 2, "arriving in the occupied car should start access search")

	main.in_car = false
	main.player.translation = Vector3(-213.5, 1.0, -74.0)
	_expect(mission.handle_interact(), "interacting near the guard should open the dialogue")
	_expect(mission.is_overlay_open(), "guard interaction should display the free-text panel")
	mission._on_dialogue_submitted("Guten Tag, ich bringe den Aktenkoffer zur Uebergabe in den Bundestag.")
	mission._on_dialogue_submitted("Bitte pruefen Sie meinen Dienstausweis und rufen Sie die Dienststelle an.")
	_expect(mission.front_door_open, "two complementary free-text arguments should open the main door")
	mission.update_mission(0.016)
	_expect(mission.state == 3, "approved access should advance to entering the building")

	mission.close_dialogue()
	main.player.translation = Vector3(-218.0, 1.0, -44.5)
	mission.update_mission(0.016)
	_expect(mission.state == 4, "reaching the interior should enable case delivery")
	_expect(mission.handle_interact(), "delivery interaction should be consumed by the mission")
	_expect(mission.mission_completed and not mission.has_briefcase, "delivery should complete exactly once and consume the case")


func _test_hidden_route(main, mission):
	main.in_car = false
	mission.set_state(2)
	mission.push_crate.translation = Vector3(-245.0, 0.8, -48.8)
	mission.check_hidden_passage()
	_expect(mission.hidden_door_open, "moving the crate should reveal the service passage")
	_expect(mission.access_route == "Geheimgang", "hidden entry should be recorded as the chosen route")
	mission.update_mission(0.016)
	_expect(mission.state == 3, "the revealed passage should grant building access")

	main.player.translation = Vector3(-218.0, 1.0, -44.5)
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


func _expect(condition: bool, message: String):
	if not condition:
		failures.append(message)
