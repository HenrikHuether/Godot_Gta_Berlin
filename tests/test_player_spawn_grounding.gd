extends SceneTree

const MAIN_SCENE = preload("res://main.tscn")
const OBSERVATION_SECONDS := 6.0

var failures := []


func _init():
	call_deferred("_run")


func _run():
	var main = MAIN_SCENE.instance()
	get_root().add_child(main)
	var start = main.player.global_transform.origin
	var minimum_y = start.y
	var physics_fps = max(
		1.0,
		float(ProjectSettings.get_setting("physics/common/physics_fps"))
	)
	for _frame in range(int(ceil(physics_fps * OBSERVATION_SECONDS))):
		yield(self, "physics_frame")
		minimum_y = min(minimum_y, main.player.global_transform.origin.y)

	var finish = main.player.global_transform.origin
	_expect(finish.y > 0.45, "player should remain above the Berlin floor after spawning")
	_expect(minimum_y > -0.5, "player should never fall through the map during spawn settling")
	_expect(main.player.is_on_floor(), "player should settle into an on-floor state")
	_expect(
		Vector2(finish.x - start.x, finish.z - start.z).length() < 0.1,
		"idle spawn settling should not move the player horizontally"
	)

	var ground_collision = main.get_node_or_null("BerlinMap/GroundSurface/CollisionShape")
	print(
		"Spawn grounding diagnostic: start=%s finish=%s minimum_y=%.3f floor=%s shape=%s"
		% [
			start,
			finish,
			minimum_y,
			main.player.is_on_floor(),
			ground_collision.shape.get_class() if ground_collision and ground_collision.shape else "None"
		]
	)
	if failures.empty():
		print("PASS: player remains grounded after the real main-scene spawn")
		quit(0)
		return
	for failure in failures:
		printerr("FAIL: %s" % failure)
	quit(1)


func _expect(condition: bool, message: String):
	if not condition:
		failures.append(message)
