extends RigidBody
class_name RealisticHelicopterController

signal rotor_destroyed(reason)
signal hard_impact(impact_speed)
signal fatal_crash(impact_speed)

# EC135/H135-class "simulator-light" setup. Godot units are treated as metres
# and all forces use SI units.
const HELICOPTER_MASS := 2600.0
const GRAVITY_ACCELERATION := 9.81
const AIR_DENSITY := 1.225
const MAIN_ROTOR_RADIUS := 5.20
const MAIN_ROTOR_AREA := PI * MAIN_ROTOR_RADIUS * MAIN_ROTOR_RADIUS
const NOMINAL_ROTOR_RPM := 395.0
const MAX_MAIN_ROTOR_THRUST := HELICOPTER_MASS * GRAVITY_ACCELERATION * 1.55
const PROFILE_POWER_WATTS := 75000.0
const ROTOR_TORQUE_SIGN := 1.0

const MIN_COLLECTIVE := 0.12
const MAX_COLLECTIVE := 1.0
const DEFAULT_COLLECTIVE := 0.16
const COLLECTIVE_CHANGE_RATE := 0.35
const CYCLIC_RESPONSE_TIME := 0.12
const PEDAL_RESPONSE_TIME := 0.10
const MAX_CYCLIC_PITCH := deg2rad(10.0)
const MAX_CYCLIC_ROLL := deg2rad(9.0)
const MAX_PEDAL_TORQUE := 7800.0

const ROTOR_SPOOL_UP_TIME := 2.50
const ROTOR_SPOOL_DOWN_TIME := 5.00
const ROTOR_FAILURE_SPOOL_DOWN_TIME := 2.80
const ROTOR_DAMAGE_RPM_RATIO := 0.35
const ROTOR_HUB_LOCAL := Vector3(0.0, 1.55, -0.15)
const TAIL_ROTOR_HUB_LOCAL := Vector3(0.11, 0.68, 5.85)

# Effective CdA values in body-local right/up/back axes. Forward is -Z.
const DRAG_AREA_RIGHT := 3.80
const DRAG_AREA_VERTICAL := 5.00
const DRAG_AREA_FORWARD := 1.45
const ANGULAR_DAMP_PITCH := 8500.0
const ANGULAR_DAMP_YAW := 3500.0
const ANGULAR_DAMP_ROLL := 7500.0
const SAS_LEVEL_TORQUE := 14000.0

const GROUND_EFFECT_MAX := 1.22
const GROUND_EFFECT_RAY_LENGTH := MAIN_ROTOR_RADIUS * 1.50
const TRANSLATIONAL_LIFT_GAIN := 0.12
const VORTEX_RING_MAX_LOSS := 0.35
const HIGH_SPEED_MAX_LOSS := 0.25

const HARD_IMPACT_THRESHOLD := 7.5
const FATAL_CRASH_THRESHOLD := 4.5
const IMPACT_COOLDOWN := 0.55
const FATAL_CRASH_ARM_DELAY := 0.25

const MAIN_ANIMATION_RPM := 240.0
const FRAGMENT_LIFETIME := 7.0

var driver_active := false
var operational := true
var engine_enabled := false
var simulation_enabled := true

var _cyclic_pitch_input := 0.0
var _cyclic_roll_input := 0.0
var _yaw_input := 0.0
var _collective_change_input := 0.0
var _cyclic_pitch_state := 0.0
var _cyclic_roll_state := 0.0
var _yaw_state := 0.0
var _collective := DEFAULT_COLLECTIVE
var _rotor_rpm_ratio := 0.0

var _rotor_failed := false
var _rotor_failure_reason := ""
var _failure_elapsed := 0.0
var _fatal_crash_emitted := false
var _pending_failure_impact_speed := 0.0
var _impact_cooldown := 0.0
var _last_airborne_velocity := Vector3.ZERO

var _last_thrust := 0.0
var _last_ground_effect := 1.0
var _last_translational_lift := 1.0
var _last_vortex_ring_factor := 1.0
var _last_high_speed_factor := 1.0
var _last_planar_airspeed := 0.0

var _main_rotor_area: Area
var _tail_rotor_area: Area
var _rotor_visuals := []
var _animation_player: AnimationPlayer
var _visual_failure_finalized := false
var _fragments_spawned := false

var _pending_teleport := false
var _pending_transform := Transform.IDENTITY
var _pending_reset_motion := true


func _ready():
	mass = HELICOPTER_MASS
	gravity_scale = 1.0
	linear_damp = 0.02
	angular_damp = 0.03
	continuous_cd = true
	contact_monitor = true
	contacts_reported = 24
	can_sleep = true

	_main_rotor_area = get_node_or_null("MainRotorArea")
	_tail_rotor_area = get_node_or_null("TailRotorArea")
	if is_instance_valid(_main_rotor_area):
		_main_rotor_area.connect("body_entered", self, "_on_rotor_body_entered", ["main"])
	if is_instance_valid(_tail_rotor_area):
		_tail_rotor_area.connect("body_entered", self, "_on_rotor_body_entered", ["tail"])


func set_driver_active(active: bool):
	driver_active = active and operational and simulation_enabled and not _rotor_failed
	if driver_active:
		set_sleeping(false)
	else:
		clear_driver_input()


func set_driver_input(cyclic_pitch: float, cyclic_roll: float, yaw: float, collective_change := 0.0):
	if not operational or not simulation_enabled or _rotor_failed:
		clear_driver_input()
		return
	driver_active = true
	_cyclic_pitch_input = clamp(cyclic_pitch, -1.0, 1.0)
	_cyclic_roll_input = clamp(cyclic_roll, -1.0, 1.0)
	_yaw_input = clamp(yaw, -1.0, 1.0)
	_collective_change_input = clamp(collective_change, -1.0, 1.0)
	set_sleeping(false)


func clear_driver_input():
	_cyclic_pitch_input = 0.0
	_cyclic_roll_input = 0.0
	_yaw_input = 0.0
	_collective_change_input = 0.0


func set_engine_enabled(enabled: bool):
	engine_enabled = enabled and operational and simulation_enabled and not _rotor_failed
	if operational:
		set_sleeping(false)


func set_simulation_enabled(enabled: bool):
	simulation_enabled = enabled
	clear_driver_input()
	if enabled:
		mode = RigidBody.MODE_RIGID
		if operational:
			set_sleeping(false)
	else:
		driver_active = false
		engine_enabled = false
		mode = RigidBody.MODE_STATIC


func set_collective(value: float):
	_collective = clamp(value, MIN_COLLECTIVE, MAX_COLLECTIVE)
	if operational:
		set_sleeping(false)


func get_collective() -> float:
	return _collective


func get_rotor_rpm() -> float:
	return _rotor_rpm_ratio * NOMINAL_ROTOR_RPM


func get_rotor_rpm_ratio() -> float:
	return _rotor_rpm_ratio


func get_forward_speed() -> float:
	return linear_velocity.dot(-global_transform.basis.z.normalized())


func get_speed_kph() -> float:
	return linear_velocity.length() * 3.6


func get_vertical_speed() -> float:
	return linear_velocity.y


func is_rotor_operational() -> bool:
	return operational and not _rotor_failed


func is_rotor_failed() -> bool:
	return _rotor_failed


func is_crash_armed() -> bool:
	return _rotor_failed and not _fatal_crash_emitted


func get_rotor_failure_reason() -> String:
	return _rotor_failure_reason


func get_force_telemetry() -> Dictionary:
	return {
		"thrust": _last_thrust,
		"ground_effect": _last_ground_effect,
		"translational_lift": _last_translational_lift,
		"vortex_ring": _last_vortex_ring_factor,
		"high_speed": _last_high_speed_factor,
		"planar_airspeed": _last_planar_airspeed
	}


func teleport_to(target_transform: Transform, reset_motion := true):
	global_transform = target_transform
	_pending_transform = target_transform
	_pending_teleport = true
	_pending_reset_motion = reset_motion
	if reset_motion:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_last_airborne_velocity = Vector3.ZERO
	if simulation_enabled and mode == RigidBody.MODE_RIGID:
		set_sleeping(false)


func freeze_as_wreck():
	operational = false
	simulation_enabled = false
	engine_enabled = false
	driver_active = false
	clear_driver_input()
	_fatal_crash_emitted = true
	_last_thrust = 0.0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	mode = RigidBody.MODE_STATIC


func bind_visuals(model: Node):
	_rotor_visuals.clear()
	_animation_player = null
	if not is_instance_valid(model):
		return
	for rotor_name in ["Object_9", "Object_7"]:
		var rotor_visual = model.find_node(rotor_name, true, false)
		if is_instance_valid(rotor_visual):
			_rotor_visuals.append(rotor_visual)
	_animation_player = _find_animation_player(model)
	if is_instance_valid(_animation_player) and _animation_player.has_animation("Take 001"):
		_animation_player.play("Take 001")
		_animation_player.playback_speed = 0.0
	if _rotor_failed:
		_hide_rotor_visuals()


func trigger_rotor_failure(reason := "damage"):
	_trigger_rotor_failure(str(reason))


func calculate_rotor_spool(current_ratio: float, target_ratio: float, delta: float, response_time: float) -> float:
	if delta <= 0.0:
		return clamp(current_ratio, 0.0, 1.05)
	var safe_response_time = max(response_time, 0.001)
	var response = 1.0 - exp(-delta / safe_response_time)
	return clamp(current_ratio + (target_ratio - current_ratio) * response, 0.0, 1.05)


func calculate_ground_effect_factor(height: float) -> float:
	if height >= GROUND_EFFECT_RAY_LENGTH:
		return 1.0
	var safe_height = max(height, MAIN_ROTOR_RADIUS * 0.28)
	var ratio = MAIN_ROTOR_RADIUS / (4.0 * safe_height)
	var denominator = max(0.05, 1.0 - ratio * ratio)
	var raw_factor = clamp(1.0 / denominator, 1.0, GROUND_EFFECT_MAX)
	var fade = 1.0 - smoothstep_unit(
		(height - MAIN_ROTOR_RADIUS) / max(0.001, GROUND_EFFECT_RAY_LENGTH - MAIN_ROTOR_RADIUS)
	)
	return lerp(1.0, raw_factor, fade)


func calculate_translational_lift_factor(planar_speed: float) -> float:
	return 1.0 + TRANSLATIONAL_LIFT_GAIN * smooth_range(5.0, 15.0, max(0.0, planar_speed))


func calculate_vortex_ring_factor(descent_speed: float, planar_speed: float, collective: float) -> float:
	var descent_strength = smooth_range(5.0, 11.0, max(0.0, descent_speed))
	var translation_recovery = smooth_range(6.0, 14.0, max(0.0, planar_speed))
	var collective_strength = smooth_range(0.40, 0.75, collective)
	var vortex_strength = descent_strength * (1.0 - translation_recovery) * collective_strength
	return 1.0 - VORTEX_RING_MAX_LOSS * clamp(vortex_strength, 0.0, 1.0)


func calculate_high_speed_factor(planar_speed: float) -> float:
	return 1.0 - HIGH_SPEED_MAX_LOSS * smooth_range(60.0, 78.0, max(0.0, planar_speed))


func calculate_anisotropic_drag(local_velocity: Vector3) -> Vector3:
	var coefficient = -0.5 * AIR_DENSITY
	return Vector3(
		coefficient * DRAG_AREA_RIGHT * local_velocity.x * abs(local_velocity.x),
		coefficient * DRAG_AREA_VERTICAL * local_velocity.y * abs(local_velocity.y),
		coefficient * DRAG_AREA_FORWARD * local_velocity.z * abs(local_velocity.z)
	)


func calculate_disk_normal_local(cyclic_pitch: float, cyclic_roll: float) -> Vector3:
	var pitch_angle = clamp(cyclic_pitch, -1.0, 1.0) * MAX_CYCLIC_PITCH
	var roll_angle = clamp(cyclic_roll, -1.0, 1.0) * MAX_CYCLIC_ROLL
	return Vector3(tan(roll_angle), 1.0, -tan(pitch_angle)).normalized()


func calculate_main_rotor_thrust(
		collective: float,
		rotor_ratio: float,
		ground_effect: float,
		translational_lift: float,
		vortex_ring_factor: float,
		high_speed_factor: float,
		efficiency := 1.0
	) -> float:
	return max(0.0,
		MAX_MAIN_ROTOR_THRUST
		* clamp(collective, 0.0, MAX_COLLECTIVE)
		* pow(clamp(rotor_ratio, 0.0, 1.05), 2.0)
		* max(0.0, ground_effect)
		* max(0.0, translational_lift)
		* clamp(vortex_ring_factor, 0.0, 1.0)
		* clamp(high_speed_factor, 0.0, 1.0)
		* clamp(efficiency, 0.0, 1.0)
	)


func calculate_main_rotor_reaction_torque(thrust: float, rotor_ratio: float) -> float:
	if rotor_ratio <= 0.001:
		return 0.0
	var induced_power = pow(max(0.0, thrust), 1.5) / sqrt(2.0 * AIR_DENSITY * MAIN_ROTOR_AREA)
	var profile_power = PROFILE_POWER_WATTS * pow(clamp(rotor_ratio, 0.0, 1.05), 3.0)
	var rotor_omega = max(rotor_ratio * NOMINAL_ROTOR_RPM * TAU / 60.0, 10.0)
	return (induced_power + profile_power) / rotor_omega


func calculate_yaw_control_torque(yaw_input: float, rotor_ratio: float) -> float:
	# Godot's positive rotation around +Y turns a -Z-facing aircraft left.
	# Therefore positive "yaw right" input must apply negative body-up torque.
	return (
		-clamp(yaw_input, -1.0, 1.0)
		* MAX_PEDAL_TORQUE
		* pow(clamp(rotor_ratio, 0.0, 1.05), 2.0)
	)


func smooth_range(from: float, to: float, value: float) -> float:
	if to <= from:
		return 1.0 if value >= to else 0.0
	return smoothstep_unit((value - from) / (to - from))


func smoothstep_unit(value: float) -> float:
	var bounded = clamp(value, 0.0, 1.0)
	return bounded * bounded * (3.0 - 2.0 * bounded)


func _integrate_forces(state):
	if _pending_teleport:
		state.set_transform(_pending_transform)
		if _pending_reset_motion:
			state.set_linear_velocity(Vector3.ZERO)
			state.set_angular_velocity(Vector3.ZERO)
			state.set_sleep_state(false)
		_pending_teleport = false

	if not operational or not simulation_enabled or mode != RigidBody.MODE_RIGID:
		return

	var delta = state.get_step()
	_update_control_states(delta)
	_update_rotor_state(delta)
	_impact_cooldown = max(0.0, _impact_cooldown - delta)
	if _rotor_failed:
		_failure_elapsed += delta

	var body_transform = state.get_transform()
	var basis = body_transform.basis.orthonormalized()
	var velocity = state.get_linear_velocity()
	var disk_normal_local = calculate_disk_normal_local(_cyclic_pitch_state, _cyclic_roll_state)
	var disk_normal = basis.xform(disk_normal_local).normalized()
	var rotor_hub_world = body_transform.origin + basis.xform(ROTOR_HUB_LOCAL)

	var axial_airspeed = velocity.dot(disk_normal)
	var planar_velocity = velocity - disk_normal * axial_airspeed
	_last_planar_airspeed = planar_velocity.length()
	_last_ground_effect = _sample_ground_effect(state, body_transform, basis, disk_normal)
	_last_translational_lift = calculate_translational_lift_factor(_last_planar_airspeed)
	_last_vortex_ring_factor = calculate_vortex_ring_factor(
		max(0.0, -axial_airspeed),
		_last_planar_airspeed,
		_collective
	)
	_last_high_speed_factor = calculate_high_speed_factor(_last_planar_airspeed)

	var rotor_efficiency = 0.0 if _rotor_failed else 1.0
	_last_thrust = calculate_main_rotor_thrust(
		_collective,
		_rotor_rpm_ratio,
		_last_ground_effect,
		_last_translational_lift,
		_last_vortex_ring_factor,
		_last_high_speed_factor,
		rotor_efficiency
	)
	if _last_thrust > 0.0:
		state.add_force(disk_normal * _last_thrust, rotor_hub_world - body_transform.origin)

	_apply_rotor_torque(state, basis, _last_thrust)
	_apply_aerodynamics(state, basis, velocity)
	_apply_stability_augmentation(state, basis)
	if _rotor_failed:
		_apply_failure_imbalance(state, basis)
	_detect_impacts(state)


func _physics_process(_delta):
	var keep_awake = (
		engine_enabled
		or _rotor_rpm_ratio > 0.01
		or (_rotor_failed and not _fatal_crash_emitted)
	)
	can_sleep = not keep_awake
	if keep_awake and sleeping:
		set_sleeping(false)
	if is_instance_valid(_animation_player) and not _rotor_failed:
		if _animation_player.has_animation("Take 001") and not _animation_player.is_playing():
			_animation_player.play("Take 001")
		_animation_player.playback_speed = _rotor_rpm_ratio * NOMINAL_ROTOR_RPM / MAIN_ANIMATION_RPM
	if not _rotor_failed and _rotor_rpm_ratio >= ROTOR_DAMAGE_RPM_RATIO:
		_check_existing_rotor_overlaps()


func _update_control_states(delta: float):
	var effective_pitch = _cyclic_pitch_input if driver_active and not _rotor_failed else 0.0
	var effective_roll = _cyclic_roll_input if driver_active and not _rotor_failed else 0.0
	var effective_yaw = _yaw_input if driver_active and not _rotor_failed else 0.0
	var effective_collective_change = _collective_change_input if driver_active and not _rotor_failed else 0.0
	_collective = clamp(
		_collective + effective_collective_change * COLLECTIVE_CHANGE_RATE * delta,
		MIN_COLLECTIVE,
		MAX_COLLECTIVE
	)
	_cyclic_pitch_state = _exponential_approach(
		_cyclic_pitch_state,
		effective_pitch,
		delta,
		CYCLIC_RESPONSE_TIME
	)
	_cyclic_roll_state = _exponential_approach(
		_cyclic_roll_state,
		effective_roll,
		delta,
		CYCLIC_RESPONSE_TIME
	)
	_yaw_state = _exponential_approach(_yaw_state, effective_yaw, delta, PEDAL_RESPONSE_TIME)


func _update_rotor_state(delta: float):
	var target_ratio = 0.0
	if engine_enabled and not _rotor_failed:
		var load_droop = 0.035 * smooth_range(0.65, 1.0, _collective)
		target_ratio = 1.0 - load_droop
	var response_time = ROTOR_SPOOL_UP_TIME if target_ratio > _rotor_rpm_ratio else ROTOR_SPOOL_DOWN_TIME
	if _rotor_failed:
		response_time = ROTOR_FAILURE_SPOOL_DOWN_TIME
	_rotor_rpm_ratio = calculate_rotor_spool(
		_rotor_rpm_ratio,
		target_ratio,
		delta,
		response_time
	)


func _exponential_approach(current: float, target: float, delta: float, response_time: float) -> float:
	var response = 1.0 - exp(-max(0.0, delta) / max(0.001, response_time))
	return lerp(current, target, response)


func _sample_ground_effect(state, body_transform: Transform, basis: Basis, disk_normal: Vector3) -> float:
	if _rotor_failed or _rotor_rpm_ratio < 0.05 or disk_normal.dot(Vector3.UP) < 0.35:
		return 1.0
	var hub = body_transform.origin + basis.xform(ROTOR_HUB_LOCAL)
	var sample_radius = MAIN_ROTOR_RADIUS * 0.45
	var forward = -basis.z.normalized()
	var right = basis.x.normalized()
	var offsets = [
		Vector2.ZERO,
		Vector2(sample_radius, 0.0),
		Vector2(-sample_radius, 0.0),
		Vector2(0.0, sample_radius),
		Vector2(0.0, -sample_radius)
	]
	var factor_sum = 0.0
	var hit_count = 0
	for offset in offsets:
		var ray_start = hub + right * offset.x + forward * offset.y
		var ray_end = ray_start - disk_normal * GROUND_EFFECT_RAY_LENGTH
		var hit = state.get_space_state().intersect_ray(
			ray_start,
			ray_end,
			[get_rid()],
			collision_mask,
			true,
			false
		)
		if hit.empty():
			continue
		var surface_normal = hit.normal.normalized()
		if surface_normal.dot(disk_normal) < 0.55:
			continue
		factor_sum += calculate_ground_effect_factor(ray_start.distance_to(hit.position))
		hit_count += 1
	if hit_count <= 0:
		return 1.0
	var coverage = float(hit_count) / float(offsets.size())
	return lerp(1.0, factor_sum / float(hit_count), coverage)


func _apply_rotor_torque(state, basis: Basis, thrust: float):
	var body_up = basis.y.normalized()
	var reaction_torque = calculate_main_rotor_reaction_torque(thrust, _rotor_rpm_ratio)
	if reaction_torque <= 0.0:
		return
	state.add_torque(-body_up * reaction_torque * ROTOR_TORQUE_SIGN)
	if not _rotor_failed:
		var anti_torque = reaction_torque + calculate_yaw_control_torque(_yaw_state, _rotor_rpm_ratio)
		state.add_torque(body_up * anti_torque * ROTOR_TORQUE_SIGN)


func _apply_aerodynamics(state, basis: Basis, velocity: Vector3):
	var local_velocity = basis.xform_inv(velocity)
	var local_drag = calculate_anisotropic_drag(local_velocity)
	state.add_central_force(basis.xform(local_drag))


func _apply_stability_augmentation(state, basis: Basis):
	var local_angular_velocity = basis.xform_inv(state.get_angular_velocity())
	var damping_scale = 0.22
	if not _rotor_failed:
		damping_scale += 0.78 * pow(_rotor_rpm_ratio, 2.0)
	var local_damping = Vector3(
		-local_angular_velocity.x * ANGULAR_DAMP_PITCH * damping_scale,
		-local_angular_velocity.y * ANGULAR_DAMP_YAW * damping_scale,
		-local_angular_velocity.z * ANGULAR_DAMP_ROLL * damping_scale
	)
	state.add_torque(basis.xform(local_damping))
	if _rotor_failed or _rotor_rpm_ratio < 0.10:
		return
	var centered_input = 1.0 - max(abs(_cyclic_pitch_state), abs(_cyclic_roll_state))
	var assist_scale = clamp(centered_input, 0.0, 1.0) * pow(_rotor_rpm_ratio, 2.0)
	var level_axis = basis.y.normalized().cross(Vector3.UP)
	state.add_torque(level_axis * SAS_LEVEL_TORQUE * assist_scale)


func _apply_failure_imbalance(state, basis: Basis):
	var imbalance_scale = pow(_rotor_rpm_ratio, 2.0)
	if imbalance_scale <= 0.001:
		return
	var local_imbalance = Vector3(
		sin(_failure_elapsed * 7.3) * 3800.0,
		0.0,
		cos(_failure_elapsed * 6.1) * 3200.0
	) * imbalance_scale
	state.add_torque(basis.xform(local_imbalance))


func _detect_impacts(state):
	var contact_count = state.get_contact_count()
	var strongest_delta_v = 0.0
	for contact_index in range(contact_count):
		var impulse_magnitude = abs(float(state.get_contact_impulse(contact_index)))
		strongest_delta_v = max(strongest_delta_v, impulse_magnitude / HELICOPTER_MASS)

	var impact_speed = 0.0
	if contact_count <= 0:
		_last_airborne_velocity = state.get_linear_velocity()
	else:
		# Consume the last free-flight velocity on the first contact step. Keeping
		# it while resting would repeat the same landing every cooldown interval.
		impact_speed = max(strongest_delta_v, _last_airborne_velocity.length())
		_last_airborne_velocity = Vector3.ZERO
		if impact_speed >= HARD_IMPACT_THRESHOLD and _impact_cooldown <= 0.0:
			_impact_cooldown = IMPACT_COOLDOWN
			emit_signal("hard_impact", impact_speed)

	if _rotor_failed and impact_speed >= FATAL_CRASH_THRESHOLD:
		# A very low-altitude failure can hit before the short arming delay
		# expires. Latch that real impact so it is not lost while resting.
		_pending_failure_impact_speed = max(_pending_failure_impact_speed, impact_speed)

	if (
		_rotor_failed
		and not _fatal_crash_emitted
		and _failure_elapsed >= FATAL_CRASH_ARM_DELAY
		and _pending_failure_impact_speed >= FATAL_CRASH_THRESHOLD
	):
		_fatal_crash_emitted = true
		emit_signal("fatal_crash", _pending_failure_impact_speed)


func _on_rotor_body_entered(body: Node, rotor_name: String):
	if not is_instance_valid(body) or body == self or _rotor_failed:
		return
	if _rotor_rpm_ratio < ROTOR_DAMAGE_RPM_RATIO:
		return
	_trigger_rotor_failure("%s_rotor_contact:%s" % [rotor_name, body.name])


func _check_existing_rotor_overlaps():
	for area_data in [
		{"area": _main_rotor_area, "name": "main"},
		{"area": _tail_rotor_area, "name": "tail"}
	]:
		var rotor_area = area_data.area
		if not is_instance_valid(rotor_area):
			continue
		for body in rotor_area.get_overlapping_bodies():
			if is_instance_valid(body) and body != self:
				_trigger_rotor_failure("%s_rotor_contact:%s" % [area_data.name, body.name])
				return


func _trigger_rotor_failure(reason: String):
	if _rotor_failed or not operational:
		return
	_rotor_failed = true
	_rotor_failure_reason = reason
	engine_enabled = false
	driver_active = false
	clear_driver_input()
	_failure_elapsed = 0.0
	_pending_failure_impact_speed = 0.0
	_last_thrust = 0.0
	set_sleeping(false)
	emit_signal("rotor_destroyed", reason)
	call_deferred("_finalize_rotor_failure")


func _finalize_rotor_failure():
	if _visual_failure_finalized:
		return
	_visual_failure_finalized = true
	for rotor_area in [_main_rotor_area, _tail_rotor_area]:
		if not is_instance_valid(rotor_area):
			continue
		rotor_area.set_deferred("monitoring", false)
		var rotor_shape = rotor_area.get_node_or_null("CollisionShape")
		if is_instance_valid(rotor_shape):
			rotor_shape.set_deferred("disabled", true)
	if is_instance_valid(_animation_player):
		_animation_player.stop(false)
	_hide_rotor_visuals()
	_spawn_rotor_fragments()


func _hide_rotor_visuals():
	for rotor_visual in _rotor_visuals:
		if is_instance_valid(rotor_visual) and rotor_visual is Spatial:
			rotor_visual.visible = false


func _find_animation_player(node: Node):
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found = _find_animation_player(child)
		if is_instance_valid(found):
			return found
	return null


func _spawn_rotor_fragments():
	if _fragments_spawned or not is_inside_tree() or not is_instance_valid(get_parent()):
		return
	_fragments_spawned = true
	var body_basis = global_transform.basis.orthonormalized()
	var body_origin = global_transform.origin
	var body_linear_velocity = linear_velocity
	var body_angular_velocity = angular_velocity

	for fragment_index in range(4):
		var angle = float(fragment_index) * TAU / 4.0
		var local_radial = Vector3(cos(angle), 0.0, sin(angle))
		var world_radial = body_basis.xform(local_radial).normalized()
		var fragment_basis = body_basis * Basis(Vector3.UP, angle)
		var fragment_origin = body_origin + body_basis.xform(ROTOR_HUB_LOCAL + local_radial * 1.55)
		var offset = fragment_origin - body_origin
		var fragment_velocity = (
			body_linear_velocity
			+ body_angular_velocity.cross(offset)
			+ world_radial * 5.5
			+ Vector3.UP * (1.2 + float(fragment_index) * 0.25)
		)
		_create_rotor_fragment(
			"MainRotorFragment%d" % fragment_index,
			Transform(fragment_basis, fragment_origin),
			Vector3(2.30, 0.07, 0.17),
			fragment_velocity,
			body_angular_velocity + world_radial * (4.0 + float(fragment_index))
		)

	for fragment_index in range(3):
		var angle = float(fragment_index) * TAU / 3.0
		var local_radial = Vector3(0.0, cos(angle), sin(angle))
		var world_radial = body_basis.xform(local_radial).normalized()
		var fragment_basis = body_basis * Basis(Vector3.RIGHT, angle)
		var fragment_origin = body_origin + body_basis.xform(TAIL_ROTOR_HUB_LOCAL + local_radial * 0.28)
		var offset = fragment_origin - body_origin
		var fragment_velocity = (
			body_linear_velocity
			+ body_angular_velocity.cross(offset)
			+ world_radial * 3.5
			+ Vector3.UP * 0.6
		)
		_create_rotor_fragment(
			"TailRotorFragment%d" % fragment_index,
			Transform(fragment_basis, fragment_origin),
			Vector3(0.12, 0.72, 0.09),
			fragment_velocity,
			body_angular_velocity + world_radial * (5.0 + float(fragment_index))
		)


func _create_rotor_fragment(
		fragment_name: String,
		fragment_transform: Transform,
		fragment_size: Vector3,
		fragment_velocity: Vector3,
		fragment_angular_velocity: Vector3
	):
	var fragment = RigidBody.new()
	fragment.name = fragment_name
	fragment.mass = 7.0
	fragment.continuous_cd = true
	fragment.linear_damp = 0.08
	fragment.angular_damp = 0.04
	get_parent().add_child(fragment)
	fragment.global_transform = fragment_transform
	# Fragments are spawned directly around their former hubs. Excluding the
	# parent airframe prevents an overlap with the tail boom/fuselage from being
	# mistaken for the later ground impact that should trigger fatal_crash.
	fragment.add_collision_exception_with(self)
	add_collision_exception_with(fragment)

	var mesh_instance = MeshInstance.new()
	var fragment_mesh = CubeMesh.new()
	fragment_mesh.size = fragment_size
	var fragment_material = SpatialMaterial.new()
	fragment_material.albedo_color = Color("34383a")
	fragment_material.roughness = 0.62
	fragment_material.metallic = 0.28
	fragment_mesh.material = fragment_material
	mesh_instance.mesh = fragment_mesh
	fragment.add_child(mesh_instance)

	var collision = CollisionShape.new()
	var fragment_shape = BoxShape.new()
	fragment_shape.extents = fragment_size * 0.5
	collision.shape = fragment_shape
	fragment.add_child(collision)
	fragment.linear_velocity = fragment_velocity
	fragment.angular_velocity = fragment_angular_velocity
	get_tree().create_timer(FRAGMENT_LIFETIME).connect("timeout", fragment, "queue_free")
