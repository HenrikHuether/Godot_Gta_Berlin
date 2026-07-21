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
	_test_damageable_vehicles(main)

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
		print("PASS: combat weapons, audio, ammunition, vehicle damage, reload, and police shooting")
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
	var expected_sounds = ["pistol", "rifle", "police_pistol", "rocket", "explosion", "fire"]
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

	if main.sound_streams.has("fire") and main.sound_streams["fire"] is AudioStreamSample:
		var fire_stream = main.sound_streams["fire"]
		_expect(
			fire_stream.loop_mode == AudioStreamSample.LOOP_FORWARD,
			"vehicle-fire sound should loop forward"
		)
		_expect(fire_stream.loop_begin == 0, "vehicle-fire loop should begin at its first frame")
		_expect(fire_stream.loop_end > fire_stream.loop_begin, "vehicle-fire loop should have a non-empty range")


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


func _test_damageable_vehicles(main):
	_expect(main.car.has_meta("role") and str(main.car.get_meta("role")) == "vehicle", "player car should be registered with the vehicle role")
	_expect(main.car.has_meta("health"), "player car should expose damageable health metadata")
	_expect(main.car.has_meta("destroyed") and not bool(main.car.get_meta("destroyed")), "player car should begin undestroyed")
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
