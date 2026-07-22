extends SceneTree

const VEHICLE_SCENE = preload("res://scenes/PlayerVehicle.tscn")
const PHYSICS_FPS := 120.0
const TARGET_SPEED := 100.0 / 3.6


func _init():
	Engine.iterations_per_second = int(PHYSICS_FPS)
	Engine.physics_jitter_fix = 0.0
	call_deferred("_run")


func _run():
	var stage = Spatial.new()
	get_root().add_child(stage)
	for segment_index in range(12):
		var ground = StaticBody.new()
		ground.name = "CalibrationRoad_%02d" % segment_index
		ground.translation = Vector3(0, -0.25, 75.0 - float(segment_index) * 150.0)
		ground.set_meta("surface_grip", 1.02)
		ground.set_meta("rolling_resistance", 1.0)
		stage.add_child(ground)
		var ground_collider = CollisionShape.new()
		var ground_shape = BoxShape.new()
		ground_shape.extents = Vector3(25, 0.25, 75.1)
		ground_collider.shape = ground_shape
		ground.add_child(ground_collider)

	var car = VEHICLE_SCENE.instance()
	car.translation = Vector3(0, 0.72, 0)
	stage.add_child(car)
	for _settle_frame in range(240):
		yield(self, "physics_frame")
	car.set_driver_active(true)
	car.set_driver_input(1.0, 0.0, 0.0, 0.0)
	var acceleration_start = car.global_transform.origin
	var acceleration_frames := 0
	while acceleration_frames < int(PHYSICS_FPS * 16.0) and car.get_forward_speed() < TARGET_SPEED:
		yield(self, "physics_frame")
		acceleration_frames += 1
	var acceleration_time = float(acceleration_frames) / PHYSICS_FPS
	var acceleration_distance = car.global_transform.origin.distance_to(acceleration_start)
	var reached_100 = car.get_forward_speed() >= TARGET_SPEED
	var terminal_speed = car.get_speed_kph()
	var terminal_rpm = car.get_engine_rpm()
	var terminal_gear = car.get_current_gear()
	var terminal_grounded = car.get_grounded_wheel_count()

	car.set_driver_input(0.0, 0.0, 1.0, 0.0)
	var braking_start = car.global_transform.origin
	var braking_frames := 0
	while braking_frames < int(PHYSICS_FPS * 8.0) and abs(car.get_forward_speed()) > 0.5:
		yield(self, "physics_frame")
		braking_frames += 1
	var braking_time = float(braking_frames) / PHYSICS_FPS
	var braking_distance = car.global_transform.origin.distance_to(braking_start)

	print("Vehicle calibration: 0-100 km/h %.2f s over %.1f m; 100-0 km/h %.2f s over %.1f m; terminal %.1f km/h, %d rpm, gear %d, %d wheels grounded" % [
		acceleration_time,
		acceleration_distance,
		braking_time,
		braking_distance,
		terminal_speed,
		int(terminal_rpm),
		terminal_gear,
		terminal_grounded
	])
	if not reached_100:
		printerr("FAIL: vehicle did not reach 100 km/h within 16 seconds")
		quit(1)
	elif acceleration_time < 6.5 or acceleration_time > 12.5:
		printerr("FAIL: 0-100 km/h time is outside the road-car calibration window")
		quit(1)
	elif braking_distance < 28.0 or braking_distance > 55.0:
		printerr("FAIL: 100-0 km/h braking distance is outside the road-car calibration window")
		quit(1)
	else:
		print("PASS: acceleration and braking calibration")
		quit(0)
