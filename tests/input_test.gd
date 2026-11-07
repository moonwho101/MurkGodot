extends SceneTree
## Input check: drives the game with synthetic mouse and keyboard events and verifies the hero reacts.

var game: Node


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _click(pos: Vector2, button: int = MOUSE_BUTTON_LEFT, hold_frames: int = 3) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	Input.parse_input_event(ev)
	var down := InputEventMouseButton.new()
	down.position = pos
	down.button_index = button
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(hold_frames)
	var up := InputEventMouseButton.new()
	up.position = pos
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(1)


func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _check(label: String, ok: bool) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)


func _run() -> void:
	await _frames(5)
	game.on_splash_click()
	game.on_select_confirm()
	await _frames(3)
	_check("objective modal open", game.state == "MODAL")
	_key(KEY_ENTER, true)
	_key(KEY_ENTER, false)
	await _frames(3)
	_check("Enter closes modal", game.state == "PLAYING")

	var p = game.player
	game.ds.reveal(1, p.x, p.y, 8)
	# Click-to-move to a far explored cell.
	var target := Vector2i(p.x, p.y)
	var path = null
	for y in range(1, game.ds.n + 1):
		for x in range(1, game.ds.n + 1):
			var cell = game.ds.cell(x, y, 1)
			if cell.explored and game.ds.walkable(x, y, 1):
				var cand = game.ds.find_path(1, p.x, p.y, x, y)
				if cand != null and (path == null or cand.size() > path.size()) and cand.size() <= 6:
					path = cand
					target = Vector2i(x, y)
	print("target ", target, " from ", Vector2i(p.x, p.y), " steps ", path.size() if path else 0)
	var w: Vector2 = game.renderer.grid_to_world(target.x, target.y)
	var sp: Vector2 = game.renderer.world_to_screen(w)
	await _click(sp)
	await _frames(int(path.size() * 20) + 20)
	_check("click-to-move reaches target", p.x == target.x and p.y == target.y)

	# Keyboard movement
	var sx: int = p.x
	var sy: int = p.y
	for k in [KEY_W, KEY_A, KEY_S, KEY_D]:
		_key(k, true)
		await _frames(18)
		_key(k, false)
	_check("keyboard moves hero", p.x != sx or p.y != sy)

	# Fire with space and right-click
	var before: int = game.projectiles.size()
	_key(KEY_SPACE, true)
	await _frames(4)
	_key(KEY_SPACE, false)
	_check("space fires a missile", game.projectiles.size() > before or p.shots > 0)
	await _frames(40)
	await _click(Vector2(900, 300), MOUSE_BUTTON_RIGHT, 4)
	_check("right-click fires", p.shots > 0 or game.projectiles.size() > 0)

	# Zoom, map, pause keys
	var z: float = game.renderer.scale_px
	_key(KEY_EQUAL, true)
	_key(KEY_EQUAL, false)
	await _frames(3)
	_check("zoom key changes scale", game.renderer.scale_px != z)
	_key(KEY_M, true)
	_key(KEY_M, false)
	await _frames(2)
	_check("M opens map", game.state == "MAP")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(2)
	_check("Esc closes map", game.state == "PLAYING")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(2)
	_check("Esc pauses", game.state == "PAUSED")
	_key(KEY_ESCAPE, true)
	_key(KEY_ESCAPE, false)
	await _frames(2)
	_check("Esc resumes", game.state == "PLAYING")

	# Stairs: teleport onto a down ladder and press E.
	var stairs: Array = game.ds.find_stairs(1, "down")
	if not stairs.is_empty():
		p.teleport(stairs[0].x, stairs[0].y, 1)
		game.ds.reveal(1, p.x, p.y)
		game.on_player_arrive()
		_key(KEY_E, true)
		_key(KEY_E, false)
		await _frames(60)
		_check("ladder takes hero down", game.lvl == 2 and p.lvl == 2)

	# Win: carry the relic home and check reward flow + save.
	var relic = game.ds.relic(2)
	game.player_take_relic(relic)
	game.lvl = 1
	p.teleport(game.home.x, game.home.y, 1)
	game.setup_level_view(true)
	game.on_player_arrive()
	_check("episode complete modal", game.state == "MODAL")
	game.close_modal()
	_check("next episode started", game.episode_num == 2)
	_check("progress saved", game.load_save() != null)

	# Quit to title and continue from save.
	game.pause_quit()
	_check("title shown", game.state == "SELECT")
	game.on_continue()
	await _frames(3)
	_check("continue restores episode", game.episode_num == 2 and game.player.armour >= 30)
	quit()
