extends SceneTree

const MAIN_SCENE = preload("res://main.tscn")

var failures = []


func _init():
	call_deferred("_run")


func _run():
	var main = MAIN_SCENE.instance()
	get_root().add_child(main)
	# Let _ready(), deferred ground placement, and the physics server finish once.
	yield(self, "idle_frame")
	yield(self, "physics_frame")
	main.set_physics_process(false)
	main.set_process(false)
	_expect(is_instance_valid(main.player_collider), "main should retain a direct reference to the player collider")
	_expect(
		main.player.get_node_or_null("CollisionShape") == main.player_collider,
		"player collider should have the stable CollisionShape node name used by gameplay code"
	)

	_test_weapon_models_and_selection(main)
	_test_procedural_audio(main)

	# Isolate hitscan checks from the city geometry while still exercising the
	# real physics ray, ammo consumption, falloff, and damage path.
	main.in_car = false
	main.player.global_transform = Transform(Basis(), Vector3(0, 50, 0))
	main.player.get_node("CollisionShape").disabled = false
	var target = _make_training_target(main, Vector3(0, 50.65, -12))
	yield(self, "physics_frame")
	yield(self, "physics_frame")

	main.set_weapon("rifle")
	main.weapon_cooldown = 0.0
	main.reload_remaining = 0.0
	main.ammo_in_mag["rifle"] = 30
	var ammo_before = int(main.ammo_in_mag["rifle"])
	main.try_fire_weapon()
	_expect(
		int(main.ammo_in_mag["rifle"]) == ammo_before - 1,
		"firing the assault rifle should consume exactly one cartridge"
	)
	_expect(
		int(target.get_meta("health")) == 86,
		"a near-range assault-rifle hit should reduce a 120 HP target by 34 HP"
	)

	_test_reload_transfer(main)
	_test_player_damage(main)
	_test_player_death_sequence(main)
	_test_damageable_vehicles(main)
	_test_hlf_fire_engine(main)
	_test_combined_emergency_dispatch(main)

	# The rifle target is behind the officer and cannot obstruct this shot, but
	# move the actors above the map again to keep the line of sight deterministic.
	main.player.global_transform = Transform(Basis(), Vector3(0, 50, 0))
	var officer_count_before = main.police_officers.size()
	main.spawn_police_officers(Vector3(0, 50, -6))
	_expect(
		main.police_officers.size() == officer_count_before + 2,
		"spawning a patrol should create two police officers"
	)
	if main.police_officers.size() > officer_count_before:
		var officer = main.police_officers[officer_count_before]
		officer.global_transform = Transform(Basis(), Vector3(0, 50, -6))
		if main.police_officers.size() > officer_count_before + 1:
			main.police_officers[officer_count_before + 1].translation = Vector3(20, 50, -6)
		yield(self, "physics_frame")
		yield(self, "physics_frame")
		_test_police_officer_and_shot(main, officer)

	if failures.empty():
		print("PASS: combat, audio, vehicle damage, HLF emergency equipment, death fade, reload, and police shooting")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)


func _test_weapon_models_and_selection(main):
	var models = {
		"pistol": main.pistol_model,
		"rifle": main.rifle_model,
		"bazooka": main.bazooka_model,
	}
	var all_models_exist = true
	for weapon in models:
		var exists = is_instance_valid(models[weapon])
		_expect(exists, "%s model should exist" % weapon)
		all_models_exist = all_models_exist and exists
	if not all_models_exist:
		return

	_expect(main.pistol_model.name == "Pistol", "pistol model should be identifiable")
	_expect(main.rifle_model.name == "AssaultRifle", "assault-rifle model should be identifiable")
	_expect(main.bazooka_model.name == "Bazooka", "rocket-launcher model should be identifiable")
	for weapon in ["pistol", "rifle", "bazooka"]:
		main.set_weapon(weapon)
		_expect(main.equipped_weapon == weapon, "%s should be selectable" % weapon)
		for candidate in models:
			_expect(
				models[candidate].visible == (candidate == weapon),
				"selecting %s should set the correct first-person model visibility" % weapon
			)


func _test_procedural_audio(main):
	var expected_sounds = ["pistol", "rifle", "police_pistol", "rocket", "explosion", "fire", "fire_engine", "martinshorn"]
	for sound_name in expected_sounds:
		var exists = main.sound_streams.has(sound_name)
		_expect(exists, "%s should have a procedural sound stream" % sound_name)
		if not exists:
			continue
		var stream = main.sound_streams[sound_name]
		var is_sample = stream is AudioStreamSample
		_expect(is_sample, "%s sound should be an AudioStreamSample" % sound_name)
		if not is_sample:
			continue
		_expect(stream.format == AudioStreamSample.FORMAT_16_BITS, "%s sound should use 16-bit PCM" % sound_name)
		_expect(stream.mix_rate == 22050, "%s sound should use the procedural 22050 Hz mix rate" % sound_name)
		_expect(not stream.stereo, "%s sound should remain mono for 3D positioning" % sound_name)
		_expect(stream.data.size() > 0, "%s sound should contain generated PCM frames" % sound_name)

	for loop_name in ["fire", "fire_engine", "martinshorn"]:
		if not main.sound_streams.has(loop_name) or not (main.sound_streams[loop_name] is AudioStreamSample):
			continue
		var loop_stream = main.sound_streams[loop_name]
		_expect(
			loop_stream.loop_mode == AudioStreamSample.LOOP_FORWARD,
			"%s sound should loop forward" % loop_name
		)
		_expect(loop_stream.loop_begin == 0, "%s loop should begin at its first frame" % loop_name)
		_expect(loop_stream.loop_end > loop_stream.loop_begin, "%s loop should have a non-empty range" % loop_name)

	if main.sound_streams.has("martinshorn") and main.sound_streams["martinshorn"] is AudioStreamSample:
		_test_martinshorn_sample(main.sound_streams["martinshorn"])


func _test_martinshorn_sample(stream: AudioStreamSample):
	_expect(stream.loop_end == 52920, "Martinshorn should retain an exact 2.4-second seamless loop")
	_expect(stream.data.size() == 105840, "Martinshorn should contain 52920 mono 16-bit frames")
	if stream.data.size() < 105840:
		return
	var peak = 0
	for frame in range(stream.loop_end):
		peak = max(peak, abs(_pcm_frame(stream, frame)))
	_expect(peak > 8000, "Martinshorn should have a strong pneumatic-horn level")
	_expect(peak < 32767, "Martinshorn synthesis should retain headroom without clipping")
	_expect(abs(_pcm_frame(stream, 0)) < 500 and abs(_pcm_frame(stream, stream.loop_end - 1)) < 500, "Martinshorn valve envelopes should close cleanly at the loop boundary")

	var low_435 = _pcm_tone_power(stream, 435.0, 0.14, 0.30)
	var low_450 = _pcm_tone_power(stream, 450.0, 0.14, 0.30)
	var low_high_pair = _pcm_tone_power(stream, 580.0, 0.14, 0.30) + _pcm_tone_power(stream, 600.0, 0.14, 0.30)
	var high_580 = _pcm_tone_power(stream, 580.0, 0.74, 0.30)
	var high_600 = _pcm_tone_power(stream, 600.0, 0.74, 0.30)
	var high_low_pair = _pcm_tone_power(stream, 435.0, 0.74, 0.30) + _pcm_tone_power(stream, 450.0, 0.74, 0.30)
	_expect(low_435 + low_450 > low_high_pair * 3.0, "low Martinshorn note should contain its 435/450 Hz horn pair")
	_expect(high_580 + high_600 > high_low_pair * 3.0, "high Martinshorn note should contain its 580/600 Hz horn pair")
	_expect(low_450 > low_435 * 0.15, "low Martinshorn note should retain the second bell that creates natural beating")
	_expect(high_600 > high_580 * 0.15, "high Martinshorn note should retain the second bell that creates natural beating")
	var plateau_rms = _pcm_rms(stream, 0.18, 0.20)
	var valve_rms = _pcm_rms(stream, 0.592, 0.016)
	_expect(valve_rms < plateau_rms * 0.72, "Martinshorn note change should include a brief pneumatic valve dip")


func _pcm_frame(stream: AudioStreamSample, frame: int) -> int:
	var byte_index = frame * 2
	var raw = int(stream.data[byte_index]) | (int(stream.data[byte_index + 1]) << 8)
	return raw - 65536 if raw >= 32768 else raw


func _pcm_rms(stream: AudioStreamSample, start_seconds: float, duration: float) -> float:
	var start_frame = int(start_seconds * stream.mix_rate)
	var frame_count = int(duration * stream.mix_rate)
	var energy = 0.0
	for frame_offset in range(frame_count):
		var value = float(_pcm_frame(stream, start_frame + frame_offset)) / 32768.0
		energy += value * value
	return sqrt(energy / float(max(1, frame_count)))


func _pcm_tone_power(stream: AudioStreamSample, frequency: float, start_seconds: float, duration: float) -> float:
	var start_frame = int(start_seconds * stream.mix_rate)
	var frame_count = int(duration * stream.mix_rate)
	var sine_sum = 0.0
	var cosine_sum = 0.0
	for frame_offset in range(frame_count):
		var window = 0.5 - cos(PI * 2.0 * float(frame_offset) / float(max(1, frame_count - 1))) * 0.5
		var sample_value = float(_pcm_frame(stream, start_frame + frame_offset)) / 32768.0 * window
		var phase = PI * 2.0 * frequency * float(frame_offset) / float(stream.mix_rate)
		sine_sum += sample_value * sin(phase)
		cosine_sum += sample_value * cos(phase)
	return sine_sum * sine_sum + cosine_sum * cosine_sum


func _make_training_target(main, position: Vector3) -> StaticBody:
	var target = StaticBody.new()
	target.name = "CombatTestTarget"
	target.set_meta("health", 120)
	target.set_meta("role", "training_target")
	var collision = CollisionShape.new()
	var shape = BoxShape.new()
	# Generous dimensions absorb the rifle's deliberate random spread.
	shape.extents = Vector3(1.8, 1.8, 0.5)
	collision.shape = shape
	target.add_child(collision)
	main.add_child(target)
	target.translation = position
	return target


func _test_reload_transfer(main):
	main.set_weapon("rifle")
	main.ammo_in_mag["rifle"] = 7
	main.ammo_reserve["rifle"] = 11
	main.start_reload()
	_expect(main.reloading_weapon == "rifle", "reload should remember the selected weapon")
	_expect(main.reload_remaining > 0.0, "rifle reload should start a timer")
	main.update_weapon_system(3.0, true)
	_expect(int(main.ammo_in_mag["rifle"]) == 18, "reload should transfer all 11 reserve rounds")
	_expect(int(main.ammo_reserve["rifle"]) == 0, "reload should subtract transferred rounds from reserve")
	_expect(main.reloading_weapon == "", "completed reload should clear its weapon state")
	_expect(main.reload_remaining == 0.0, "completed reload should clear its timer")


func _test_player_damage(main):
	main.player_health = 100
	main.damage_player(17)
	_expect(main.player_health == 83, "damage_player should subtract non-lethal damage from player HP")
	_expect(main.damage_flash_time > 0.0, "player damage should trigger visual feedback")


func _test_player_death_sequence(main):
	# Exercise the occupied-car branch as well: death must eject the player before
	# the physical presentation starts, then keep input locked through fade-in.
	main.in_car = true
	main.player.global_transform = main.car.global_transform
	main.player.get_node("CollisionShape").disabled = true
	main.player_health = 5
	main.damage_player(5)
	_expect(main.player_dying, "zero HP should start a single locked death sequence")
	_expect(main.player_health == 0, "death sequence should visibly retain zero HP before respawn")
	_expect(not main.in_car, "lethal damage in a car should eject the player before the fall")
	_expect(main.player.global_transform.origin.distance_to(main.car.global_transform.origin) > 2.4, "death ejection should place the player safely beside the car")
	_expect(main.death_fade_overlay.visible, "zero HP should reveal the fullscreen black fade")
	_expect(main.death_fade_layer.layer == 100, "death fade should render above every mission UI layer")
	var health_during_death = main.player_health
	main.damage_player(50)
	_expect(main.player_health == health_during_death, "additional hits should be ignored during the death sequence")

	main.update_player_death(0.78)
	_expect(main.player.rotation_degrees.x > 20.0, "death animation should tip the player backwards")
	_expect(main.death_fade_overlay.color.a > 0.15, "black fade should advance while the player falls")

	main.update_player_death(0.60)
	_expect(main.death_fade_overlay.color.a > 0.95, "screen should become fully black before the respawn is shown")
	_expect(main.player_health == 100, "player should respawn behind the opaque overlay")
	_expect(main.player_dying, "controls should remain locked until the image fades back in")
	main.damage_player(25)
	_expect(main.player_health == 100, "player should remain invulnerable while the respawn fades back in")

	main.update_player_death(1.05)
	_expect(not main.player_dying, "death sequence should unlock controls exactly after fade-in")
	_expect(not main.death_fade_overlay.visible, "death overlay should hide after fade-in")
	_expect(main.player.rotation_degrees == Vector3.ZERO, "respawn should restore the upright player rotation")
	_expect(main.camera.rotation_degrees == Vector3.ZERO, "respawn should restore the level first-person camera")
	_expect(not main.player.get_node("CollisionShape").disabled, "respawn should re-enable the player collider")

	# Run the same trigger a second time on foot. This covers the normal police
	# kill path and proves that no stale state prevents another death animation.
	main.in_car = false
	main.player.get_node("CollisionShape").disabled = false
	main.player_health = 1
	main.damage_player(1)
	_expect(main.player_dying and main.player_health == 0, "a later on-foot zero-HP hit should start the animation again")
	main.update_player_death(2.50)
	_expect(not main.player_dying and main.player_health == 100, "second death sequence should complete exactly once")
	_expect(not main.player.get_node("CollisionShape").disabled, "on-foot respawn should leave the collider enabled")


func _test_damageable_vehicles(main):
	_expect(main.car.has_meta("role") and str(main.car.get_meta("role")) == "vehicle", "player car should be registered with the vehicle role")
	_expect(main.car.has_meta("health"), "player car should expose damageable health metadata")
	_expect(main.car.has_meta("destroyed") and not bool(main.car.get_meta("destroyed")), "player car should begin undestroyed")
	_test_golf_vehicle_visual(main.car, false)
	if main.car.has_meta("health"):
		var initial_player_car_health = int(main.car.get_meta("health"))
		main.damage_vehicle(main.car, 9, false)
		_expect(
			int(main.car.get_meta("health")) == initial_player_car_health - 9,
			"damage_vehicle should reduce player-car HP"
		)
		_expect(main.car_health == initial_player_car_health - 9, "player-car metadata and HUD health should stay synchronized")
		# Restore the mission car so this focused assertion cannot affect later tests.
		main.car.set_meta("health", initial_player_car_health)
		main.car_health = initial_player_car_health

	# Keep the blast hundreds of metres from the player, while using the real
	# patrol-car factory and destruction path.
	var remote_position = main.player.global_transform.origin + Vector3(180, 0, 180)
	var police_car = main.create_emergency_vehicle("police", remote_position)
	_expect(is_instance_valid(police_car), "police vehicle factory should return a patrol car")
	if not is_instance_valid(police_car):
		return
	_expect(police_car.has_meta("role") and str(police_car.get_meta("role")) == "vehicle", "police car should be registered with the vehicle role")
	_expect(police_car.has_meta("health"), "police car should expose damageable health metadata")
	_expect(int(police_car.get_meta("health")) == 160, "police car should begin with 160 HP")
	_test_golf_vehicle_visual(police_car, true)

	main.damage_vehicle(police_car, 25, false)
	_expect(int(police_car.get_meta("health")) == 135, "damage_vehicle should reduce police-car HP")
	var fires_before = main.vehicle_fires.size()
	var player_health_before_blast = main.player_health
	main.damage_vehicle(police_car, 200)
	_expect(bool(police_car.get_meta("destroyed")), "lethal vehicle damage should mark the patrol car destroyed")
	_expect(int(police_car.get_meta("health")) == 0, "destroyed patrol car should have zero HP")
	_expect(main.destroyed_vehicles.has(police_car), "destroyed patrol car should enter the destroyed-vehicle registry")
	_expect(main.player_health == player_health_before_blast, "remote test-vehicle explosion should not damage the player")
	_expect(main.vehicle_fires.size() == fires_before + 1, "destroying a patrol car should create one vehicle fire")
	if main.vehicle_fires.size() > fires_before:
		var fire_data = main.vehicle_fires[main.vehicle_fires.size() - 1]
		var fire_effect = fire_data.get("effect", null)
		var fire_audio = fire_data.get("audio", null)
		_expect(is_instance_valid(fire_effect) and fire_effect.name == "VehicleFire", "destroyed patrol car should own a visible VehicleFire effect")
		_expect(is_instance_valid(fire_audio), "vehicle fire should create a 3D audio player")
		if is_instance_valid(fire_audio):
			_expect(fire_audio.stream == main.sound_streams["fire"], "vehicle fire should use the looping procedural fire stream")


func _test_golf_vehicle_visual(vehicle, police_variant: bool):
	var visual = vehicle.get_node_or_null("Golf7Visual")
	_expect(is_instance_valid(visual), "player and police cars should use the Golf7 visual wrapper")
	if not is_instance_valid(visual):
		return
	var model = visual.get_node_or_null("Golf7Model")
	_expect(is_instance_valid(model), "Golf7 visual wrapper should contain the imported model")
	if not is_instance_valid(model):
		return
	for mesh_name in ["Auto", "Reifen_VL", "Reifen_VR", "Reifen_HL", "Reifen_HR"]:
		_expect(model.get_node_or_null(mesh_name) is MeshInstance, "Golf7 model should contain mesh %s" % mesh_name)
	var collider = vehicle.get_node_or_null("CollisionShape")
	_expect(is_instance_valid(collider) and collider.shape is BoxShape, "Golf7 vehicle should retain a simple box collider")
	if is_instance_valid(collider) and collider.shape is BoxShape:
		_expect(collider.shape.extents == Vector3(1.06, 0.72, 2.14), "Golf7 collider should match the scaled model bounds")
	if police_variant:
		_expect(vehicle.get_node_or_null("PoliceDoorLabelLeft") is Label3D, "police Golf should retain its left POLIZEI marking")
		_expect(vehicle.get_node_or_null("PoliceDoorLabelRight") is Label3D, "police Golf should retain its right POLIZEI marking")
		_expect(vehicle.get_node_or_null("BlueLightLeft") is MeshInstance, "police Golf should retain the left blue beacon")
		_expect(vehicle.get_node_or_null("BlueLightRight") is MeshInstance, "police Golf should retain the right blue beacon")


func _test_hlf_fire_engine(main):
	# Keep the factory/destruction checks well away from the player and the patrol
	# car created above while exercising the same runtime path as a real dispatch.
	var remote_position = main.player.global_transform.origin + Vector3(-220, 0, 220)
	remote_position.y = main.HLF_GROUND_HEIGHT
	var fire_engine = main.create_emergency_vehicle("fire", remote_position)
	_expect(is_instance_valid(fire_engine), "fire-vehicle factory should return an HLF")
	if not is_instance_valid(fire_engine):
		return

	_expect(fire_engine.name == "FireEngine", "fire vehicle should retain the stable FireEngine node name")
	_expect(fire_engine.has_meta("role") and str(fire_engine.get_meta("role")) == "vehicle", "HLF should be registered with the vehicle role")
	_expect(fire_engine.has_meta("vehicle_kind") and str(fire_engine.get_meta("vehicle_kind")) == "fire_vehicle", "HLF should identify itself as a fire vehicle")
	_expect(fire_engine.has_meta("health") and int(fire_engine.get_meta("health")) == 240, "HLF should begin with 240 HP")
	_expect(fire_engine.has_meta("max_health") and int(fire_engine.get_meta("max_health")) == 240, "HLF maximum health should be 240 HP")
	_expect(fire_engine.has_meta("destroyed") and not bool(fire_engine.get_meta("destroyed")), "HLF should begin undestroyed")

	var visual = fire_engine.get_node_or_null("HLFVisual")
	_expect(is_instance_valid(visual), "HLF should contain its imported-model visual wrapper")
	var tire_contact_y = main.HLF_GROUND_HEIGHT + main.HLF_VISUAL_OFFSET.y + main.HLF_TIRE_BOTTOM_LOCAL_Y
	_expect(abs(tire_contact_y - 0.045) < 0.0001, "HLF tires should sit slightly into every visible road surface without a gap")
	var model = visual.get_node_or_null("HLFModel") if is_instance_valid(visual) else null
	_expect(is_instance_valid(model), "HLF visual wrapper should contain the imported HLF model")

	var front_beacon = _find_descendant(model, "Blaulicht_Vorne") if is_instance_valid(model) else null
	var rear_beacon = _find_descendant(model, "Blaulicht_Hinten") if is_instance_valid(model) else null
	_test_hlf_beacon(front_beacon, "front")
	_test_hlf_beacon(rear_beacon, "rear")
	var front_flash = model.get_node_or_null("BlueFlashLightFront") if is_instance_valid(model) else null
	var rear_flash_left = model.get_node_or_null("BlueFlashLightRearLeft") if is_instance_valid(model) else null
	var rear_flash_right = model.get_node_or_null("BlueFlashLightRearRight") if is_instance_valid(model) else null
	_test_hlf_flash_light(front_flash, Vector3(0.0113, 2.6606, 0.7325), "front")
	_test_hlf_flash_light(rear_flash_left, Vector3(-0.7865, 2.7684, -5.3798), "rear-left")
	_test_hlf_flash_light(rear_flash_right, Vector3(0.7836, 2.7684, -5.3798), "rear-right")

	var collider = fire_engine.get_node_or_null("CollisionShape")
	_expect(is_instance_valid(collider) and collider.shape is BoxShape, "HLF should retain a direct box collider")
	if is_instance_valid(collider) and collider.shape is BoxShape:
		_expect(collider.shape.extents == Vector3(1.15, 1.25, 3.70), "HLF collider should match the imported model bounds")
		var collider_bottom = main.HLF_GROUND_HEIGHT + collider.translation.y - collider.shape.extents.y
		_expect(abs(collider_bottom) < 0.0001, "HLF collider should physically rest on the colliding ground")

	var engine_audio = fire_engine.get_node_or_null("EngineAudio")
	var martinshorn_audio = fire_engine.get_node_or_null("MartinshornAudio")
	_test_hlf_loop_audio(engine_audio, main.sound_streams.get("fire_engine", null), "engine")
	_test_hlf_loop_audio(martinshorn_audio, main.sound_streams.get("martinshorn", null), "Martinshorn")

	var has_light_helper = main.has_method("set_hlf_blue_lights")
	_expect(has_light_helper, "main should expose set_hlf_blue_lights for deterministic beacon updates")
	if has_light_helper and front_beacon is MeshInstance and rear_beacon is MeshInstance:
		main.set_hlf_blue_lights(fire_engine, true, false)
		_expect(is_instance_valid(front_flash) and front_flash.visible, "front HLF OmniLight should be visible in the front-on phase")
		_expect(is_instance_valid(rear_flash_left) and not rear_flash_left.visible, "left rear HLF OmniLight should be hidden in the front-on phase")
		_expect(is_instance_valid(rear_flash_right) and not rear_flash_right.visible, "right rear HLF OmniLight should be hidden in the front-on phase")
		var front_emission = _hlf_beacon_emission_strength(front_beacon)
		var rear_emission = _hlf_beacon_emission_strength(rear_beacon)
		_expect(
			front_emission > rear_emission + 0.5,
			"front-on HLF phase should have materially stronger front emission than rear emission"
		)

	# At the incident the diesel remains in idle while the Martinshorn stops. It
	# must be possible to resume the en-route state before destruction as well.
	main.update_hlf_emergency_effects(fire_engine, false)
	if engine_audio is AudioStreamPlayer3D:
		_expect(engine_audio.playing and is_equal_approx(engine_audio.pitch_scale, 0.78), "arrived HLF should retain its idling engine loop")
	if martinshorn_audio is AudioStreamPlayer3D:
		_expect(not martinshorn_audio.playing, "arrived HLF should stop its Martinshorn loop")
	main.update_hlf_emergency_effects(fire_engine, true)
	if martinshorn_audio is AudioStreamPlayer3D:
		_expect(martinshorn_audio.playing, "en-route HLF state should resume its Martinshorn loop")

	# Exercise the real arrival branch at a distance where another response vehicle
	# can physically stop the long HLF. Arrival must stop the horn before deploying.
	fire_engine.rotation_degrees.y = 90.0
	var incident = fire_engine.global_transform.origin + Vector3(0, 0, 18)
	var operation_count_before = main.firefighting_operations.size()
	var arrival_response = {
		"node": fire_engine,
		"kind": "fire",
		"target": fire_engine.translation + Vector3(5.5, 0, 0),
		"incident": incident,
		"arrived": false
	}
	main.emergency_vehicles.append(arrival_response)
	main.update_emergency_vehicles(1.0 / 60.0)
	_expect(arrival_response.arrived, "HLF should finish its arrival within its collision-aware six-metre radius")
	if martinshorn_audio is AudioStreamPlayer3D:
		_expect(not martinshorn_audio.playing, "HLF arrival must stop the Martinshorn before deploying firefighters")
	var operation = main.firefighting_operations[operation_count_before].root if main.firefighting_operations.size() > operation_count_before else null
	_expect(is_instance_valid(operation), "HLF arrival should create a firefighting operation")
	if is_instance_valid(operation):
		_expect(main.firefighting_operations.size() == operation_count_before + 1, "active firefighting operation should be tracked")
		_expect(is_equal_approx(float(operation.get_meta("duration_seconds")), 300.0), "fire suppression should last exactly five minutes")
		var timer = operation.get_node_or_null("SuppressionTimer")
		_expect(timer is Timer and is_equal_approx(timer.wait_time, 300.0), "fire suppression timer should wait 300 seconds")
		if timer is Timer:
			_expect(not timer.is_stopped(), "five-minute suppression timer should start on arrival")
		var nozzle_operator = operation.get_node_or_null("FirefighterNozzle")
		var backup = operation.get_node_or_null("FirefighterBackup")
		_expect(nozzle_operator is Spatial and backup is Spatial, "fire response should deploy a two-person hose crew")
		if nozzle_operator is Spatial and backup is Spatial:
			var operator_local = fire_engine.to_local(nozzle_operator.global_transform.origin)
			var backup_local = fire_engine.to_local(backup.global_transform.origin)
			_expect(abs(operator_local.x) > 1.75 and abs(backup_local.x) > 1.75, "firefighters should stand clear beside the HLF, never beneath it")
			_expect(sign(operator_local.x) == sign(backup_local.x), "two-person hose crew should deploy together on the incident side")
		_expect(operation.get_node_or_null("AttackHose") is Spatial, "firefighters should deploy a visible, thick attack hose")
		_expect(operation.get_node_or_null("WaterSpray") is ImmediateGeometry, "nozzle should emit a continuous visible water stream")
		var first_droplet = operation.get_node_or_null("WaterDroplet00")
		var droplet_position_before = first_droplet.global_transform.origin if first_droplet is Spatial else Vector3.ZERO
		main.update_firefighting_operations(0.25)
		_expect(float(operation.get_meta("elapsed_seconds")) >= 0.25, "firefighting effect should advance throughout the five-minute operation")
		if first_droplet is Spatial:
			_expect(first_droplet.global_transform.origin.distance_to(droplet_position_before) > 0.1, "water droplets should visibly travel from nozzle to incident")
		main.extinguish_fire(incident, operation)
		_expect(operation.is_queued_for_deletion(), "completed suppression should clean up crew, hose, and spray together")
		_expect(main.firefighting_operations.size() == operation_count_before, "completed suppression should leave no stale operation state")
	main.emergency_vehicles.erase(arrival_response)

	main.damage_vehicle(fire_engine, 300)
	_expect(bool(fire_engine.get_meta("destroyed")), "lethal damage should mark the HLF destroyed")
	for flash_light in [front_flash, rear_flash_left, rear_flash_right]:
		if flash_light is OmniLight:
			_expect(not flash_light.visible, "destroying the HLF should switch off every blue cast light")
	if engine_audio is AudioStreamPlayer3D:
		_expect(not engine_audio.playing, "destroying the HLF should stop its engine loop")
	if martinshorn_audio is AudioStreamPlayer3D:
		_expect(not martinshorn_audio.playing, "destroying the HLF should stop its Martinshorn loop")


func _test_combined_emergency_dispatch(main):
	# A collapsed building dispatches fire and police back-to-back. Their original
	# route variants were identical, which spawned the first patrol car inside the
	# HLF and later blocked its arrival state.
	var marker = Spatial.new()
	main.destroyed_buildings.append(marker)
	var previous_police_dispatch_count = main.police_dispatch_count
	main.police_dispatch_count = 0
	var response_count_before = main.emergency_vehicles.size()
	var incident = Vector3(45, 0, 45)
	main.dispatch_fire_department(incident)
	main.dispatch_police(incident, 2)
	_expect(main.emergency_vehicles.size() == response_count_before + 3, "combined incident should dispatch one HLF and two patrol cars")
	if main.emergency_vehicles.size() >= response_count_before + 3:
		var fire_response = main.emergency_vehicles[response_count_before]
		var first_police_response = main.emergency_vehicles[response_count_before + 1]
		var fire_vehicle = fire_response.node
		var police_vehicle = first_police_response.node
		var travel = fire_response.target - fire_vehicle.translation
		travel.y = 0.0
		if travel.length_squared() > 0.0001:
			travel = travel.normalized()
			var lane_right = Vector3(-travel.z, 0.0, travel.x)
			var spawn_separation = police_vehicle.translation - fire_vehicle.translation
			var target_separation = first_police_response.target - fire_response.target
			_expect(abs(spawn_separation.dot(lane_right)) >= 2.9, "first patrol car should spawn in a separate lane beside the HLF")
			_expect(abs(target_separation.dot(lane_right)) >= 2.9, "first patrol car should retain its separate lane at the incident")
			var fire_forward = -fire_vehicle.global_transform.basis.z.normalized()
			_expect(fire_forward.dot(travel) > 0.99, "HLF should spawn already aligned with its route to avoid collision recovery")

	for response_index in range(main.emergency_vehicles.size() - 1, response_count_before - 1, -1):
		var response = main.emergency_vehicles[response_index]
		if is_instance_valid(response.node):
			main.stop_fire_engine_audio(response.node)
			response.node.queue_free()
		main.emergency_vehicles.remove(response_index)
	main.destroyed_buildings.erase(marker)
	marker.free()
	main.police_dispatch_count = previous_police_dispatch_count


func _test_hlf_beacon(beacon, location: String):
	_expect(beacon is MeshInstance, "HLF model should contain the nested %s blue-light mesh" % location)
	if not (beacon is MeshInstance):
		return
	_expect(beacon.mesh != null and beacon.mesh.get_surface_count() > 0, "%s HLF beacon should contain at least one mesh surface" % location)
	if beacon.mesh == null:
		return
	_expect(beacon.has_meta("blue_light_surface"), "%s HLF beacon should register its blue-light surface" % location)
	if beacon.has_meta("blue_light_surface"):
		var surface_index = int(beacon.get_meta("blue_light_surface"))
		_expect(surface_index >= 0 and surface_index < beacon.mesh.get_surface_count(), "%s HLF beacon should register a valid surface index" % location)
		var light_material = beacon.get_surface_material(surface_index) if surface_index >= 0 and surface_index < beacon.mesh.get_surface_count() else null
		_expect(light_material is SpatialMaterial, "%s HLF beacon surface should have a SpatialMaterial override" % location)
		if light_material is SpatialMaterial:
			_expect(light_material.emission_enabled, "%s HLF beacon surface override should be emissive" % location)
			_expect(light_material.emission.b > light_material.emission.r and light_material.emission.b > light_material.emission.g, "%s HLF beacon emission should remain blue" % location)


func _test_hlf_flash_light(flash_light, expected_position: Vector3, location: String):
	_expect(flash_light is OmniLight, "HLF should contain the %s BlueFlashLight OmniLight" % location)
	if not (flash_light is OmniLight):
		return
	_expect(flash_light.translation.distance_to(expected_position) < 0.001, "%s HLF OmniLight should sit at the optical lens centre" % location)
	_expect(flash_light.omni_range > 0.0 and flash_light.light_energy > 0.0, "%s HLF OmniLight should cast visible blue light" % location)


func _test_hlf_loop_audio(audio, expected_stream, label: String):
	_expect(audio is AudioStreamPlayer3D, "HLF should contain a direct %s AudioStreamPlayer3D" % label)
	if not (audio is AudioStreamPlayer3D):
		return
	_expect(audio.get_parent().name == "FireEngine", "HLF %s audio should move with the vehicle" % label)
	_expect(audio.stream == expected_stream and expected_stream != null, "HLF %s audio should use its registered sound stream" % label)
	_expect(audio.playing, "HLF %s audio loop should start with the vehicle" % label)
	_expect(audio.unit_size > 1.0, "HLF %s audio should use deliberate long-range attenuation" % label)
	var expected_range_mode = AudioStreamPlayer3D.OUT_OF_RANGE_MIX if label == "Martinshorn" else AudioStreamPlayer3D.OUT_OF_RANGE_PAUSE
	_expect(audio.out_of_range_mode == expected_range_mode, "HLF %s audio should use its intended long-range loop mode" % label)
	if label == "Martinshorn":
		_expect(audio.doppler_tracking == AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP, "Martinshorn should use physics-step Doppler tracking while the HLF moves")
		_expect(audio.emission_angle_enabled and audio.emission_angle_degrees >= 75.0, "Martinshorn should use a broad forward-facing horn pattern")
	if audio.stream is AudioStreamSample:
		_expect(audio.stream.loop_mode == AudioStreamSample.LOOP_FORWARD, "HLF %s audio stream should loop forward" % label)


func _find_descendant(node, target_name: String):
	if not is_instance_valid(node):
		return null
	if node.name == target_name:
		return node
	for child in node.get_children():
		var descendant = _find_descendant(child, target_name)
		if descendant != null:
			return descendant
	return null


func _hlf_beacon_emission_strength(beacon: MeshInstance) -> float:
	if beacon.mesh == null or not beacon.has_meta("blue_light_surface"):
		return 0.0
	var surface_index = int(beacon.get_meta("blue_light_surface"))
	if surface_index < 0 or surface_index >= beacon.mesh.get_surface_count():
		return 0.0
	var light_material = beacon.get_surface_material(surface_index)
	if not (light_material is SpatialMaterial) or not light_material.emission_enabled:
		return 0.0
	var emission_peak = max(light_material.emission.r, max(light_material.emission.g, light_material.emission.b))
	return emission_peak * light_material.emission_energy


func _test_police_officer_and_shot(main, officer):
	_expect(is_instance_valid(officer), "spawned police officer should remain valid")
	if not is_instance_valid(officer):
		return
	_expect(int(officer.get_meta("health")) == 120, "spawned police officer should have 120 HP")
	var service_pistol = officer.get_node_or_null("ServicePistol")
	_expect(service_pistol != null, "spawned police officer should carry a ServicePistol")
	var muzzle_flash = service_pistol.get_node_or_null("MuzzleFlash") if service_pistol else null
	_expect(muzzle_flash != null, "ServicePistol should contain a MuzzleFlash")

	main.in_car = false
	main.player_health = 100
	officer.set_meta("shots_fired", 0)
	main.police_shoot(officer)
	_expect(main.player_health == 88, "a clear first police shot should deal 12 HP to the player")
	_expect(int(officer.get_meta("shots_fired")) == 1, "police_shoot should record the fired shot")
	var target_center_y = main.player.get_node("CollisionShape").global_transform.origin.y
	_expect(
		officer.has_meta("last_aim_point") and officer.get_meta("last_aim_point").y < target_center_y,
		"police should aim below capsule centre at the player's torso, never over the head"
	)
	if muzzle_flash:
		_expect(muzzle_flash.visible, "police_shoot should flash the service-pistol muzzle")


func _expect(condition: bool, message: String):
	if not condition:
		failures.append(message)
