extends SceneTree

const VEHICLE_SCENE = preload("res://scenes/PlayerVehicle.tscn")

var failures := []
var hard_impacts := []
var freeze_on_hard_impact := false
var stage: Spatial
var vehicle: RigidBody


func _init():
	Engine.iterations_per_second = 120
	Engine.physics_jitter_fix = 0.0
	call_deferred("_run")


func _run():
	_test_force_helpers()
	_build_test_world()
	yield(_step_physics(240), "completed")
	_test_settled_suspension()

	var start_position = vehicle.global_transform.origin
	vehicle.set_driver_active(true)
	vehicle.set_driver_input(1.0, 0.0, 0.0, 0.0)
	yield(_step_physics(360), "completed")
	var acceleration_speed = vehicle.get_forward_speed()
	var acceleration_distance = -(vehicle.global_transform.origin.z - start_position.z)
	_expect(acceleration_speed > 4.0 and acceleration_speed < 38.0, "full throttle should create plausible forward speed")
	_expect(acceleration_distance > 8.0, "full throttle should move the car forward")
	_expect(abs(vehicle.global_transform.origin.x - start_position.x) < 1.8, "straight acceleration should not create large lateral drift")
	_expect(vehicle.get_grounded_wheel_count() >= 2, "at least two wheels should remain grounded while accelerating")
	_expect(vehicle.global_transform.basis.y.normalized().dot(Vector3.UP) > 0.72, "the car should remain upright while accelerating")

	vehicle.set_driver_input(0.0, 0.0, 1.0, 0.0)
	yield(_step_physics(240), "completed")
	var braking_speed = abs(vehicle.get_forward_speed())
	_expect(braking_speed < abs(acceleration_speed) * 0.45 + 0.8, "brakes should substantially reduce speed")
	_expect(vehicle.get_forward_speed() > -1.0, "braking should not launch the car backwards")

	var reset_transform = Transform(Basis(), Vector3(0, 0.72, 0))
	vehicle.teleport_to(reset_transform)
	vehicle.set_driver_active(true)
	yield(_step_physics(180), "completed")
	vehicle.set_driver_input(0.75, 0.0, 0.0, 0.0)
	yield(_step_physics(220), "completed")
	var steering_start_position = vehicle.global_transform.origin
	var steering_start_forward = -vehicle.global_transform.basis.z.normalized()
	vehicle.set_driver_input(0.65, -0.45, 0.0, 0.0)
	yield(_step_physics(100), "completed")
	var steering_end_forward = -vehicle.global_transform.basis.z.normalized()
	var lateral_travel = abs(vehicle.global_transform.origin.x - steering_start_position.x)
	_expect(lateral_travel > 0.20, "steering should create measurable lateral travel")
	_expect(steering_start_forward.dot(steering_end_forward) < 0.999, "steering should change the vehicle heading")
	_expect(vehicle.global_transform.basis.y.normalized().dot(Vector3.UP) > 0.68, "the car should remain stable through a steering input")

	vehicle.set_driver_active(false)
	vehicle.teleport_to(Transform(Basis(), Vector3(0, 0.72, 40)))
	yield(_step_physics(2), "completed")
	freeze_on_hard_impact = true
	vehicle.linear_velocity = Vector3(0, 0, -18)
	yield(_step_physics(100), "completed")
	_expect(not hard_impacts.empty(), "a fast chassis collision should emit a filtered hard-impact event")
	if not hard_impacts.empty():
		_expect(float(hard_impacts[0]) >= vehicle.IMPACT_THRESHOLD, "hard-impact telemetry should exceed its configured threshold")

	_expect(vehicle.mode == RigidBody.MODE_STATIC, "hard-impact listeners should be able to freeze the car during physics integration")
	vehicle.freeze_as_wreck() # Idempotent cleanup if the preceding assertion failed.
	yield(_step_physics(2), "completed")
	_expect(vehicle.mode == RigidBody.MODE_STATIC, "a destroyed vehicle should become a static wreck")
	_expect(abs(vehicle.get_forward_speed()) < 0.001, "a static wreck should report zero forward speed")
	for wheel_state in vehicle.get_wheel_states():
		_expect(abs(float(wheel_state.longitudinal_speed)) < 0.001, "wrecked wheels should stop their visual spin")

	print("Vehicle benchmark: %.1f km/h after 3 s, %.1f m travelled, %.1f km/h after braking" % [
		abs(acceleration_speed) * 3.6,
		acceleration_distance,
		braking_speed * 3.6
	])
	if failures.empty():
		print("PASS: four-wheel suspension, drivetrain, braking, steering, and force helpers")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)


func _test_force_helpers():
	var helper = VEHICLE_SCENE.instance()
	_expect(helper.calculate_suspension_force(0.0, 2.0) == 0.0, "an uncompressed spring should not pull the chassis downward")
	_expect(abs(helper.calculate_suspension_force(0.1, 0.0) - 3300.0) < 0.01, "spring force should follow Hooke's law")
	_expect(helper.calculate_suspension_force(1.0, 10.0) <= helper.MAX_SUSPENSION_FORCE, "suspension force should stay clamped")
	var unclamped_force = Vector2(8000, 6000)
	var clamped_force = helper.clamp_friction_circle(unclamped_force, 5000.0)
	_expect(abs(clamped_force.length() - 5000.0) < 0.01, "combined tire force should respect the friction circle")
	_expect(clamped_force.normalized().dot(unclamped_force.normalized()) > 0.9999, "friction-circle clamping should preserve force direction")
	_expect(abs(helper.calculate_slip_ratio(10.0, 10.0)) < 0.0001, "matching road and wheel speed should have zero slip")
	_expect(helper.calculate_slip_ratio(10.0, 12.0) > 0.0, "a faster wheel should report positive slip")
	_expect(helper.calculate_slip_ratio(10.0, 8.0) < 0.0, "a slower wheel should report negative slip")
	var standstill_slip = helper.calculate_slip_ratio(0.0, 0.0)
	_expect(not is_nan(standstill_slip) and not is_inf(standstill_slip), "standstill slip should stay finite")
	helper.free()


func _build_test_world():
	stage = Spatial.new()
	stage.name = "VehicleTestWorld"
	get_root().add_child(stage)

	var ground = StaticBody.new()
	ground.name = "AsphaltTestGround"
	ground.translation = Vector3(0, -0.25, 0)
	ground.set_meta("surface_grip", 1.02)
	ground.set_meta("rolling_resistance", 1.0)
	stage.add_child(ground)
	var ground_collider = CollisionShape.new()
	var ground_shape = BoxShape.new()
	ground_shape.extents = Vector3(100, 0.25, 100)
	ground_collider.shape = ground_shape
	ground.add_child(ground_collider)

	var wall = StaticBody.new()
	wall.name = "ImpactTestWall"
	wall.translation = Vector3(0, 1.5, 30)
	stage.add_child(wall)
	var wall_collider = CollisionShape.new()
	var wall_shape = BoxShape.new()
	wall_shape.extents = Vector3(7, 1.5, 0.3)
	wall_collider.shape = wall_shape
	wall.add_child(wall_collider)

	vehicle = VEHICLE_SCENE.instance()
	vehicle.name = "TestCar"
	vehicle.translation = Vector3(0, 0.72, 0)
	stage.add_child(vehicle)
	vehicle.set_driver_active(false)
	vehicle.connect("hard_impact", self, "_on_vehicle_hard_impact")


func _test_settled_suspension():
	_expect(vehicle.get_grounded_wheel_count() == 4, "all four suspension rays should find the ground at rest")
	_expect(vehicle.global_transform.basis.y.normalized().dot(Vector3.UP) > 0.90, "the settled chassis should remain upright")
	_expect(abs(vehicle.linear_velocity.y) < 0.65, "the suspension should settle without persistent vertical bouncing")
	_expect(vehicle.global_transform.origin.y > 0.35 and vehicle.global_transform.origin.y < 1.20, "settled ride height should remain plausible")
	var total_load = vehicle.get_total_normal_load()
	_expect(total_load > vehicle.mass * 9.81 * 0.40 and total_load < vehicle.mass * 9.81 * 1.70, "settled wheel loads should support the vehicle weight")
	for wheel_state in vehicle.get_wheel_states():
		_expect(float(wheel_state.compression) >= 0.0 and float(wheel_state.compression) <= vehicle.SUSPENSION_TRAVEL + 0.001, "wheel compression should stay inside suspension travel")
		_expect(float(wheel_state.normal_load) >= 0.0, "wheel normal load should never be negative")


func _step_physics(frame_count: int):
	for _frame in range(frame_count):
		yield(self, "physics_frame")
	yield(self, "idle_frame")


func _expect(condition: bool, message: String):
	if not condition:
		failures.append(message)


func _on_vehicle_hard_impact(impact_speed: float):
	hard_impacts.append(impact_speed)
	if freeze_on_hard_impact:
		vehicle.freeze_as_wreck()
