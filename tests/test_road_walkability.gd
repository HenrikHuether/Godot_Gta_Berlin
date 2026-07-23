extends SceneTree

const GENERATOR_SCRIPT = preload("res://scripts/berlin_surface_generator.gd")
const WALK_SPEED := 8.0
const GRAVITY := 24.0

var failures := []
var player: KinematicBody
var velocity := Vector3.ZERO
var physics_delta := 1.0 / 120.0


func _init():
	call_deferred("_run")


func _run():
	var physics_fps = max(
		1.0,
		float(ProjectSettings.get_setting("physics/common/physics_fps"))
	)
	physics_delta = 1.0 / physics_fps
	var ground = StaticBody.new()
	ground.name = "GroundSurface"
	var ground_collision = CollisionShape.new()
	var ground_shape = BoxShape.new()
	ground_shape.extents = Vector3(1000.0, 2.0, 1000.0)
	ground_collision.translation.y = -1.945
	ground_collision.shape = ground_shape
	ground.add_child(ground_collision)
	get_root().add_child(ground)

	var generator = GENERATOR_SCRIPT.new()
	generator.name = "Generator"
	get_root().add_child(generator)
	_expect(generator.build_from_file(), "street graph should build")
	if not generator.is_built():
		_finish()
		return

	var nearest = generator._nearest_street_edge(Vector3(3.0, 0.0, 8.0))
	var a = generator._street_points[int(nearest.a_id)]
	var b = generator._street_points[int(nearest.b_id)]
	var tangent = (b - a).normalized()
	var across = Vector3(-tangent.z, 0.0, tangent.x)
	var start = nearest.point + tangent * 24.0 + Vector3.UP * 3.0

	player = KinematicBody.new()
	player.name = "WalkabilityPlayer"
	player.collision_layer = 1
	player.collision_mask = 1
	var player_collision = CollisionShape.new()
	var capsule = CapsuleShape.new()
	capsule.radius = 0.45
	capsule.height = 1.70
	player_collision.shape = capsule
	player.add_child(player_collision)
	get_root().add_child(player)
	player.global_transform = Transform(Basis(), start)

	for _frame in range(int(physics_fps * 1.5)):
		yield(self, "physics_frame")
		_move_player(Vector3.ZERO)

	_expect(
		player.is_on_floor(),
		"player should settle on the road centre (position=%s, velocity=%s)"
		% [player.global_transform.origin, velocity]
	)
	var centre_start = player.global_transform.origin
	for _frame in range(int(physics_fps)):
		yield(self, "physics_frame")
		_move_player(tangent)
	var road_position = player.global_transform.origin
	var centre_distance = _horizontal_distance(centre_start, road_position)
	_expect(
		centre_distance > 7.0,
		"player should walk freely along the road centre (distance=%.3f)"
		% centre_distance
	)

	for _frame in range(int(physics_fps * 3.0)):
		yield(self, "physics_frame")
		_move_player(across)

	var final_position = player.global_transform.origin
	var edge_distance = _horizontal_distance(road_position, final_position)
	_expect(
		edge_distance > 20.0,
		"player should cross the road edge and continue walking on surrounding ground (distance=%.3f)"
		% edge_distance
	)
	_expect(final_position.y > -1.0, "player should remain above the ground surface")

	_finish()


func _move_player(direction: Vector3):
	velocity.x = direction.x * WALK_SPEED
	velocity.z = direction.z * WALK_SPEED
	velocity.y = -0.5 if player.is_on_floor() else velocity.y - GRAVITY * physics_delta
	velocity = player.move_and_slide(
		velocity,
		Vector3.UP,
		false,
		4,
		deg2rad(46.0),
		true
	)


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


func _expect(condition: bool, message: String):
	if not condition:
		failures.append(message)


func _finish():
	if failures.empty():
		print("PASS: player can walk continuously across generated road boundaries")
		quit(0)
		return
	for failure in failures:
		printerr("FAIL: %s" % failure)
	quit(1)
