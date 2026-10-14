extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_verify")


func _verify() -> void:
	_check(ProjectSettings.get_setting("application/config/name") == "彩球果實物理場", "exported identity")
	var packed := load("res://scenes/main.tscn") as PackedScene
	_check(packed != null, "exported main scene")
	if packed != null:
		var main := packed.instantiate()
		root.add_child(main)
		await process_frame
		_check(str(main.get("_state")) == "title", "pack boots to title")
		var radii: Array = main.get("_tier_radii")
		_check(radii.size() == 6, "pack keeps six ball tiers")
		main.call("_start_game")
		await process_frame
		_check(str(main.get("_state")) == "game", "pack starts gameplay")
		main.call("_debug_add_ball", 1, Vector2(210.0, 620.0))
		main.call("_debug_add_ball", 1, Vector2(250.0, 620.0))
		main.call("_debug_step", 0.016)
		_check((main.get("balls") as Array).size() == 1, "pack merges same-tier balls")
		main.queue_free()
		await process_frame
	if _failures.is_empty():
		print("[suika-pack] PASS: identity, six tiers, title, gameplay and merge")
		quit(0)
	else:
		for failure in _failures:
			push_error("[suika-pack] " + failure)
		quit(1)


func _check(condition: bool, context: String) -> void:
	if not condition and context not in _failures:
		_failures.append(context)
