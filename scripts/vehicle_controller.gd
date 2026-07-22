extends RigidBody
class_name RealisticVehicleController

signal hard_impact(impact_speed)

# Golf-sized front-wheel-drive "simcade" setup.  All values use SI units.
const VEHICLE_MASS := 1320.0
const WHEEL_RADIUS := 0.320
const WHEELBASE := 2.703
const TRACK_WIDTH := 1.62
const SUSPENSION_REST_LENGTH := 0.48
const SUSPENSION_TRAVEL := 0.18
const SPRING_RATE := 33000.0
const DAMPER_RATE := 4700.0
const ANTI_ROLL_RATE_FRONT := 7200.0
const ANTI_ROLL_RATE_REAR := 5200.0
const MAX_SUSPENSION_FORCE := 10500.0
const REFERENCE_WHEEL_LOAD := VEHICLE_MASS * 9.81 * 0.25
const CORNERING_STIFFNESS := 52000.0
const ROLLING_RESISTANCE_PER_WHEEL := 48.0
const BRAKE_FORCE := 12800.0
const HANDBRAKE_FORCE := 7200.0
const FINAL_DRIVE := 3.65
const REVERSE_RATIO := 3.18
const DRIVETRAIN_EFFICIENCY := 0.88
const IDLE_RPM := 800.0
const REDLINE_RPM := 6200.0
const SHIFT_UP_RPM := 5650.0
const SHIFT_DOWN_RPM := 1650.0
const MAX_STEER_LOW_SPEED := deg2rad(34.0)
const MAX_STEER_HIGH_SPEED := deg2rad(9.0)
const STEERING_RESPONSE := 4.6
const AIR_DENSITY := 1.225
const DRAG_AREA := 0.67
const IMPACT_THRESHOLD := 7.5
const IMPACT_COOLDOWN := 0.55
const VISUAL_REFERENCE_LENGTH := 0.38

const GEAR_RATIOS := [3.77, 2.09, 1.32, 0.98, 0.78, 0.65]
const WHEEL_NAMES := ["Reifen_VL", "Reifen_VR", "Reifen_HL", "Reifen_HR"]
const WHEEL_MOUNTS := [
	Vector3(-0.806, -0.01, -1.285),
	Vector3(0.817, -0.01, -1.285),
	Vector3(-0.806, -0.01, 1.418),
	Vector3(0.817, -0.01, 1.418)
]

var driver_active := false
var operational := true
var simulation_enabled := true

var _throttle_input := 0.0
var _steering_input := 0.0
var _brake_input := 0.0
var _handbrake_input := 0.0
var _steering_state := 0.0
var _forward_speed := 0.0
var _engine_rpm := IDLE_RPM
var _gear := 1
var _shift_cooldown := 0.0
var _impact_cooldown := 0.0
var _grounded_wheels := 0
var _total_normal_load := 0.0
var _last_requested_drive_force := 0.0
var _last_longitudinal_force := 0.0
var _last_lateral_force := 0.0
var _wheel_states := []
var _wheel_spin := [0.0, 0.0, 0.0, 0.0]
var _wheel_visuals := []
var _wheel_visual_base := []
var _visual_scale := 1.0
var _pending_teleport := false
var _pending_transform := Transform.IDENTITY
var _pending_reset_motion := true


func _ready():
	mass = VEHICLE_MASS
	gravity_scale = 1.0
	linear_damp = 0.02
	angular_damp = 0.08
	continuous_cd = true
	contact_monitor = true
	contacts_reported = 12
	can_sleep = true
	_reset_wheel_states()


func _reset_wheel_states():
	_wheel_states.clear()
	for wheel_index in range(4):
		_wheel_states.append({
			"grounded": false,
			"compression": 0.0,
			"length": SUSPENSION_REST_LENGTH + SUSPENSION_TRAVEL,
			"normal_load": 0.0,
			"longitudinal_speed": 0.0,
			"lateral_speed": 0.0,
			"grip": 1.0,
			"steer_angle": 0.0,
			"contact_position": Vector3.ZERO,
			"collider": null
		})


func set_driver_active(active: bool):
	driver_active = active and operational
	if driver_active:
		set_sleeping(false)
	else:
		clear_driver_input()


func set_driver_input(throttle: float, steering: float, brake: float, handbrake: float):
	if not operational or not simulation_enabled:
		clear_driver_input()
		return
	driver_active = true
	_throttle_input = clamp(throttle, -1.0, 1.0)
	_steering_input = clamp(steering, -1.0, 1.0)
	_brake_input = clamp(brake, 0.0, 1.0)
	_handbrake_input = clamp(handbrake, 0.0, 1.0)
	set_sleeping(false)


func clear_driver_input():
	_throttle_input = 0.0
	_steering_input = 0.0
	_brake_input = 0.0
	_handbrake_input = 0.0


func set_operational(enabled: bool):
	operational = enabled
	if not operational:
		driver_active = false
		clear_driver_input()
		_engine_rpm = 0.0
	elif _engine_rpm <= 0.0:
		_engine_rpm = IDLE_RPM


func set_simulation_enabled(enabled: bool):
	simulation_enabled = enabled
	clear_driver_input()
	if enabled:
		mode = RigidBody.MODE_RIGID
		set_sleeping(false)
	else:
		mode = RigidBody.MODE_STATIC


func freeze_as_wreck():
	set_operational(false)
	simulation_enabled = false
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_forward_speed = 0.0
	_reset_wheel_states()
	mode = RigidBody.MODE_STATIC


func teleport_to(target_transform: Transform, reset_motion := true):
	global_transform = target_transform
	_pending_transform = target_transform
	_pending_teleport = true
	_pending_reset_motion = reset_motion
	if reset_motion:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_forward_speed = 0.0
		_reset_wheel_states()
	if simulation_enabled:
		set_sleeping(false)


func bind_wheel_visuals(model: Node, visual_scale := 1.0):
	_wheel_visuals.clear()
	_wheel_visual_base.clear()
	_visual_scale = max(0.001, visual_scale)
	for wheel_name in WHEEL_NAMES:
		var wheel = model.get_node_or_null(wheel_name) if model else null
		_wheel_visuals.append(wheel)
		_wheel_visual_base.append(wheel.transform if is_instance_valid(wheel) else Transform.IDENTITY)


func get_forward_speed() -> float:
	return _forward_speed


func get_speed_kph() -> float:
	return abs(_forward_speed) * 3.6


func get_engine_rpm() -> float:
	return _engine_rpm


func get_current_gear() -> int:
	return -1 if _throttle_input < -0.05 else _gear


func get_grounded_wheel_count() -> int:
	return _grounded_wheels


func get_total_normal_load() -> float:
	return _total_normal_load


func get_force_telemetry() -> Dictionary:
	return {
		"requested_drive": _last_requested_drive_force,
		"longitudinal": _last_longitudinal_force,
		"lateral_absolute": _last_lateral_force
	}


func get_wheel_states() -> Array:
	return _wheel_states.duplicate(true)


func calculate_suspension_force(compression: float, compression_velocity: float) -> float:
	if compression <= 0.0:
		return 0.0
	return clamp(compression * SPRING_RATE + compression_velocity * DAMPER_RATE, 0.0, MAX_SUSPENSION_FORCE)


func clamp_friction_circle(force: Vector2, capacity: float) -> Vector2:
	if capacity <= 0.0:
		return Vector2.ZERO
	var magnitude = force.length()
	if magnitude <= capacity or magnitude <= 0.0001:
		return force
	return force * (capacity / magnitude)


func calculate_slip_ratio(vehicle_speed: float, wheel_surface_speed: float) -> float:
	var denominator = max(max(abs(vehicle_speed), abs(wheel_surface_speed)), 0.5)
	return (wheel_surface_speed - vehicle_speed) / denominator


func _integrate_forces(state):
	if _pending_teleport:
		state.set_transform(_pending_transform)
		if _pending_reset_motion:
			state.set_linear_velocity(Vector3.ZERO)
			state.set_angular_velocity(Vector3.ZERO)
		state.set_sleep_state(false)
		_pending_teleport = false

	if not simulation_enabled or mode != RigidBody.MODE_RIGID:
		return

	var delta = state.get_step()
	var body_transform = state.get_transform()
	var basis = body_transform.basis.orthonormalized()
	var origin = body_transform.origin
	var up = basis.y.normalized()
	var chassis_forward = -basis.z.normalized()
	var chassis_velocity = state.get_linear_velocity()
	_forward_speed = chassis_velocity.dot(chassis_forward)
	_impact_cooldown = max(0.0, _impact_cooldown - delta)
	_shift_cooldown = max(0.0, _shift_cooldown - delta)

	var effective_steering = _steering_input if driver_active and operational else 0.0
	var effective_throttle = _throttle_input if driver_active and operational else 0.0
	var effective_brake = _brake_input if driver_active and operational else 0.0
	var effective_handbrake = _handbrake_input if driver_active and operational else 0.0
	if not driver_active and abs(_forward_speed) < 3.0:
		effective_brake = 0.34
		effective_handbrake = 0.22

	_steering_state = move_toward(_steering_state, effective_steering, STEERING_RESPONSE * delta)
	var speed_steer_factor = clamp(abs(_forward_speed) / 38.0, 0.0, 1.0)
	var max_steer = lerp(MAX_STEER_LOW_SPEED, MAX_STEER_HIGH_SPEED, speed_steer_factor)
	var centre_steer_angle = -_steering_state * max_steer
	var front_angles = _ackermann_angles(centre_steer_angle)

	_update_transmission(abs(_forward_speed), effective_throttle, delta)
	var total_drive_force = _calculate_drive_force(effective_throttle)
	_last_requested_drive_force = total_drive_force
	_last_longitudinal_force = 0.0
	_last_lateral_force = 0.0
	var wheel_contacts = []
	_grounded_wheels = 0

	for wheel_index in range(4):
		var local_mount = WHEEL_MOUNTS[wheel_index]
		var mount_world = body_transform.xform(local_mount)
		var ray_length = SUSPENSION_REST_LENGTH + SUSPENSION_TRAVEL + WHEEL_RADIUS
		var ray_end = mount_world - up * ray_length
		var hit = state.get_space_state().intersect_ray(
			mount_world,
			ray_end,
			[get_rid()],
			collision_mask,
			true,
			false
		)
		var contact = {
			"grounded": false,
			"mount": mount_world,
			"position": ray_end,
			"normal": up,
			"compression": 0.0,
			"length": SUSPENSION_REST_LENGTH + SUSPENSION_TRAVEL,
			"normal_load": 0.0,
			"grip": 1.0,
			"rolling_resistance": 1.0,
			"collider": null
		}
		if not hit.empty():
			var suspension_length = clamp(
				mount_world.distance_to(hit.position) - WHEEL_RADIUS,
				SUSPENSION_REST_LENGTH - SUSPENSION_TRAVEL,
				SUSPENSION_REST_LENGTH + SUSPENSION_TRAVEL
			)
			var compression = max(0.0, SUSPENSION_REST_LENGTH - suspension_length)
			var mount_velocity = chassis_velocity + state.get_angular_velocity().cross(mount_world - origin)
			var compression_velocity = -mount_velocity.dot(up)
			var normal_load = calculate_suspension_force(compression, compression_velocity)
			contact.grounded = true
			contact.position = hit.position
			contact.normal = hit.normal.normalized()
			contact.compression = compression
			contact.length = suspension_length
			contact.normal_load = normal_load
			contact.grip = _surface_value(hit.collider, "surface_grip", 0.92)
			contact.rolling_resistance = _surface_value(hit.collider, "rolling_resistance", 1.0)
			contact.collider = hit.collider
			_grounded_wheels += 1
		wheel_contacts.append(contact)

	_apply_anti_roll(wheel_contacts, 0, 1, ANTI_ROLL_RATE_FRONT)
	_apply_anti_roll(wheel_contacts, 2, 3, ANTI_ROLL_RATE_REAR)
	_total_normal_load = 0.0

	for wheel_index in range(4):
		var contact = wheel_contacts[wheel_index]
		var steer_angle = front_angles[wheel_index] if wheel_index < 2 else 0.0
		var wheel_state = _wheel_states[wheel_index]
		wheel_state.grounded = contact.grounded
		wheel_state.compression = contact.compression
		wheel_state.length = contact.length
		wheel_state.normal_load = contact.normal_load
		wheel_state.grip = contact.grip
		wheel_state.steer_angle = steer_angle
		wheel_state.contact_position = contact.position
		wheel_state.collider = contact.collider

		if not contact.grounded:
			wheel_state.longitudinal_speed = _forward_speed
			wheel_state.lateral_speed = 0.0
			continue

		var force_offset = contact.position - origin
		var suspension_direction = (up * 0.82 + contact.normal * 0.18).normalized()
		var suspension_force = suspension_direction * contact.normal_load
		state.add_force(suspension_force, force_offset)
		_total_normal_load += contact.normal_load

		var wheel_forward = chassis_forward.rotated(up, steer_angle)
		wheel_forward = wheel_forward - contact.normal * wheel_forward.dot(contact.normal)
		if wheel_forward.length_squared() < 0.0001:
			wheel_forward = chassis_forward
		wheel_forward = wheel_forward.normalized()
		var wheel_right = wheel_forward.cross(contact.normal).normalized()
		var point_velocity = chassis_velocity + state.get_angular_velocity().cross(force_offset)
		var longitudinal_speed = point_velocity.dot(wheel_forward)
		var lateral_speed = point_velocity.dot(wheel_right)
		wheel_state.longitudinal_speed = longitudinal_speed
		wheel_state.lateral_speed = lateral_speed

		var longitudinal_force = 0.0
		if wheel_index < 2:
			longitudinal_force += total_drive_force * 0.5
		var brake_share = 0.325 if wheel_index < 2 else 0.175
		longitudinal_force += _braking_force(longitudinal_speed, effective_brake * BRAKE_FORCE * brake_share)
		if wheel_index >= 2:
			longitudinal_force += _braking_force(longitudinal_speed, effective_handbrake * HANDBRAKE_FORCE * 0.5)
		longitudinal_force += _rolling_force(longitudinal_speed, contact.rolling_resistance)

		var speed_for_slip = max(abs(longitudinal_speed), 2.0)
		var slip_angle = atan2(lateral_speed, speed_for_slip)
		var load_scale = sqrt(max(contact.normal_load, 1.0) / REFERENCE_WHEEL_LOAD)
		var low_speed_factor = clamp(abs(longitudinal_speed) / 3.0, 0.22, 1.0)
		var lateral_force = -slip_angle * CORNERING_STIFFNESS * load_scale * low_speed_factor
		var tire_capacity = max(0.0, contact.grip * contact.normal_load)
		var combined_force = clamp_friction_circle(Vector2(longitudinal_force, lateral_force), tire_capacity)
		state.add_force(wheel_forward * combined_force.x + wheel_right * combined_force.y, force_offset)
		_last_longitudinal_force += combined_force.x * wheel_forward.dot(chassis_forward)
		_last_lateral_force += abs(combined_force.y)

	_apply_aerodynamics(state, chassis_velocity, up)
	_detect_hard_impact(state)


func _ackermann_angles(centre_angle: float) -> Array:
	if abs(centre_angle) < 0.0001:
		return [0.0, 0.0]
	var direction = sign(centre_angle)
	var radius = WHEELBASE / max(tan(abs(centre_angle)), 0.001)
	var inner_angle = atan(WHEELBASE / max(0.1, radius - TRACK_WIDTH * 0.5)) * direction
	var outer_angle = atan(WHEELBASE / (radius + TRACK_WIDTH * 0.5)) * direction
	return [inner_angle, outer_angle] if direction > 0.0 else [outer_angle, inner_angle]


func _apply_anti_roll(contacts: Array, left_index: int, right_index: int, rate: float):
	var left = contacts[left_index]
	var right = contacts[right_index]
	if not left.grounded and not right.grounded:
		return
	var difference = left.compression - right.compression
	var anti_roll_force = difference * rate
	if left.grounded:
		left.normal_load = clamp(left.normal_load + anti_roll_force, 0.0, MAX_SUSPENSION_FORCE)
	if right.grounded:
		right.normal_load = clamp(right.normal_load - anti_roll_force, 0.0, MAX_SUSPENSION_FORCE)
	contacts[left_index] = left
	contacts[right_index] = right


func _surface_value(collider, metadata_name: String, fallback: float) -> float:
	if is_instance_valid(collider) and collider.has_meta(metadata_name):
		return float(collider.get_meta(metadata_name))
	return fallback


func _braking_force(longitudinal_speed: float, requested_force: float) -> float:
	if requested_force <= 0.0:
		return 0.0
	if abs(longitudinal_speed) > 0.18:
		return -sign(longitudinal_speed) * requested_force
	return clamp(-longitudinal_speed * 6500.0, -requested_force, requested_force)


func _rolling_force(longitudinal_speed: float, surface_multiplier: float) -> float:
	var resistance = ROLLING_RESISTANCE_PER_WHEEL * max(0.1, surface_multiplier)
	if abs(longitudinal_speed) > 0.12:
		return -sign(longitudinal_speed) * resistance
	return clamp(-longitudinal_speed * 420.0, -resistance, resistance)


func _update_transmission(speed: float, throttle: float, delta: float):
	if not operational:
		_engine_rpm = 0.0
		return
	if throttle < -0.05:
		var reverse_wheel_rpm = speed / WHEEL_RADIUS * 60.0 / TAU
		_engine_rpm = clamp(max(IDLE_RPM, reverse_wheel_rpm * REVERSE_RATIO * FINAL_DRIVE), IDLE_RPM, REDLINE_RPM)
		return
	var ratio = float(GEAR_RATIOS[_gear - 1])
	var wheel_rpm = speed / WHEEL_RADIUS * 60.0 / TAU
	var coupled_rpm = wheel_rpm * ratio * FINAL_DRIVE
	var launch_rpm = IDLE_RPM + max(0.0, throttle) * 1450.0 * clamp(1.0 - speed / 4.0, 0.0, 1.0)
	_engine_rpm = clamp(max(coupled_rpm, launch_rpm), IDLE_RPM, REDLINE_RPM)
	if _shift_cooldown <= 0.0 and _engine_rpm >= SHIFT_UP_RPM and _gear < GEAR_RATIOS.size():
		_gear += 1
		_shift_cooldown = 0.22
	elif _shift_cooldown <= 0.0 and _engine_rpm <= SHIFT_DOWN_RPM and _gear > 1:
		_gear -= 1
		_shift_cooldown = 0.18


func _calculate_drive_force(throttle: float) -> float:
	if abs(throttle) < 0.01 or not operational:
		return 0.0
	var ratio = REVERSE_RATIO if throttle < 0.0 else float(GEAR_RATIOS[_gear - 1])
	var engine_torque = _engine_torque(_engine_rpm) * abs(throttle)
	var wheel_torque = engine_torque * ratio * FINAL_DRIVE * DRIVETRAIN_EFFICIENCY
	return sign(throttle) * wheel_torque / WHEEL_RADIUS


func _engine_torque(rpm: float) -> float:
	if rpm < 1500.0:
		return lerp(125.0, 240.0, clamp((rpm - IDLE_RPM) / 700.0, 0.0, 1.0))
	if rpm < 3500.0:
		return lerp(240.0, 250.0, (rpm - 1500.0) / 2000.0)
	if rpm < 5000.0:
		return lerp(250.0, 218.0, (rpm - 3500.0) / 1500.0)
	return lerp(218.0, 155.0, clamp((rpm - 5000.0) / 1200.0, 0.0, 1.0))


func _apply_aerodynamics(state, velocity: Vector3, up: Vector3):
	var speed = velocity.length()
	if speed > 0.05:
		var drag = -velocity.normalized() * 0.5 * AIR_DENSITY * DRAG_AREA * speed * speed
		state.add_central_force(drag)
	var horizontal_speed = Vector3(velocity.x, 0.0, velocity.z).length()
	if _grounded_wheels >= 2 and horizontal_speed > 5.0:
		state.add_central_force(-up * min(900.0, horizontal_speed * horizontal_speed * 0.18))


func _detect_hard_impact(state):
	if _impact_cooldown > 0.0:
		return
	var strongest_delta_v = 0.0
	for contact_index in range(state.get_contact_count()):
		# Godot 3 exposes the contact impulse as a scalar magnitude.  Godot 4
		# returns a Vector3 here, so keeping this explicitly scalar also prevents
		# chassis/ground contacts from aborting the custom integrator.
		var impulse_magnitude = abs(float(state.get_contact_impulse(contact_index)))
		strongest_delta_v = max(strongest_delta_v, impulse_magnitude / VEHICLE_MASS)
	if strongest_delta_v >= IMPACT_THRESHOLD:
		_impact_cooldown = IMPACT_COOLDOWN
		emit_signal("hard_impact", strongest_delta_v)


func _physics_process(delta):
	if not simulation_enabled or _wheel_visuals.size() != 4 or _wheel_states.size() != 4:
		return
	for wheel_index in range(4):
		var wheel = _wheel_visuals[wheel_index]
		if not is_instance_valid(wheel):
			continue
		var wheel_state = _wheel_states[wheel_index]
		var wheel_speed = wheel_state.longitudinal_speed
		_wheel_spin[wheel_index] = fmod(_wheel_spin[wheel_index] - wheel_speed / WHEEL_RADIUS * delta, TAU)
		var base_transform = _wheel_visual_base[wheel_index]
		var visual_transform = base_transform
		var suspension_offset = (VISUAL_REFERENCE_LENGTH - float(wheel_state.length)) / _visual_scale
		visual_transform.origin = base_transform.origin + Vector3.UP * suspension_offset
		visual_transform.basis = base_transform.basis.rotated(Vector3.UP, float(wheel_state.steer_angle))
		visual_transform.basis = visual_transform.basis.rotated(Vector3.RIGHT, float(_wheel_spin[wheel_index]))
		wheel.transform = visual_transform
