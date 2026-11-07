extends SceneTree
## Smoke test: boots the game, starts a run and takes screenshots. Run with:
##   godot --path . -s res://tests/smoke_test.gd -- <output dir>

var game: Node
var out_dir := "user://shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	_run()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _shot(name: String) -> void:
	await _frames(2)
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name)


func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _run() -> void:
	await _frames(10)
	await _shot("01_splash")
	game.on_splash_click()
	await _frames(5)
	await _shot("02_select")
	game.on_class_picked("wizard")
	game.on_select_confirm()
	await _frames(5)
	await _shot("03_objective")
	game.close_modal()
	await _frames(30)
	await _shot("04_start")

	# Walk around with the keyboard and shoot.
	for dir_key in [KEY_D, KEY_S, KEY_A, KEY_W, KEY_D, KEY_D, KEY_S]:
		_key(dir_key, true)
		await _frames(25)
		_key(dir_key, false)
		_key(KEY_SPACE, true)
		await _frames(5)
		_key(KEY_SPACE, false)
	await _shot("05_walked")

	# Fast-forward: simulate many seconds of play to exercise AI and combat.
	for i in 600:
		game.update(0.05)
		if i % 10 == 0:
			_key(KEY_SPACE, true)
		await process_frame
	_key(KEY_SPACE, false)
	await _shot("06_after_sim")

	game.open_map()
	await _shot("07_map")
	game.close_map()
	game.open_pause()
	await _shot("08_pause")
	game.close_pause()
	game.show_help()
	await _shot("09_help")
	game.close_modal()

	game.player.skill = game.player.next_level_at
	game.add_skill(1)
	await _frames(5)
	await _shot("10_perks")
	game.choose_perk(0)

	print("player hp ", game.player.hp, " lvl ", game.lvl, " entities ", game.entities.size())
	quit()
