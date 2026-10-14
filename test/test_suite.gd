extends Node

var _failures: Array[String] = []
var _checks := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := load("res://scenes/main.tscn") as PackedScene
	_check(scene != null, "main scene must load")
	if scene == null:
		_finish()
		return
	var game := scene.instantiate()
	add_child(game)
	await get_tree().process_frame
	var radii: Array = game.get("_tier_radii")
	var colors: Array = game.get("_tier_colors")
	_check(radii.size() == 6, "game must define exactly six ball tiers")
	_check(colors.size() == 6, "game must define six tier colors")
	for index in range(1, radii.size()):
		_check(radii[index] > radii[index - 1], "ball radii must increase by tier")
	_check(str(game.get("_state")) == "title", "game must boot to title")
	game.call("_start_game")
	_check(str(game.get("_state")) == "game", "start action must enter gameplay")
	game.call("_debug_add_ball", 0, Vector2(210.0, 620.0))
	game.call("_debug_add_ball", 0, Vector2(240.0, 620.0))
	game.call("_debug_step", 0.016)
	var balls: Array = game.get("balls")
	_check(balls.size() == 1, "same-tier balls must merge into one ball")
	if balls.size() == 1:
		_check(int((balls[0] as Dictionary)["tier"]) == 1, "merge must promote the ball one tier")
		_check(int(game.get("_score")) > 0, "merge must award score")
	game.queue_free()
	_finish()


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition and message not in _failures:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("[suika-tests] PASS: %d checks" % _checks)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("[suika-tests] " + failure)
	print("[suika-tests] FAIL: %d failures across %d checks" % [_failures.size(), _checks])
	get_tree().quit(1)
