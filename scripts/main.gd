extends Control
## 彩球果實物理場：單檔自繪直屏合球遊戲。
## 所有球、容器、陰影、形變與粒子都以 Godot draw_* API 程式繪製。

const DESIGN_SIZE := Vector2(540.0, 960.0)
const LEFT_WALL := 52.0
const RIGHT_WALL := 488.0
const PLAY_TOP := 236.0
const FLOOR_Y := 866.0
const DANGER_LINE := 306.0
const UI_FONT: Font = preload("res://assets/template/fonts/ui_regular.tres")
const UI_FONT_MEDIUM: Font = preload("res://assets/template/fonts/ui_medium.tres")

const TIER_RADIUS_VALUES := [18.0, 25.0, 34.0, 45.0, 58.0, 73.0]
const TIER_NAMES: Array[String] = ["莓果", "蜜橘", "青檸", "薄荷", "藍莓", "葡萄"]
const TIER_TEXTURE_DIR := "res://assets/balls/"

var _state := "title"
var _paused := false
var _score := 0
var _best_score := 0
var _aim_x := 270.0
var _current_tier := 0
var _next_tier := 1
var _drop_cooldown := 0.0
var _danger_time := 0.0
var _message := ""
var _message_time := 0.0
var _rng := RandomNumberGenerator.new()
var _last_input_was_touch := false

var balls: Array[Dictionary] = []
var particles: Array[Dictionary] = []

# 公開給有限度驗證使用的資料，讓核心規則可被檢查而不依賴截圖。
var _tier_radii: Array = TIER_RADIUS_VALUES
var _tier_colors: Array[Color] = [
	Color("#ff6b6b"), Color("#ffbd59"), Color("#b8e05f"),
	Color("#56d6d2"), Color("#6d9bff"), Color("#b784f3"),
]
var _tier_texture_paths: Array[String] = []
var _tier_textures: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 20261015
	_best_score = int(ProjectSettings.get_setting("application/config/version", "0"))
	_load_tier_textures()
	_reset_run()
	queue_redraw()


func _process(delta: float) -> void:
	var dt := minf(delta, 0.04)
	if _state == "game" and not _paused:
		_drop_cooldown = maxf(0.0, _drop_cooldown - dt)
		for _step in 3:
			_simulate_step(dt / 3.0)
		_update_particles(dt)
		_check_game_over(dt)
	else:
		_update_particles(dt)
	if _message_time > 0.0:
		_message_time -= dt
		if _message_time <= 0.0:
			_message = ""
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_aim_x = clampf(event.position.x, LEFT_WALL + 8.0, RIGHT_WALL - 8.0)
	elif event is InputEventScreenTouch:
		_last_input_was_touch = true
		_aim_x = clampf(event.position.x, LEFT_WALL + 8.0, RIGHT_WALL - 8.0)
		if not event.pressed:
			_handle_primary_action(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_last_input_was_touch = false
		_aim_x = clampf(event.position.x, LEFT_WALL + 8.0, RIGHT_WALL - 8.0)
		_handle_primary_action(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			_start_game()
		elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			if _state == "title" or _state == "game_over":
				_start_game()
			elif _state == "game":
				_drop_ball()
		elif event.keycode == KEY_ESCAPE and _state == "game":
			_paused = not _paused
			_message = "已暫停" if _paused else "繼續遊戲"
			_message_time = 1.0


func _handle_primary_action(point: Vector2) -> void:
	if _state == "title":
		if Rect2(126.0, 684.0, 288.0, 68.0).has_point(point):
			_start_game()
	elif _state == "game_over":
		if Rect2(126.0, 650.0, 288.0, 68.0).has_point(point):
			_start_game()
	elif _state == "game":
		if Rect2(390.0, 52.0, 112.0, 42.0).has_point(point):
			_start_game()
		elif Rect2(38.0, 52.0, 92.0, 42.0).has_point(point):
			_paused = not _paused
		else:
			_drop_ball()


func _reset_run() -> void:
	balls.clear()
	particles.clear()
	_score = 0
	_danger_time = 0.0
	_drop_cooldown = 0.0
	_aim_x = 270.0
	_current_tier = _random_tier()
	_next_tier = _random_tier()


func _start_game() -> void:
	_reset_run()
	_state = "game"
	_paused = false
	_message = "拖曳選擇落點，點一下投球"
	_message_time = 2.8
	queue_redraw()


func _random_tier() -> int:
	# 前三級出現機率較高，讓新局容易建立合成節奏。
	var roll := _rng.randf()
	if roll < 0.54:
		return 0
	if roll < 0.82:
		return 1
	if roll < 0.96:
		return 2
	return 3


func _load_tier_textures() -> void:
	_tier_texture_paths.clear()
	_tier_textures.clear()
	for tier in range(6):
		var path := TIER_TEXTURE_DIR + str(tier + 1) + ".png"
		_tier_texture_paths.append(path)
		if ResourceLoader.exists(path):
			_tier_textures.append(load(path) as Texture2D)
		else:
			_tier_textures.append(null)


func _make_ball(tier: int, position: Vector2) -> Dictionary:
	return {
		"tier": clampi(tier, 0, _tier_radii.size() - 1),
		"pos": position,
		"vel": Vector2.ZERO,
		"squash": Vector2.ONE,
		"rotation": 0.0,
		"impact": 0.0,
		"lock": 0.24,
		"rest": 0.0,
	}


func _drop_ball() -> void:
	if _state != "game" or _paused or _drop_cooldown > 0.0:
		return
	var radius: float = float(_tier_radii[_current_tier])
	var spawn := Vector2(clampf(_aim_x, LEFT_WALL + radius, RIGHT_WALL - radius), PLAY_TOP - radius - 2.0)
	balls.append(_make_ball(_current_tier, spawn))
	_current_tier = _next_tier
	_next_tier = _random_tier()
	_drop_cooldown = 0.28
	_message = ""
	_message_time = 0.0


func _simulate_step(delta: float) -> void:
	for ball in balls:
		var velocity: Vector2 = ball["vel"]
		var tier: int = int(ball["tier"])
		var radius: float = float(_tier_radii[tier])
		velocity.y += 1180.0 * delta
		velocity *= Vector2(0.994, 0.996)
		ball["vel"] = velocity
		ball["pos"] = (ball["pos"] as Vector2) + velocity * delta
		ball["lock"] = maxf(0.0, float(ball["lock"]) - delta)
		ball["squash"] = (ball["squash"] as Vector2).lerp(Vector2.ONE, minf(1.0, delta * 10.5))
		ball["impact"] = maxf(0.0, float(ball["impact"]) - delta * 4.2)
		ball["rotation"] = lerp_angle(float(ball["rotation"]), 0.0, minf(1.0, delta * 7.0))
		if velocity.length() < 24.0 and float(ball["impact"]) < 0.08:
			ball["rest"] = float(ball["rest"]) + delta
		else:
			ball["rest"] = 0.0
		if float(ball["rest"]) > 0.16 and (ball["pos"] as Vector2).y + radius >= FLOOR_Y - 1.5:
			velocity = Vector2.ZERO
			ball["vel"] = velocity
		_resolve_world_bounds(ball)

	# 每個物理小步最多完成一次合成，避免同一幀連鎖造成穿透。
	for i in balls.size():
		if i >= balls.size():
			break
		for j in range(i + 1, balls.size()):
			if j >= balls.size():
				break
			var a: Dictionary = balls[i]
			var b: Dictionary = balls[j]
			var delta_pos: Vector2 = (b["pos"] as Vector2) - (a["pos"] as Vector2)
			var distance := delta_pos.length()
			var minimum: float = float(_tier_radii[int(a["tier"])]) + float(_tier_radii[int(b["tier"])])
			if distance >= minimum or distance <= 0.001:
				continue
			if int(a["tier"]) == int(b["tier"]) and int(a["tier"]) < _tier_radii.size() - 1 and float(a["lock"]) <= 0.0 and float(b["lock"]) <= 0.0:
				_merge_balls(i, j)
				return
			_resolve_ball_collision(a, b, delta_pos, distance, minimum)


func _resolve_world_bounds(ball: Dictionary) -> void:
	var tier: int = int(ball["tier"])
	var radius: float = float(_tier_radii[tier])
	var position: Vector2 = ball["pos"]
	var velocity: Vector2 = ball["vel"]
	if position.x - radius < LEFT_WALL:
		position.x = LEFT_WALL + radius
		if velocity.x < 0.0:
			_set_impact(ball, absf(velocity.x) * 0.7, Vector2.LEFT)
			velocity.x = -velocity.x * 0.42
	elif position.x + radius > RIGHT_WALL:
		position.x = RIGHT_WALL - radius
		if velocity.x > 0.0:
			_set_impact(ball, absf(velocity.x) * 0.7, Vector2.RIGHT)
			velocity.x = -velocity.x * 0.42
	if position.y + radius > FLOOR_Y:
		position.y = FLOOR_Y - radius
		if velocity.y > 40.0:
			_set_impact(ball, absf(velocity.y), Vector2.UP)
			velocity.y = -velocity.y * 0.32
		else:
			velocity.y = 0.0
			if absf(velocity.x) < 8.0:
				velocity.x = 0.0
			velocity.x *= 0.86
	ball["pos"] = position
	ball["vel"] = velocity


func _resolve_ball_collision(a: Dictionary, b: Dictionary, delta_pos: Vector2, distance: float, minimum: float) -> void:
	var normal := delta_pos / distance
	var overlap := minimum - distance
	if overlap < 0.45:
		return
	var a_radius: float = float(_tier_radii[int(a["tier"])])
	var b_radius: float = float(_tier_radii[int(b["tier"])])
	var total: float = a_radius + b_radius
	a["pos"] = (a["pos"] as Vector2) - normal * overlap * 0.72 * (b_radius / total)
	b["pos"] = (b["pos"] as Vector2) + normal * overlap * 0.72 * (a_radius / total)
	var relative: Vector2 = (b["vel"] as Vector2) - (a["vel"] as Vector2)
	var velocity_along := relative.dot(normal)
	if velocity_along < 0.0:
		var mass_a := maxf(1.0, a_radius * a_radius)
		var mass_b := maxf(1.0, b_radius * b_radius)
		var impulse := -(1.0 + 0.30) * velocity_along / (1.0 / mass_a + 1.0 / mass_b)
		a["vel"] = (a["vel"] as Vector2) - normal * impulse / mass_a
		b["vel"] = (b["vel"] as Vector2) + normal * impulse / mass_b
		var tangent := Vector2(-normal.y, normal.x)
		var tangent_speed := relative.dot(tangent)
		var friction := clampf(-tangent_speed * 0.11, -impulse * 0.22, impulse * 0.22)
		a["vel"] = (a["vel"] as Vector2) - tangent * friction / mass_a
		b["vel"] = (b["vel"] as Vector2) + tangent * friction / mass_b
		if absf(velocity_along) > 32.0:
			_set_impact(a, absf(velocity_along), normal)
			_set_impact(b, absf(velocity_along), -normal)


func _set_impact(ball: Dictionary, speed: float, normal: Vector2) -> void:
	var strength := clampf(speed / 420.0, 0.12, 1.0)
	ball["impact"] = maxf(float(ball["impact"]), strength)
	ball["squash"] = Vector2(1.0 + 0.26 * strength, 1.0 - 0.20 * strength)
	ball["rotation"] = normal.angle()
	if speed > 210.0:
		_spawn_burst(ball["pos"] as Vector2, _tier_colors[int(ball["tier"])], 3)


func _merge_balls(index_a: int, index_b: int) -> void:
	if index_a >= balls.size() or index_b >= balls.size():
		return
	var a: Dictionary = balls[index_a]
	var b: Dictionary = balls[index_b]
	var tier := int(a["tier"])
	var next_tier := mini(tier + 1, _tier_radii.size() - 1)
	var position := ((a["pos"] as Vector2) + (b["pos"] as Vector2)) * 0.5
	var velocity := ((a["vel"] as Vector2) + (b["vel"] as Vector2)) * 0.5
	var burst_color := _tier_colors[next_tier]
	var high_index := maxi(index_a, index_b)
	var low_index := mini(index_a, index_b)
	balls.remove_at(high_index)
	balls.remove_at(low_index)
	var merged := _make_ball(next_tier, position)
	merged["vel"] = velocity + Vector2(0.0, -42.0)
	merged["squash"] = Vector2(1.30, 0.72)
	merged["impact"] = 0.95
	merged["lock"] = 0.26
	balls.append(merged)
	_score += (tier + 1) * 12
	_spawn_burst(position, burst_color, 16)
	_message = "+%d  合成 %s" % [(tier + 1) * 12, TIER_NAMES[next_tier]]
	_message_time = 1.15


func _spawn_burst(position: Vector2, color: Color, amount: int) -> void:
	for _i in amount:
		var angle := _rng.randf_range(0.0, TAU)
		var speed := _rng.randf_range(80.0, 260.0)
		particles.append({
			"pos": position,
			"vel": Vector2.from_angle(angle) * speed,
			"life": _rng.randf_range(0.28, 0.62),
			"max_life": 0.62,
			"size": _rng.randf_range(2.0, 5.0),
			"color": color,
		})


func _update_particles(delta: float) -> void:
	for index in range(particles.size() - 1, -1, -1):
		var particle: Dictionary = particles[index]
		particle["life"] = float(particle["life"]) - delta
		if float(particle["life"]) <= 0.0:
			particles.remove_at(index)
			continue
		particle["vel"] = (particle["vel"] as Vector2) * 0.94
		particle["vel"].y += 480.0 * delta
		particle["pos"] = (particle["pos"] as Vector2) + (particle["vel"] as Vector2) * delta


func _check_game_over(delta: float) -> void:
	var threatening := false
	for ball in balls:
		var tier := int(ball["tier"])
		var position: Vector2 = ball["pos"]
		if position.y - _tier_radii[tier] < DANGER_LINE and absf((ball["vel"] as Vector2).y) < 72.0:
			threatening = true
			break
	if threatening:
		_danger_time += delta
	else:
		_danger_time = maxf(0.0, _danger_time - delta * 2.0)
	if _danger_time > 1.45:
		_state = "game_over"
		_paused = false
		_best_score = maxi(_best_score, _score)
		_message = "球堆超過危險線"
		_message_time = 2.0


func _debug_add_ball(tier: int, position: Vector2) -> void:
	var ball := _make_ball(tier, position)
	ball["lock"] = 0.0
	balls.append(ball)


func _debug_step(delta: float) -> void:
	_simulate_step(delta)


func _draw() -> void:
	_draw_background()
	if _state == "title":
		_draw_title()
	elif _state == "game" or _state == "game_over":
		_draw_game()
		if _state == "game_over":
			_draw_game_over()


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, DESIGN_SIZE), Color("#09111f"))
	draw_rect(Rect2(0.0, 0.0, DESIGN_SIZE.x, 170.0), Color("#101c31"))
	draw_circle(Vector2(455.0, 46.0), 170.0, Color(0.18, 0.33, 0.50, 0.13))
	draw_circle(Vector2(68.0, 930.0), 180.0, Color(0.32, 0.18, 0.45, 0.12))
	for y in range(180, 960, 48):
		draw_line(Vector2(0.0, y), Vector2(DESIGN_SIZE.x, y), Color(0.40, 0.58, 0.75, 0.035), 1.0)


func _draw_title() -> void:
	_draw_pill(Rect2(176.0, 104.0, 188.0, 30.0), Color(0.19, 0.86, 0.82, 0.13), Color(0.35, 0.95, 0.89, 0.75))
	_draw_centered("SUIKA PHYSICS LAB", 125.0, 12, Color("#8cf7e9"), UI_FONT_MEDIUM)
	_draw_centered("彩球果實", 290.0, 58, Color("#f8fbff"), UI_FONT_MEDIUM)
	_draw_centered("六色球體 × 彈性碰撞 × 合成連鎖", 337.0, 17, Color("#9eb2ce"), UI_FONT)
	_draw_pill(Rect2(92.0, 420.0, 356.0, 92.0), Color(0.06, 0.12, 0.22, 0.92), Color(0.24, 0.40, 0.58, 0.65))
	_draw_centered("把同色球碰在一起，合成更大的球", 455.0, 18, Color("#edf5ff"), UI_FONT_MEDIUM)
	_draw_centered("小心球堆不要越過上方的危險線", 486.0, 14, Color("#9eb2ce"), UI_FONT)
	_draw_pill(Rect2(126.0, 684.0, 288.0, 68.0), Color("#46d7c8"), Color("#8bfff0"), 16)
	_draw_centered("開始遊戲", 727.0, 23, Color("#062026"), UI_FONT_MEDIUM)
	_draw_centered("點擊或觸控開始  ·  R 重新開始", 816.0, 14, Color("#7189a8"), UI_FONT)
	_draw_centered("程式繪製 · 無外部素材", 858.0, 12, Color("#4c6380"), UI_FONT)


func _draw_game() -> void:
	# 頂部資訊列
	_draw_centered("彩球果實", 34.0, 17, Color("#eaf2ff"), UI_FONT_MEDIUM)
	_draw_pill(Rect2(38.0, 52.0, 92.0, 42.0), Color(0.08, 0.15, 0.26, 0.92), Color(0.22, 0.37, 0.55, 0.7))
	_draw_centered("暫停" if not _paused else "繼續", 79.0, 14, Color("#b9cce4"), UI_FONT_MEDIUM, Rect2(38.0, 52.0, 92.0, 42.0))
	_draw_pill(Rect2(144.0, 52.0, 172.0, 42.0), Color(0.08, 0.15, 0.26, 0.92), Color(0.22, 0.37, 0.55, 0.7))
	_draw_string("分數", Vector2(160.0, 78.0), 12, Color("#7791b4"), UI_FONT)
	_draw_string(str(_score), Vector2(218.0, 80.0), 20, Color("#f7d779"), UI_FONT_MEDIUM)
	_draw_pill(Rect2(390.0, 52.0, 112.0, 42.0), Color(0.08, 0.15, 0.26, 0.92), Color(0.22, 0.37, 0.55, 0.7))
	_draw_centered("重新開始", 79.0, 13, Color("#b9cce4"), UI_FONT_MEDIUM, Rect2(390.0, 52.0, 112.0, 42.0))

	# 下一顆球卡片
	_draw_pill(Rect2(382.0, 112.0, 120.0, 94.0), Color(0.07, 0.13, 0.23, 0.96), Color(0.22, 0.37, 0.55, 0.7))
	_draw_string("下一顆", Vector2(397.0, 135.0), 12, Color("#7895b8"), UI_FONT)
	_draw_ball_visual(_make_ball(_next_tier, Vector2(446.0, 167.0)), 0.82, true)
	_draw_string(TIER_NAMES[_next_tier], Vector2(456.0, 195.0), 11, Color("#afc2dc"), UI_FONT)

	# 直屏容器
	_draw_pill(Rect2(34.0, 214.0, 472.0, 674.0), Color(0.045, 0.085, 0.15, 0.94), Color(0.18, 0.34, 0.52, 0.92), 24)
	draw_rect(Rect2(52.0, PLAY_TOP, RIGHT_WALL - LEFT_WALL, FLOOR_Y - PLAY_TOP), Color(0.035, 0.07, 0.13, 0.86))
	# 內部柔和光帶與格線，保持幾何且不搶球體。
	for x in range(76, 488, 52):
		draw_line(Vector2(x, PLAY_TOP), Vector2(x, FLOOR_Y), Color(0.25, 0.48, 0.64, 0.035), 1.0)
	for y in range(280, 860, 58):
		draw_line(Vector2(52.0, y), Vector2(488.0, y), Color(0.25, 0.48, 0.64, 0.035), 1.0)
	# 危險線
	draw_line(Vector2(57.0, DANGER_LINE), Vector2(483.0, DANGER_LINE), Color(1.0, 0.40, 0.42, 0.68), 2.0)
	draw_line(Vector2(62.0, DANGER_LINE + 5.0), Vector2(478.0, DANGER_LINE + 5.0), Color(1.0, 0.40, 0.42, 0.16), 1.0)
	_draw_string("危險線", Vector2(62.0, DANGER_LINE - 10.0), 11, Color(1.0, 0.54, 0.55, 0.9), UI_FONT_MEDIUM)
	# 地面與牆面
	draw_line(Vector2(52.0, FLOOR_Y), Vector2(488.0, FLOOR_Y), Color("#6f9dbc"), 3.0)
	draw_line(Vector2(52.0, PLAY_TOP), Vector2(52.0, FLOOR_Y), Color(0.27, 0.56, 0.72, 0.75), 3.0)
	draw_line(Vector2(488.0, PLAY_TOP), Vector2(488.0, FLOOR_Y), Color(0.27, 0.56, 0.72, 0.75), 3.0)
	# 瞄準導引與待投球
	if not _paused and _state == "game":
		draw_dashed_line(Vector2(_aim_x, 220.0), Vector2(_aim_x, PLAY_TOP - 8.0), Color(0.56, 0.92, 0.87, 0.48), 1.5, 5.0)
		draw_circle(Vector2(_aim_x, 220.0), 4.0, Color("#8cf7e9"))
		_draw_ball_visual(_make_ball(_current_tier, Vector2(_aim_x, 180.0)), 0.88, true)
	for particle in particles:
		_draw_particle(particle)
	for ball in balls:
		_draw_ball_visual(ball)
	if _paused:
		_draw_pill(Rect2(138.0, 484.0, 264.0, 72.0), Color(0.04, 0.09, 0.16, 0.96), Color(0.39, 0.72, 0.78, 0.85))
		_draw_centered("已暫停", 529.0, 25, Color("#eaf8ff"), UI_FONT_MEDIUM)
	if _message_time > 0.0 and not _message.is_empty():
		_draw_pill(Rect2(90.0, 900.0, 360.0, 38.0), Color(0.08, 0.15, 0.25, 0.92), Color(0.24, 0.45, 0.60, 0.7), 14)
		_draw_centered(_message, 925.0, 14, Color("#c9d9ed"), UI_FONT_MEDIUM, Rect2(90.0, 900.0, 360.0, 38.0))


func _draw_game_over() -> void:
	draw_rect(Rect2(0.0, 0.0, DESIGN_SIZE.x, DESIGN_SIZE.y), Color(0.02, 0.04, 0.08, 0.58))
	_draw_pill(Rect2(72.0, 382.0, 396.0, 332.0), Color(0.045, 0.08, 0.15, 0.98), Color(1.0, 0.42, 0.48, 0.7), 24)
	_draw_centered("這局結束", 459.0, 31, Color("#fff4f2"), UI_FONT_MEDIUM)
	_draw_centered("球堆碰到危險線太久了", 499.0, 15, Color("#aebbd0"), UI_FONT)
	_draw_centered("本局分數", 556.0, 13, Color("#7894b6"), UI_FONT)
	_draw_centered(str(_score), 604.0, 42, Color("#f7d779"), UI_FONT_MEDIUM)
	_draw_pill(Rect2(126.0, 650.0, 288.0, 68.0), Color("#46d7c8"), Color("#8bfff0"), 16)
	_draw_centered("再玩一次", 693.0, 23, Color("#062026"), UI_FONT_MEDIUM)
	_draw_centered("點擊按鈕或按 R", 762.0, 14, Color("#879bb8"), UI_FONT)


func _draw_ball_visual(ball: Dictionary, alpha: float = 1.0, preview: bool = false) -> void:
	var tier := int(ball["tier"])
	var position: Vector2 = ball["pos"]
	var radius: float = float(_tier_radii[tier])
	var squash: Vector2 = ball["squash"]
	var rotation := float(ball["rotation"])
	var base := _tier_colors[tier]
	var texture: Texture2D = _tier_textures[tier] if tier < _tier_textures.size() else null
	var shadow := Color(0.0, 0.0, 0.0, 0.30 * alpha)
	if preview:
		shadow.a = 0.0
	# 落地陰影與外輪廓，讓形變在小螢幕上仍然清楚。
	if not preview:
		draw_set_transform(position + Vector2(2.0, 7.0), 0.0, Vector2(radius * 1.02, radius * 0.40))
		draw_circle(Vector2.ZERO, 1.0, shadow)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var body := base
	body.a = alpha
	draw_set_transform(position, rotation, Vector2(radius * squash.x, radius * squash.y))
	draw_circle(Vector2.ZERO, 1.04, Color(0.02, 0.06, 0.11, 0.75 * alpha))
	if texture != null:
		draw_texture_rect(texture, Rect2(-0.96, -0.96, 1.92, 1.92), false, Color(1.0, 1.0, 1.0, alpha))
	else:
		draw_circle(Vector2.ZERO, 0.96, body)
	var light := base.lightened(0.24)
	light.a = alpha * 0.92
	if texture == null:
		draw_circle(Vector2(-0.24, -0.27), 0.65, light)
	var shade := base.darkened(0.24)
	shade.a = alpha * 0.55
	if texture == null:
		draw_arc(Vector2(0.05, 0.10), 0.76, 0.20, 2.65, 18, shade, 0.08)
	if texture == null and tier >= 3:
		var ring := base.lightened(0.40)
		ring.a = alpha * 0.50
		draw_arc(Vector2.ZERO, 0.78, -2.55, -0.35, 16, ring, 0.06)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if not preview and tier >= 1:
		var label := str(tier + 1)
		_draw_centered(label, position.y + 6.0, maxf(11.0, radius * 0.42), Color(1.0, 1.0, 1.0, alpha * 0.72), UI_FONT_MEDIUM, Rect2(position.x - radius, position.y - radius, radius * 2.0, radius * 2.0))


func _draw_particle(particle: Dictionary) -> void:
	var life := clampf(float(particle["life"]) / float(particle["max_life"]), 0.0, 1.0)
	var color: Color = particle["color"]
	color.a = life * 0.8
	draw_circle(particle["pos"] as Vector2, float(particle["size"]) * life, color)


func _draw_pill(rect: Rect2, fill: Color, border: Color, radius: int = 13) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)


func _draw_string(text: String, position: Vector2, size: int, color: Color, font: Font = UI_FONT) -> void:
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


func _draw_centered(text: String, baseline_y: float, size: int, color: Color, font: Font = UI_FONT, region := Rect2(0.0, 0.0, DESIGN_SIZE.x, 0.0)) -> void:
	var width := region.size.x if region.size.x > 0.0 else DESIGN_SIZE.x
	var left := region.position.x if region.size.x > 0.0 else 0.0
	var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	_draw_string(text, Vector2(left + (width - text_width) * 0.5, baseline_y), size, color, font)
