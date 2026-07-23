extends SceneTree

const HELICOPTER_SCENE = preload("res://scenes/PlayerHelicopter.tscn")

var failures := []
var stage: Spatial
var helicopter: RigidBody
var rotor_failures := []
var hard_impacts := []
var fatal_crashes := []


func _init():
	Engine.iterations_per_second = 120
	Engine.physics_jitter_fix = 0.0
	call_deferred("_run")


func _run():
	_test_force_helpers()
	_build_test_world()
	yield(_step_physics(60), "completed")
	_test_scene_contract()
	yield(_test_spool_and_lift(), "completed")
	yield(_test_rotor_overlap_failure_and_crash(), "completed")
	yield(_test_fragment_self_collision_exclusion(), "completed")
	yield(_test_low_altitude_crash_latch(), "completed")

	if failures.empty():
		print("PASS: helicopter spool, aerodynamic helpers, lift, rotor failure, and fatal crash")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)


func _test_force_helpers():
	var helper = HELICOPTER_SCENE.instance()
	_expect(abs(helper.mass - 2600.0) < 0.01, "helicopter scene should use the requested 2600 kg mass")

	var spool_ratio = 0.0
	for _frame in range(600):
		spool_ratio = helper.calculate_rotor_spool(spool_ratio, 1.0, 1.0 / 120.0, helper.ROTOR_SPOOL_UP_TIME)
	_expect(spool_ratio > 0.84 and spool_ratio < 0.90, "five seconds of spool-up should approach, but not instantly reach, governed RPM")
	_expect(helper.calculate_rotor_spool(0.7, 0.0, 0.0, 5.0) == 0.7, "zero-duration spool integration should not change RPM")

	var hover_collective = helper.HELICOPTER_MASS * helper.GRAVITY_ACCELERATION / helper.MAX_MAIN_ROTOR_THRUST
	var hover_thrust = helper.calculate_main_rotor_thrust(
		hover_collective,
		1.0,
		1.0,
		1.0,
		1.0,
		1.0
	)
	_expect(abs(hover_thrust - helper.HELICOPTER_MASS * helper.GRAVITY_ACCELERATION) < 1.0, "OGE hover collective should balance weight")

	var close_ground_effect = helper.calculate_ground_effect_factor(helper.MAIN_ROTOR_RADIUS * 0.45)
	var far_ground_effect = helper.calculate_ground_effect_factor(helper.MAIN_ROTOR_RADIUS * 1.5)
	_expect(close_ground_effect > 1.10 and close_ground_effect <= helper.GROUND_EFFECT_MAX, "low rotor height should create bounded ground effect")
	_expect(abs(far_ground_effect - 1.0) < 0.001, "ground effect should fade out by 1.5 rotor radii")
	_expect(helper.calculate_translational_lift_factor(16.0) > helper.calculate_translational_lift_factor(0.0), "forward airspeed should create effective translational lift")

	var vortex_factor = helper.calculate_vortex_ring_factor(10.0, 0.0, 0.9)
	var recovered_vortex_factor = helper.calculate_vortex_ring_factor(10.0, 16.0, 0.9)
	_expect(vortex_factor < 0.80, "rapid vertical descent at high collective should enter vortex-ring loss")
	_expect(recovered_vortex_factor > 0.99, "translational airspeed should recover vortex-ring lift")
	_expect(helper.calculate_high_speed_factor(80.0) < 0.80, "very high airspeed should reduce rotor efficiency")

	var local_velocity = Vector3(18.0, -7.0, -42.0)
	var drag = helper.calculate_anisotropic_drag(local_velocity)
	_expect(drag.dot(local_velocity) < 0.0, "anisotropic drag should always oppose nonzero velocity")
	_expect(not is_nan(drag.length()) and not is_inf(drag.length()), "drag helper should remain finite")

	var forward_disk = helper.calculate_disk_normal_local(1.0, 0.0)
	var right_disk = helper.calculate_disk_normal_local(0.0, 1.0)
	_expect(forward_disk.z < -0.10, "positive pitch input should tilt rotor thrust forward along -Z")
	_expect(right_disk.x > 0.10, "positive roll input should tilt rotor thrust toward +X")
	_expect(
		helper.calculate_yaw_control_torque(1.0, 1.0) < 0.0,
		"positive right-pedal input should turn a -Z-facing helicopter to the right"
	)
	_expect(
		helper.calculate_yaw_control_torque(-1.0, 1.0) > 0.0,
		"negative left-pedal input should turn a -Z-facing helicopter to the left"
	)
	helper.free()


func _build_test_world():
	stage = Spatial.new()
	stage.name = "HelicopterTestWorld"
	get_root().add_child(stage)

	var ground = StaticBody.new()
	ground.name = "TestGround"
	ground.translation = Vector3(0, -0.25, 0)
	stage.add_child(ground)
	var ground_collider = CollisionShape.new()
	var ground_shape = BoxShape.new()
	ground_shape.extents = Vector3(120, 0.25, 120)
	ground_collider.shape = ground_shape
	ground.add_child(ground_collider)

	helicopter = HELICOPTER_SCENE.instance()
	helicopter.name = "FlightTestHelicopter"
	helicopter.translation = Vector3(0, 1.50, 0)
	stage.add_child(helicopter)
	helicopter.connect("rotor_destroyed", self, "_on_rotor_destroyed")
	helicopter.connect("hard_impact", self, "_on_hard_impact")
	helicopter.connect("fatal_crash", self, "_on_fatal_crash")


func _test_scene_contract():
	_expect(helicopter is RigidBody, "player helicopter should be a force-driven RigidBody")
	_expect(helicopter.scale.distance_to(Vector3.ONE) < 0.001, "RigidBody root should remain uniformly unscaled")
	_expect(not helicopter.custom_integrator, "helicopter should retain Godot gravity alongside custom rotor forces")
	_expect(helicopter.continuous_cd, "helicopter chassis should enable continuous collision detection")
	_expect(helicopter.contact_monitor and helicopter.contacts_reported >= 16, "helicopter should report enough chassis contacts for crash detection")
	_expect(helicopter.get_node_or_null("MainRotorArea") is Area, "scene should contain a main-rotor swept Area")
	_expect(helicopter.get_node_or_null("TailRotorArea") is Area, "scene should contain a tail-rotor swept Area")
	var main_area = helicopter.get_node_or_null("MainRotorArea")
	var tail_area = helicopter.get_node_or_null("TailRotorArea")
	_expect(main_area.monitoring and main_area.collision_layer == 0 and main_area.collision_mask == 1, "main rotor Area should monitor only layer-one world bodies")
	_expect(tail_area.monitoring and tail_area.collision_layer == 0 and tail_area.collision_mask == 1, "tail rotor Area should monitor only layer-one world bodies")
	_expect(abs(abs(tail_area.global_transform.basis.y.normalized().dot(Vector3.RIGHT)) - 1.0) < 0.001, "tail rotor cylinder axis should point along local X")
	var main_shape_node = helicopter.get_node_or_null("MainRotorArea/CollisionShape")
	var tail_shape_node = helicopter.get_node_or_null("TailRotorArea/CollisionShape")
	_expect(main_shape_node and main_shape_node.shape is CylinderShape, "main rotor Area should use a cylindrical swept disk")
	_expect(tail_shape_node and tail_shape_node.shape is CylinderShape, "tail rotor Area should use a cylindrical swept disk")
	if main_shape_node and main_shape_node.shape is CylinderShape:
		_expect(abs(main_shape_node.shape.radius - 5.2) < 0.001, "main rotor disk radius should be 5.2 m")
		_expect(main_shape_node.shape.height >= 0.8, "main rotor sweep should be thick enough to resist high-speed tunnelling")
	if tail_shape_node and tail_shape_node.shape is CylinderShape:
		_expect(abs(tail_shape_node.shape.radius - 0.59) < 0.001, "tail rotor disk radius should be 0.59 m")
		_expect(tail_shape_node.shape.height >= 0.6, "tail rotor sweep should be thick enough to resist high-speed tunnelling")
	_expect(helicopter.get_node_or_null("HelicopterVisual") == null, "isolated physics scene should not instantiate the heavy GLB")
	for method_name in [
		"bind_visuals",
		"set_driver_active",
		"set_driver_input",
		"set_engine_enabled",
		"set_simulation_enabled",
		"set_collective",
		"get_rotor_rpm",
		"get_collective",
		"get_speed_kph",
		"is_rotor_failed",
		"trigger_rotor_failure",
		"teleport_to",
		"freeze_as_wreck"
	]:
		_expect(helicopter.has_method(method_name), "public integration API should provide %s" % method_name)
	for signal_name in ["rotor_destroyed", "hard_impact", "fatal_crash"]:
		_expect(helicopter.has_signal(signal_name), "controller should expose %s signal" % signal_name)
	helicopter.set_simulation_enabled(false)
	_expect(helicopter.mode == RigidBody.MODE_STATIC, "disabled helicopter simulation should use static mode")
	helicopter.set_simulation_enabled(true)
	_expect(helicopter.mode == RigidBody.MODE_RIGID, "re-enabled helicopter simulation should restore rigid mode")


func _test_spool_and_lift():
	helicopter.set_driver_active(true)
	helicopter.set_collective(helicopter.MIN_COLLECTIVE)
	helicopter.set_engine_enabled(true)
	yield(_step_physics(600), "completed")
	_expect(helicopter.get_rotor_rpm_ratio() > 0.82, "engine should spool the rotor above 82 percent within five seconds")
	_expect(helicopter.get_rotor_rpm() < helicopter.NOMINAL_ROTOR_RPM + 1.0, "governor should not substantially overspeed the main rotor")
	_expect(not helicopter.is_rotor_failed() and rotor_failures.empty(), "spinning swept Areas should not self-trigger against their parent RigidBody")

	var lift_start_y = helicopter.global_transform.origin.y
	helicopter.set_collective(0.72)
	helicopter.set_driver_input(0.0, 0.0, 0.0, 0.0)
	yield(_step_physics(300), "completed")
	var lift_gain = helicopter.global_transform.origin.y - lift_start_y
	_expect(lift_gain > 1.0, "high collective at governed RPM should lift the helicopter clear of the ground")
	_expect(helicopter.get_vertical_speed() > -0.5, "powered collective should not leave the helicopter in an uncontrolled descent")
	var telemetry = helicopter.get_force_telemetry()
	_expect(float(telemetry.thrust) > helicopter.HELICOPTER_MASS * helicopter.GRAVITY_ACCELERATION, "climb test should generate more thrust than weight")
	_expect(float(telemetry.ground_effect) >= 1.0 and float(telemetry.ground_effect) <= helicopter.GROUND_EFFECT_MAX + 0.001, "sampled ground effect should stay bounded")
	helicopter.set_collective(helicopter.MIN_COLLECTIVE)
	helicopter.set_engine_enabled(false)
	yield(_step_physics(120), "completed")


func _test_rotor_overlap_failure_and_crash():
	rotor_failures.clear()
	hard_impacts.clear()
	fatal_crashes.clear()
	if is_instance_valid(helicopter):
		helicopter.queue_free()
	yield(self, "idle_frame")

	helicopter = HELICOPTER_SCENE.instance()
	helicopter.name = "CrashTestHelicopter"
	helicopter.translation = Vector3(30, 1.50, 0)
	stage.add_child(helicopter)
	helicopter.connect("rotor_destroyed", self, "_on_rotor_destroyed")
	helicopter.connect("hard_impact", self, "_on_hard_impact")
	helicopter.connect("fatal_crash", self, "_on_fatal_crash")

	var dummy_visual = Spatial.new()
	dummy_visual.name = "DummyEC135Visual"
	helicopter.add_child(dummy_visual)
	var main_visual = MeshInstance.new()
	main_visual.name = "Object_9"
	dummy_visual.add_child(main_visual)
	var tail_visual = MeshInstance.new()
	tail_visual.name = "Object_7"
	dummy_visual.add_child(tail_visual)
	helicopter.bind_visuals(dummy_visual)

	var obstacle = StaticBody.new()
	obstacle.name = "RotorTestObstacle"
	obstacle.translation = Vector3(33.0, 3.05, -0.15)
	stage.add_child(obstacle)
	var obstacle_collider = CollisionShape.new()
	var obstacle_shape = BoxShape.new()
	obstacle_shape.extents = Vector3(0.25, 0.65, 0.25)
	obstacle_collider.shape = obstacle_shape
	obstacle.add_child(obstacle_collider)

	helicopter.set_collective(helicopter.MIN_COLLECTIVE)
	helicopter.set_engine_enabled(true)
	yield(_step_physics(300), "completed")
	_expect(rotor_failures.size() == 1, "an obstacle already inside the swept disk should destroy the rotor once RPM becomes dangerous")
	_expect(helicopter.is_rotor_failed(), "public is_rotor_failed alias should expose critical rotor state")
	_expect(not helicopter.is_rotor_operational(), "rotor contact should immediately make the rotor non-operational")
	_expect(not helicopter.engine_enabled, "rotor contact should shut the engine down")
	_expect(helicopter.mode == RigidBody.MODE_RIGID, "rotor failure should leave the chassis dynamic so it can fall")
	_expect(fatal_crashes.empty(), "rotor failure while stationary should not explode before a subsequent crash")
	yield(self, "idle_frame")
	yield(self, "idle_frame")
	_expect(not main_visual.visible and not tail_visual.visible, "rotor failure should hide Object_9 and Object_7 visuals")
	_expect(_count_fragment_nodes() >= 7, "rotor failure should spawn visible main- and tail-rotor fragments")

	obstacle.queue_free()
	helicopter.teleport_to(Transform(Basis(), Vector3(30, 14.0, 0)))
	yield(_step_physics(4), "completed")
	var fall_start_y = helicopter.global_transform.origin.y
	yield(_step_physics(90), "completed")
	_expect(helicopter.global_transform.origin.y < fall_start_y - 1.0, "failed rotor should provide no lift and the RigidBody should fall")
	_expect(fatal_crashes.empty(), "fatal crash should wait for chassis contact rather than occur in mid-air")

	var frames_waited = 0
	while fatal_crashes.empty() and frames_waited < 600:
		yield(self, "physics_frame")
		frames_waited += 1
	yield(self, "idle_frame")
	_expect(fatal_crashes.size() == 1, "first significant chassis impact after rotor failure should emit one fatal_crash")
	if not fatal_crashes.empty():
		_expect(float(fatal_crashes[0]) >= helicopter.FATAL_CRASH_THRESHOLD, "fatal crash telemetry should exceed its threshold")
	var hard_impact_count_after_crash = hard_impacts.size()
	yield(_step_physics(120), "completed")
	_expect(fatal_crashes.size() == 1, "fatal_crash should be emitted at most once")
	_expect(
		hard_impacts.size() == hard_impact_count_after_crash,
		"a consumed landing velocity must not repeat hard-impact damage while the wreck is resting"
	)
	helicopter.freeze_as_wreck()
	helicopter.freeze_as_wreck()
	yield(_step_physics(2), "completed")
	_expect(helicopter.mode == RigidBody.MODE_STATIC, "freeze_as_wreck should be idempotent and leave a static wreck")
	_expect(helicopter.linear_velocity.length() < 0.001 and helicopter.angular_velocity.length() < 0.001, "frozen wreck should have no residual motion")


func _test_low_altitude_crash_latch():
	fatal_crashes.clear()
	helicopter = HELICOPTER_SCENE.instance()
	helicopter.name = "LowAltitudeCrashHelicopter"
	helicopter.translation = Vector3(60, 2.05, 0)
	stage.add_child(helicopter)
	helicopter.connect("fatal_crash", self, "_on_fatal_crash")
	helicopter.linear_velocity = Vector3(0, -10.0, 0)
	helicopter.trigger_rotor_failure("low_altitude_test")
	yield(_step_physics(90), "completed")
	_expect(
		fatal_crashes.size() == 1,
		"a real impact before the arming delay expires must remain latched and explode once armed"
	)
	helicopter.freeze_as_wreck()


func _test_fragment_self_collision_exclusion():
	fatal_crashes.clear()
	helicopter = HELICOPTER_SCENE.instance()
	helicopter.name = "HighAltitudeFragmentHelicopter"
	helicopter.translation = Vector3(90, 100.0, 0)
	stage.add_child(helicopter)
	helicopter.connect("fatal_crash", self, "_on_fatal_crash")
	helicopter.linear_velocity = Vector3(20.0, 0, 0)
	helicopter.trigger_rotor_failure("fragment_exception_test")
	yield(_step_physics(120), "completed")
	_expect(
		fatal_crashes.empty(),
		"spawned rotor fragments must not collide with their own airframe and fake a mid-air fatal crash"
	)
	_expect(helicopter.global_transform.origin.y > 85.0, "high-altitude fragment test should remain clear of the ground")
	helicopter.freeze_as_wreck()


func _count_fragment_nodes() -> int:
	var count = 0
	for child in stage.get_children():
		if child.name.begins_with("MainRotorFragment") or child.name.begins_with("TailRotorFragment"):
			count += 1
	return count


func _step_physics(frame_count: int):
	for _frame in range(frame_count):
		yield(self, "physics_frame")
	yield(self, "idle_frame")


func _expect(condition: bool, message: String):
	if not condition:
		failures.append(message)


func _on_rotor_destroyed(reason: String):
	rotor_failures.append(reason)


func _on_hard_impact(impact_speed: float):
	hard_impacts.append(impact_speed)


func _on_fatal_crash(impact_speed: float):
	fatal_crashes.append(impact_speed)
