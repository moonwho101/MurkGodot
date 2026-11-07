extends SceneTree
## Logic soak test: plays every episode of every class with a randomly acting hero and reports script errors
## (they appear on stderr as SCRIPT ERROR). Run headless with:
##   godot --headless --path . -s res://tests/logic_test.gd

var game: Node
var stats := {"episodes": 0, "kills": 0, "deaths": 0, "rival_eps": 0, "perks": 0, "level_changes": 0}


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	_run()


func _key(code: int, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _step_actions(i: int) -> void:
	var p = game.player
	match game.state:
		"MODAL":
			game.close_modal()
			return
		"PERK":
			game.choose_perk(randi() % 3)
			stats.perks += 1
			return
		"PLAYING":
			pass
		_:
			return
	if i % 7 == 0:
		game.keys.clear()
		var codes := [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE]
		for c in codes:
			if randf() < 0.35:
				game.keys[c] = true
	if i % 40 == 0 and randf() < 0.5:
		game.use_stairs()
	if i % 97 == 0:
		game.use_ring()
	if i % 211 == 0:
		game.drop_relic(p, true)
	if i % 150 == 0 and randf() < 0.3:
		# Teleport around the dungeon so off-level AI and every floor get exercised.
		var l: int = 1 + randi() % game.ds.maxlevel
		var spot = game.ds.random_floor(l)
		if spot != null and p.alive:
			p.teleport(spot.x, spot.y, l)
			game.lvl = l
			game.setup_level_view(true)
			game.on_player_arrive()
	if i % 111 == 0 and randf() < 0.1:
		game.wake_all()
	if i % 60 == 0:
		game.path = []


func _run() -> void:
	randomize()
	await process_frame
	game.on_splash_click()
	for cls in Defs.CLASS_ORDER:
		var def: Dictionary = Defs.CLASS_DEFS[cls]
		var total: int = game.ds.get_episode(def.file, 1).size() # touch loader
		var count: int = game.ds.level_definitions[def.file].size()
		for ep_num in range(1, count + 1):
			game.class_key = cls
			game.episode_num = ep_num
			game.player = null if ep_num == 1 or randf() < 0.3 else game.player
			game.begin_episode()
			game.close_modal()
			stats.episodes += 1
			var has_rivals := false
			for e in game.entities:
				if e.team == 2:
					has_rivals = true
			if has_rivals:
				stats.rival_eps += 1
			var steps := 500 if has_rivals else 160
			var start_lvl: int = game.lvl
			for i in steps:
				_step_actions(i)
				if game.state == "PLAYING":
					game.update(0.05)
					if i % 4 == 0:
						game.renderer.frame({
							"ds": game.ds, "lvl": game.lvl, "entities": game.entities, "projectiles": game.projectiles,
							"player": game.player, "ui": game.ui_state(),
						}, 0.05)
				if not game.player.alive and i % 25 == 0:
					await process_frame
				if i % 100 == 0:
					await process_frame
			stats.kills += game.ep_stats.kills
			stats.deaths += game.ep_stats.deaths
			game.keys.clear()
			if game.state != "PLAYING":
				if game.state == "MODAL":
					game.close_modal()
				elif game.state == "PERK":
					game.choose_perk(0)
			game.pending_perks = 0
			await process_frame
	print("LOGIC TEST DONE ", stats)
	quit()
