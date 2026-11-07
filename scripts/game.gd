# Copyright (c) Mark Longo 2026
extends Node
## Murk game: rules, AI, input and flow. Ports the arcade logic of the original (MurkThink.cpp, Murk.cpp)
## to a real-time loop with click-to-move, auto-fire, exploration fog and a minimap.

const SETTINGS_PATH := "user://murk_settings.json"
const SAVE_PATH := "user://murk_save.json"
const BEST_PATH := "user://murk_best.json"

const DEFAULT_SETTINGS := {
	"sfx": 1.0, "amb": 1.0, "aim": true, "shake": true, "hints": true, "muted": false, "autoStairs": true,
}

const MOVE_KEYS := {
	KEY_LEFT: Vector2i(-1, 0), KEY_A: Vector2i(-1, 0), KEY_KP_4: Vector2i(-1, 0),
	KEY_RIGHT: Vector2i(1, 0), KEY_D: Vector2i(1, 0), KEY_KP_6: Vector2i(1, 0),
	KEY_UP: Vector2i(0, -1), KEY_W: Vector2i(0, -1), KEY_KP_8: Vector2i(0, -1),
	KEY_DOWN: Vector2i(0, 1), KEY_S: Vector2i(0, 1), KEY_KP_2: Vector2i(0, 1),
	KEY_KP_7: Vector2i(-1, -1), KEY_KP_9: Vector2i(1, -1), KEY_KP_1: Vector2i(-1, 1), KEY_KP_3: Vector2i(1, 1),
}
const FIRE_KEYS := [KEY_SPACE, KEY_CTRL, KEY_J]
const STICK_SECTORS := [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]
const HERO_INT_KEYS := ["level", "level_base", "skill", "next_level_at", "max_hp", "armour", "rings", "dmin", "dmax",
	"max_shots", "pierce", "lifesteal"]
const HERO_FLOAT_KEYS := ["fire_cd", "tile_time"]

var audio: MurkAudio
var renderer: MurkRenderer
var ui: MurkUI
var ds := DungeonSystem.new()

var state := "LOADING"
var class_key := "fighter"
var episode_num := 1
var lvl := 1
var player: Entity = null
var entities: Array = []
var projectiles: Array = []
var home = null  # Vector3i(x, y, lvl)
var team2_lair = null  # Vector3i(x, y, lvl)
var deaths := 0

var mouse := {"pos": Vector2.ZERO, "left": false, "right": false, "left_on_enemy": false, "active": false}
var path: Array = []
var auto_use := false
var last_path_cell := ""
var transition := false
var wake_timer := 0.0
var pit_timer := 4.0
var minimap_timer := 0.0
var hint_cooldown := {}
var last_sound_at := {}
var step_flip := 0
var time := 0.0

var keys := {}
var tap = null
var attack_target: Entity = null
var hover_cell = null
var hover_entity = null
var repath_at := 0.0
var pad_state := {"ix": 0, "iy": 0, "fire": false, "aim_dir": 0, "prev": {}}
var last_click_time := 0
var last_click_cell := ""

var modal_action: Callable = Callable()
var modal_return := ""
var settings := {}
var pending_perks := 0
var pending_hero = null
var perk_choices: Array = []
var ep_stats := {"kills": 0, "time": 0.0, "deaths": 0, "items": 0}
var map_lvl := 1
var stair_cache := {}
var rivals_enabled := false
var dungeon_awake := false
var rivals_alerted := false


func _ready() -> void:
	randomize()
	audio = MurkAudio.new()
	add_child(audio)
	renderer = MurkRenderer.new()
	add_child(renderer)
	renderer.load_textures()
	ui = MurkUI.new()
	add_child(ui)
	ui.setup(self)

	settings = DEFAULT_SETTINGS.duplicate()
	var saved = _read_json(SETTINGS_PATH)
	if saved is Dictionary:
		for k in saved:
			if settings.has(k):
				settings[k] = saved[k]
	_apply_settings()

	var levels = _read_json("res://assets/levels.json")
	if levels is Dictionary:
		ds.load_level_defs(levels)
	else:
		push_warning("Could not load levels.json, using the built-in episode.")

	ui.show_splash(true)
	ui.set_splash_ready()
	state = "SPLASH"


# ---------- persistence ----------

func _read_json(file: String):
	if not FileAccess.file_exists(file):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(file))


func _write_json(file: String, value) -> void:
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(value))


func _apply_settings() -> void:
	audio.set_volumes(float(settings.sfx), float(settings.amb))
	audio.set_muted(bool(settings.muted))
	renderer.shake_enabled = bool(settings.shake)
	ui.sync_settings(settings, DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)


func save_settings() -> void:
	_write_json(SETTINGS_PATH, settings)
	_apply_settings()


func serialize_hero(p: Entity) -> Dictionary:
	var hero := {"perks": p.perks.duplicate()}
	for k in HERO_INT_KEYS + HERO_FLOAT_KEYS:
		hero[k] = p.get(k)
	return hero


func apply_hero(p: Entity, hero: Dictionary) -> void:
	for k in HERO_INT_KEYS:
		if hero.has(k):
			p.set(k, int(hero[k]))
	for k in HERO_FLOAT_KEYS:
		if hero.has(k):
			p.set(k, float(hero[k]))
	p.perks = {}
	for k in hero.get("perks", {}):
		p.perks[k] = int(hero.perks[k])
	p.hp = p.max_hp


func load_save():
	var s = _read_json(SAVE_PATH)
	if s is Dictionary and int(s.get("v", 0)) == 1 and Defs.CLASS_DEFS.has(s.get("classKey", "")) and s.get("hero") is Dictionary:
		return s
	return null


## Only episode boundaries are saved: a fresh run never overwrites an older save until it earns its first reward.
func save_progress() -> void:
	if episode_num <= 1 or player == null:
		return
	_write_json(SAVE_PATH, {
		"v": 1, "classKey": class_key, "episodeNum": episode_num, "deaths": deaths,
		"hero": serialize_hero(player),
	})


func record_best() -> bool:
	var best = _read_json(BEST_PATH)
	if not (best is Dictionary):
		best = {"episode": 0, "score": 0}
	var is_best: bool = episode_num > int(best.episode) or (episode_num == int(best.episode) and player.skill > int(best.score))
	if is_best:
		_write_json(BEST_PATH, {"episode": episode_num, "score": player.skill})
	return is_best


func format_time(sec: float) -> String:
	var s := int(sec)
	return "%d:%02d" % [s / 60, s % 60]


# ---------- menus ----------

func on_splash_click() -> void:
	audio.start_ambience()
	audio.play("button.wav")
	ui.show_splash(false)
	show_select_screen()


func show_select_screen() -> void:
	state = "SELECT"
	var best = _read_json(BEST_PATH)
	ui.show_select(true, class_key, load_save(), best if best is Dictionary else null)


func on_class_picked(key: String) -> void:
	class_key = key
	ui.select_class(key)
	audio.play("button.wav")


func on_select_confirm() -> void:
	audio.play("Spawn.wav")
	ui.show_select(false)
	ui.show_hud(true)
	start_new_game()


func on_continue() -> void:
	audio.play("Spawn.wav")
	ui.show_select(false)
	ui.show_hud(true)
	continue_game()


# ---------- game flow ----------

func start_new_game() -> void:
	episode_num = 1
	player = null
	pending_hero = null
	deaths = 0
	begin_episode()


func continue_game() -> void:
	var save = load_save()
	if save == null:
		start_new_game()
		return
	class_key = save.classKey
	episode_num = int(save.episodeNum)
	player = null
	pending_hero = save.hero
	deaths = int(save.get("deaths", 0))
	begin_episode()


func begin_episode() -> void:
	var def: Dictionary = Defs.CLASS_DEFS[class_key]
	var ep := ds.get_episode(def.file, episode_num)
	ds.build(ep)
	projectiles = []
	entities = []
	path = []
	attack_target = null
	stair_cache = {}
	ep_stats = {"kills": 0, "time": 0.0, "deaths": 0, "items": 0}
	team2_lair = null
	rivals_enabled = false
	dungeon_awake = false
	rivals_alerted = false
	ui.clear_log()

	var h: Vector3i = ds.random_floor(1)
	home = Vector3i(h.x, h.y, 1)
	ds.cell(h.x, h.y, 1).pad = def.pad

	if player == null:
		player = Entity.new({
			"kind": "player", "type": "player", "name": def.name, "image": def.image, "team": 1, "classKey": class_key,
			"x": h.x, "y": h.y, "lvl": 1, "hp": def.hp + randi() % 10,
			"armour": def.armour, "rings": def.rings, "dmin": def.dmin, "dmax": def.dmax, "shots": def.shots,
			"fireCd": def.fireCd, "tileTime": def.tileTime, "fireSound": def.fireSound,
		})
		player.level = 1
		player.next_level_at = 25
		if pending_hero != null:
			apply_hero(player, pending_hero)
		pending_hero = null
	else:
		player.teleport(h.x, h.y, 1)
		player.hp = player.max_hp
		player.protection = 0.0
		player.carrying = 0
		player.shots = 0
		player.fire_timer = 0.0
	player.dir = Defs.DIR_SE
	player.alive = true
	player.death_timer = 0.0
	player.hp = player.max_hp
	entities.append(player)

	spawn_population(ep)
	lvl = 1
	ui.set_prompt("")
	setup_level_view(true)
	update_hud()
	pit_timer = 3.0
	save_progress()
	show_objective(true)


func spawn_population(ep: Dictionary) -> void:
	var maxl := ds.maxlevel
	var monster_total: int = ep.beholders + ep.deathorb + ep.skeletons + ep.mouther + ep.ogre

	var lairs: Array = []
	for i in ceili(monster_total / 5.0):
		var l := mini(maxl - 1, Defs.rand_int(maxl - 1) + 2)
		var p = ds.random_floor(maxi(2, l))
		if p != null:
			ds.cell(p.x, p.y, p.z).pad = 4
			lairs.append(p)

	var spawn_monsters := func(key: String, count: int, speed: int) -> void:
		var mdef: Dictionary = Defs.MONSTER_DEFS[key]
		for i in count:
			var l := Defs.rand_int(maxl - 1) + 2
			var p = ds.random_floor(l, func(x, y): return is_far_from_home(x, y, l))
			if p == null:
				continue
			var e := Entity.new({
				"kind": "monster", "type": key, "name": mdef.name, "image": mdef.image, "team": 0, "x": p.x, "y": p.y, "lvl": l,
				"hp": mdef.hp + mini(30, episode_num - 1) + Defs.rand_int(3), "dmin": mdef.dmin, "dmax": mdef.dmax,
				"shots": mdef.shots, "fireCd": mdef.fireCd, "aggr": mdef.aggr,
				"tileTime": Defs.BASE_TILE_TIME * (1.0 + 0.55 * (maxi(1, speed) - 1)),
				"asleep": true,
				"fireSound": "fireball.wav" if mdef.image in [2, 4, 5, 9] else "throw.wav",
			})
			e.dir = 1 + Defs.rand_int(4)
			e.lair = lairs[entities.size() % lairs.size()] if not lairs.is_empty() else Vector3i(p.x, p.y, l)
			entities.append(e)
	spawn_monsters.call("beholder", ep.beholders, ep.bspeed)
	spawn_monsters.call("mouther", ep.mouther, ep.mspeed)
	spawn_monsters.call("ogre", ep.ogre, ep.ospeed)
	spawn_monsters.call("skeleton", ep.skeletons, ep.sspeed)
	spawn_monsters.call("deathorb", ep.deathorb, ep.dspeed)

	# Gametype 1 is a pure treasure hunt; rival squads (team 2) only exist in gametype 2.
	rivals_enabled = ep.gametype == 2
	var has_team2: bool = rivals_enabled and (
		(ep.fighter > 0 and ep.fteam == 2) or (ep.cleric > 0 and ep.cteam == 2) or
		(ep.thief > 0 and ep.tteam == 2) or (ep.wizard > 0 and ep.wteam == 2))
	if has_team2:
		var relic = ds.relic(2)
		var lair_spot = ds.random_floor(maxl, func(x, y): return relic == null or relic.lvl != maxl or relic.x != x or relic.y != y)
		if lair_spot == null:
			lair_spot = ds.random_floor(maxl)
		if lair_spot != null:
			team2_lair = Vector3i(lair_spot.x, lair_spot.y, lair_spot.z)
			ds.cell(lair_spot.x, lair_spot.y, lair_spot.z).pad = 5

	var state_ref := {"leader_spawned": false}
	var spawn_characters := func(key: String, count: int, team: int, speed: int) -> void:
		var cdef: Dictionary = Defs.CLASS_DEFS[key]
		var friendly := team == 1
		var is_team2 := team == 2
		# Team 2 characters are skipped unless this episode has rivals; unknown team values never spawn.
		if not friendly and not (is_team2 and has_team2):
			return
		for i in count:
			var l: int = 1 if friendly else (team2_lair.z if team2_lair != null else maxl)
			var p = null
			if friendly:
				p = ds.random_floor(l, func(x, y): return absi(x - home.x) + absi(y - home.y) > 2)
			elif is_team2 and team2_lair != null:
				if not state_ref.leader_spawned:
					p = Vector3i(team2_lair.x, team2_lair.y, team2_lair.z)
				else:
					p = ds.random_floor(l, func(x, y): return absi(x - team2_lair.x) + absi(y - team2_lair.y) <= 4)
					if p == null:
						p = ds.random_floor(l)
			else:
				p = ds.random_floor(l)
			if p == null:
				continue
			var is_leader: bool = is_team2 and not state_ref.leader_spawned
			if is_leader:
				state_ref.leader_spawned = true
			var e := Entity.new({
				"kind": "ally" if friendly else "rival", "type": key, "name": cdef.name, "image": cdef.image,
				"team": 1 if friendly else 2, "x": p.x, "y": p.y, "lvl": l,
				"hp": cdef.hp + Defs.rand_int(10) + episode_num, "armour": cdef.armour,
				"dmin": cdef.dmin, "dmax": cdef.dmax, "shots": cdef.shots, "fireCd": cdef.fireCd + 0.15, "aggr": 0.75,
				"tileTime": Defs.BASE_TILE_TIME * (1.0 + 0.55 * (maxi(1, speed) - 1)) * 0.9,
				"asleep": false, "fireSound": cdef.fireSound, "isLeader": is_leader,
			})
			e.lair = Vector3i(team2_lair.x, team2_lair.y, team2_lair.z) if (is_team2 and team2_lair != null) else Vector3i(p.x, p.y, l)
			entities.append(e)
	spawn_characters.call("fighter", ep.fighter, ep.fteam, ep.fspeed)
	spawn_characters.call("cleric", ep.cleric, ep.cteam, ep.cspeed)
	spawn_characters.call("thief", ep.thief, ep.tteam, ep.tspeed)
	spawn_characters.call("wizard", ep.wizard, ep.wteam, ep.wspeed)


func is_far_from_home(x: int, y: int, l: int) -> bool:
	return l != 1 or absi(x - home.x) + absi(y - home.y) > 6


func setup_level_view(snap: bool) -> void:
	renderer.build_level(ds, lvl)
	ds.reveal(lvl, player.x, player.y)
	if snap:
		renderer.cam_snap = true
	update_hud()


# ---------- stairs and falling ----------

func use_stairs() -> void:
	var p := player
	if state != "PLAYING" or transition or not p.alive or p.is_moving():
		return
	var c := ds.cell(p.x, p.y, lvl)
	if c.type != DungeonSystem.T_STAIR:
		hint("stairs", "There is no ladder here.")
		return
	if c.stair == "down":
		change_level(lvl + 1, p.x, p.y, "You climb down to floor")
	elif lvl > 1:
		change_level(lvl - 1, p.x, p.y, "You climb up to floor")


func change_level(target: int, x: int, y: int, msg: String, fall: bool = false) -> void:
	if transition:
		return
	transition = true
	path = []
	attack_target = null
	auto_use = false
	ui.fade(true)
	audio.play("Protection.wav" if fall else "walk.wav", 0.5)
	await get_tree().create_timer(0.26).timeout
	var from_lvl := lvl
	var followers: Array = []
	for e in entities:
		if e.kind == "ally" and e.alive and not e.asleep and e.lvl == from_lvl \
				and absi(e.x - player.x) + absi(e.y - player.y) <= 5:
			followers.append(e)
	projectiles = []
	player.shots = 0
	player.teleport(x, y, target)
	for e in entities:
		if e != player:
			e.shots = 0
	for ally in followers:
		var spot = free_spot_near(x, y, target, ally)
		if spot != null:
			ally.teleport(spot.x, spot.y, target)
			ally.stair_cd = 3.0
			ally.rest_timer = 0.3
	lvl = target
	setup_level_view(true)
	on_player_arrive()
	toast("%s %d." % [msg, target])
	ui.fade(false)
	await get_tree().create_timer(0.2).timeout
	transition = false


## Nearest walkable cell to (x, y) on `l` that no living entity occupies.
func free_spot_near(x: int, y: int, l: int, ignore: Entity):
	for r in range(0, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var nx := x + dx
				var ny := y + dy
				if ds.walkable(nx, ny, l) and entity_at(nx, ny, l, ignore) == null:
					return Vector2i(nx, ny)
	return null


## Moves a non-player entity through the stairs at (sx, sy) on its level to the adjoining level.
func entity_take_stairs(e: Entity, sx: int, sy: int) -> bool:
	var c := ds.cell(sx, sy, e.lvl)
	if c.type != DungeonSystem.T_STAIR:
		return false
	var target := e.lvl + 1 if c.stair == "down" else e.lvl - 1
	if target < 1 or target > ds.maxlevel:
		return false
	var spot = free_spot_near(sx, sy, target, e)
	if spot == null:
		return false
	if e.lvl == lvl:
		play_at("walk.wav", e, 0.4)
	e.teleport(spot.x, spot.y, target)
	if e.carrying != 0:
		var r = ds.relic(e.carrying)
		if r != null:
			r.lvl = target
			r.x = spot.x
			r.y = spot.y
	e.shots = 0
	e.windup = 0.0
	e.stair_cd = 4.0
	e.rest_timer = 0.4
	e.stair_wander = ""
	if target == lvl:
		play_at("walk.wav", e, 0.4)
		pop_text(e, "!", "#ffd24a")
	return true


func get_team2_leader():
	for e in entities:
		if e.team == 2 and e.is_leader and e.alive:
			return e
	for e in entities:
		if e.team == 2 and e.is_leader:
			return e
	for e in entities:
		if e.team == 2 and e.alive:
			return e
	for e in entities:
		if e.team == 2:
			return e
	return null


## The leader seeks the treasure; if the leader is down, every surviving rival takes over that role.
func is_team2_lead(e: Entity) -> bool:
	var leader = get_team2_leader()
	return e == leader or leader == null or not leader.alive


func relic_at_lair(relic, e: Entity) -> bool:
	return relic != null and relic.carrier == null and e.lair != null \
		and relic.lvl == e.lair.z and relic.x == e.lair.x and relic.y == e.lair.y


func get_team2_target_lvl(e: Entity) -> int:
	var relic = ds.relic(2)
	if e.carrying == 2:
		return e.lair.z if e.lair != null else e.lvl
	if relic != null and relic.carrier != null and relic.carrier.team != 2:
		return relic.carrier.lvl
	var leader = get_team2_leader()
	if is_team2_lead(e):
		if relic != null and relic.carrier == null and relic.lvl > 0:
			if relic_at_lair(relic, e):
				return e.lair.z
			return relic.lvl
		return e.lair.z if e.lair != null else e.lvl
	else:
		if leader != null and leader.alive:
			return leader.lvl
		if relic != null and relic.carrier == null and relic.lvl > 0:
			return relic.lvl
		return e.lair.z if e.lair != null else e.lvl


## Squad priority for tight tunnels: treasure carrier > leader > escort.
func team2_rank(e: Entity) -> int:
	if e.carrying == 2:
		return 2
	return 1 if is_team2_lead(e) else 0


## Steps a rival to the adjacent cell `next`, trading places with a lower-ranked idle squadmate blocking a
## one-tile tunnel. Equal ranks never swap, so two rivals cannot ping-pong. Returns true if it moved.
func team2_push_through(e: Entity, next: Vector2i, animate: bool) -> bool:
	var occ = entity_at(next.x, next.y, e.lvl, e)
	if occ != null and not (occ.team == 2 and not occ.is_moving() and team2_rank(e) > team2_rank(occ)):
		return false
	var from_x := e.x
	var from_y := e.y
	var d := Defs.dir_from_delta(next.x - from_x, next.y - from_y)
	if animate:
		e.start_move(next.x, next.y, d)
		if occ != null:
			occ.start_move(from_x, from_y, Defs.dir_from_delta(from_x - next.x, from_y - next.y))
	else:
		e.dir = d
		e.teleport(next.x, next.y, e.lvl)
		if occ != null:
			occ.teleport(from_x, from_y, e.lvl)
	return true


## Where an off-screen rival walks on its current floor (simulated, since it is not rendered).
func team2_off_level_goal(e: Entity):
	var relic = ds.relic(2)
	if e.carrying == 2:
		return e.lair if (e.lair != null and e.lair.z == e.lvl) else null
	if relic != null and relic.carrier == null and relic.lvl == e.lvl and not relic_at_lair(relic, e) and is_team2_lead(e):
		return Vector2i(relic.x, relic.y)
	var leader = get_team2_leader()
	if leader != null and leader.alive and leader != e and leader.lvl == e.lvl \
			and absi(leader.x - e.x) + absi(leader.y - e.y) > 3:
		return leader
	return null


func check_entity_relic_pickup(e: Entity) -> void:
	if not e.alive or e.carrying != 0:
		return
	for relic in ds.relics:
		if relic.carrier != null or relic.lvl != e.lvl or relic.x != e.x or relic.y != e.y:
			continue
		if relic.drop_cooldown > 0.0:
			continue
		if relic.id == 2 and e.team == 2:
			# Treasure already secured in their own lair stays put; rivals guard it instead of re-carrying it.
			if relic_at_lair(relic, e):
				continue
			relic.carrier = e
			e.carrying = relic.id
			play_at("treasure.wav", e, 0.7)
			if e.lvl == lvl:
				var w := renderer.grid_to_world(e.x, e.y)
				renderer.burst(w.x, w.y - 30, 0x66bbff, 18, 90, 0.7, 14)
				pop_text(e, "TREASURE!", "#66bbff")
			toast("%s from Team 2 seized the blue treasure!" % e.name, "warn")
			return


func check_entity_lair_arrival(e: Entity) -> void:
	if not e.alive or e.carrying != 2 or e.lair == null:
		return
	if e.lvl == e.lair.z and e.x == e.lair.x and e.y == e.lair.y:
		drop_relic(e, false)
		play_at("treasure.wav", e, 0.7)
		if e.lvl == lvl:
			var w := renderer.grid_to_world(e.x, e.y)
			renderer.burst(w.x, w.y - 30, 0x66bbff, 20, 100, 0.8, 16)
			pop_text(e, "SECURED!", "#66bbff")
		toast("Rivals secured the blue treasure in their lair! Infiltrate and take it back!", "warn")


## Awake creatures on other floors keep playing: they walk to the nearest stairs that lead toward their objective.
func update_off_level(e: Entity, dt: float) -> void:
	if e.asleep or e.stair_cd > 0.0:
		e.stair_timer = 0.0
		return
	var target_lvl := -1
	if e.team == 2:
		target_lvl = get_team2_target_lvl(e)
	elif e.kind == "ally":
		target_lvl = player.lvl
	else:
		var diff := player.lvl - e.lvl
		if absi(diff) == 1 and absi(e.x - player.x) + absi(e.y - player.y) <= 14:
			target_lvl = player.lvl

	if target_lvl == -1 or target_lvl == e.lvl:
		e.stair_timer = 0.0
		if e.team == 2:
			var goal = team2_off_level_goal(e)
			if goal != null and (goal.x != e.x or goal.y != e.y):
				e.off_step_timer -= dt
				if e.off_step_timer <= 0.0:
					e.off_step_timer = e.tile_time
					var blocked := func(x, y): return entity_at(x, y, e.lvl, e) != null
					var pth = ds.find_path(e.lvl, e.x, e.y, goal.x, goal.y, blocked, 500)
					if pth == null:
						pth = ds.find_path(e.lvl, e.x, e.y, goal.x, goal.y, Callable(), 500)
					if pth != null and not pth.is_empty() and not (goal is Entity and pth.size() == 1):
						team2_push_through(e, pth[0], false)
			check_entity_relic_pickup(e)
			check_entity_lair_arrival(e)
		return

	var kind := "down" if target_lvl - e.lvl > 0 else "up"
	if e.stair_timer == 0.0:
		var best = null
		var best_d := 1000000
		for s in ds.find_stairs(e.lvl, kind):
			var d: int = absi(s.x - e.x) + absi(s.y - e.y)
			if d < best_d:
				best_d = d
				best = s
		if best == null:
			return
		e.stair_goal = best
		e.stair_timer = maxf(0.5, best_d * e.tile_time * 1.2)
		return
	e.stair_timer -= dt
	if e.stair_timer > 0.0:
		return
	var s = e.stair_goal
	e.stair_goal = null
	if s != null:
		e.x = s.x
		e.y = s.y
		if not entity_take_stairs(e, s.x, s.y):
			e.stair_cd = 1.5


## Walks toward the closest stairs of the given kind; returns true if it acted.
func seek_stairs(e: Entity, kind: String) -> bool:
	if e.stair_cd > 0.0:
		return false
	var c := ds.cell(e.x, e.y, e.lvl)
	if c.type == DungeonSystem.T_STAIR and c.stair == kind:
		return entity_take_stairs(e, e.x, e.y)
	var blocked := func(x, y): return entity_at(x, y, e.lvl, e) != null
	var best = null
	for s in ds.find_stairs(e.lvl, kind):
		var pth = ds.find_path(e.lvl, e.x, e.y, s.x, s.y, blocked, 300)
		if pth != null and not pth.is_empty() and (best == null or pth.size() < best.size()):
			best = pth
	if best == null and e.team == 2:
		for s in ds.find_stairs(e.lvl, kind):
			var pth = ds.find_path(e.lvl, e.x, e.y, s.x, s.y, Callable(), 300)
			if pth != null and not pth.is_empty() and (best == null or pth.size() < best.size()):
				best = pth
		return best != null and team2_push_through(e, best[0], true)
	if best == null:
		return false
	return try_step(e, Defs.dir_from_delta(best[0].x - e.x, best[0].y - e.y))


func update_pits(dt: float) -> void:
	var ep := ds.current_episode
	if not ep.is_empty() and int(ep.get("pits", 0)) > 0:
		pit_timer -= dt
		var active := 0
		for pit in ds.pits:
			if pit.active:
				active += 1
		if pit_timer <= 0.0:
			pit_timer = 3.0 + randf() * 4.0
			var max_pit := int(ep.get("maxpit", 6))
			if active < mini(6, max_pit if max_pit > 0 else 6):
				spawn_pit()
	for pit in ds.pits:
		if not pit.active:
			continue
		pit.age += dt
		pit.frame = int(floor(pit.age / 0.083)) + 1
		if pit.frame >= 36:
			pit.active = false
	var p := player
	if not p.alive or p.is_moving() or transition or p.lvl >= ds.maxlevel:
		return
	for pit in ds.pits:
		if pit.active and pit.lvl == lvl and pit.x == p.x and pit.y == p.y and pit.frame >= 18 and pit.frame <= 29:
			pit.active = false
			toast("The floor gives way beneath you!", "warn")
			renderer.add_shake(8.0)
			change_level(lvl + 1, p.x, p.y, "You fall to floor", true)
			return


func spawn_pit() -> void:
	for tries in 60:
		var l := Defs.rand_int(ds.maxlevel - 1) + 1
		var x := Defs.rand_int(ds.n) + 1
		var y := Defs.rand_int(ds.n) + 1
		if not ds.is_free_floor(x, y, l) or not ds.walkable(x, y, l + 1):
			continue
		var taken := false
		for p in ds.pits:
			if p.active and p.x == x and p.y == y and p.lvl == l:
				taken = true
				break
		if taken:
			continue
		var pit = null
		for p in ds.pits:
			if not p.active:
				pit = p
				break
		if pit == null:
			pit = DungeonSystem.Pit.new()
			ds.pits.append(pit)
		pit.x = x
		pit.y = y
		pit.lvl = l
		pit.frame = 1
		pit.age = 0.0
		pit.active = true
		return


# ---------- player actions ----------

func entity_at(x: int, y: int, l: int, ignore: Entity = null):
	for e in entities:
		if e != ignore and e.alive and e.lvl == l and e.x == x and e.y == y:
			return e
	return null


func fire(e: Entity, dir: int) -> bool:
	if not e.alive or e.fire_timer > 0.0 or e.shots >= e.max_shots:
		return false
	e.dir = dir
	e.fire_timer = e.fire_cd
	e.shots += 1
	e.shot_flash = 0.1
	projectiles.append(Projectile.new(e, dir))
	play_at(e.fire_sound if e.fire_sound != "" else "throw.wav", e, 0.5)
	return true


func use_ring() -> void:
	var p := player
	if state != "PLAYING" or not p.alive:
		return
	if p.protection > 0.0:
		hint("ring", "The ring is already protecting you.")
		return
	if p.rings <= 0:
		hint("ring", "You have no Rings of Protection.")
		return
	p.rings -= 1
	p.protection = 7.0
	audio.play("Protection.wav", 0.6)
	audio.play("tcleric.wav", 0.25)
	toast("Ring of Protection! You are invulnerable.", "good")
	update_hud()


func drop_relic(ent: Entity, voluntary: bool) -> void:
	if ent == null or ent.carrying == 0:
		if voluntary:
			hint("drop", "You are not carrying a relic.")
		return
	var relic = ds.relic(ent.carrying)
	ent.carrying = 0
	if relic != null:
		relic.carrier = null
		relic.x = ent.x
		relic.y = ent.y
		relic.lvl = ent.lvl
		relic.drop_cooldown = 1.5 if voluntary else 0.6
		relic.voluntary_drop = voluntary
	if voluntary:
		toast("You set down the relic.")
		audio.play("button.wav")
	update_hud()


# ---------- arrival, pickups, relics ----------

func on_player_arrive() -> void:
	var p := player
	ds.reveal(lvl, p.x, p.y)

	var c := ds.cell(p.x, p.y, lvl)
	var cdef: Dictionary = Defs.CLASS_DEFS[class_key]
	match c.item:
		"e":
			if p.hp >= p.max_hp:
				hint("elixir", "You are already at full health.")
			else:
				var gain := mini(p.max_hp - p.hp, 10 + p.level * 2)
				p.hp += gain
				pop_text(p, "+%d" % gain, "#7dff9b")
				consume_item(c, "Elixir restores your health.", "item.wav")
		"a":
			if not cdef.wearsArmour:
				hint("armour", "This armour does not suit a spellcaster.")
			else:
				p.armour += 5
				pop_text(p, "+5 armour", "#9fd8ff")
				consume_item(c, "You don the armour (+5 armour).", "item.wav")
		"s":
			if not cdef.readsScrolls:
				hint("scroll", "Only spellcasters can read this scroll.")
			else:
				p.armour += 5
				pop_text(p, "+5 ward", "#9fd8ff")
				consume_item(c, "The scroll weaves a protective ward (+5 armour).", "item.wav")
		"r":
			p.rings += 1
			pop_text(p, "+1 ring", "#ffe27a")
			consume_item(c, "A Ring of Protection! (press R to use)", "item.wav")

	for relic in ds.relics:
		if relic.carrier != null or relic.lvl != lvl or relic.x != p.x or relic.y != p.y:
			continue
		if relic.drop_cooldown > 0.0:
			continue
		if p.carrying != 0:
			hint("carry", "You can only carry one relic at a time.")
			continue
		player_take_relic(relic)

	if p.carrying != 0 and home != null and p.lvl == home.z and p.x == home.x and p.y == home.y:
		deliver_relic()

	if c.type == DungeonSystem.T_STAIR:
		ui.set_prompt("Press E to climb down" if c.stair == "down" else "Press E to climb up")
	else:
		ui.set_prompt("")
	update_hud()


func player_take_relic(relic) -> void:
	var p := player
	relic.carrier = p
	p.carrying = relic.id
	audio.play("treasure.wav", 0.7)
	var w := renderer.grid_to_world(p.x, p.y)
	renderer.burst(w.x, w.y - 30, 0xff6655 if relic.id == 1 else 0x66bbff, 18, 90, 0.7, 14)
	if relic.id == 2:
		if not dungeon_awake:
			dungeon_awake = true
			toast("You seized the blue treasure! Carry it back to your pad - the dungeon awakens!", "good")
			wake_all()
		else:
			toast("You have the blue treasure again! Get it home!", "good")
	else:
		toast("You took the treasure. Return it to your pad for a bonus.", "good")
	update_hud()


## Lets a standing player re-take a relic knocked from their hands once its short drop cooldown ends.
func check_player_relic_retake() -> void:
	var p := player
	if not p.alive or p.is_moving() or p.carrying != 0 or transition:
		return
	for relic in ds.relics:
		if relic.carrier != null or relic.voluntary_drop or relic.drop_cooldown > 0.0:
			continue
		if relic.lvl != p.lvl or relic.x != p.x or relic.y != p.y:
			continue
		player_take_relic(relic)
		return


func consume_item(c: DungeonSystem.Cell, msg: String, sound: String) -> void:
	c.item = ""
	ep_stats.items += 1
	toast(msg)
	audio.play(sound, 0.5)
	var w := renderer.grid_to_world(player.x, player.y)
	renderer.burst(w.x, w.y - 24, 0xfff0a0, 12, 70, 0.6, 10)


func deliver_relic() -> void:
	var p := player
	var id := p.carrying
	var relic = ds.relic(id)
	p.carrying = 0
	if relic != null:
		relic.carrier = null
		relic.lvl = 0
	if id == 1:
		add_skill(30)
		toast("Relic secured! +30 skill.", "good")
		audio.play("win.wav", 0.6)
		update_hud()
		return
	audio.play("win.wav", 0.8)
	p.armour += 30
	p.rings += 3
	add_skill(30)
	update_hud()
	var s := ep_stats
	var best := record_best()
	modal_action = func():
		episode_num += 1
		begin_episode()
	show_modal(
		"EPISODE COMPLETE",
		"Monsters slain: [b]%d[/b]     Time: [b]%s[/b]\nTimes fallen: [b]%d[/b]     Hero level: [b]%d[/b]\n\n" % [s.kills, format_time(s.time), s.deaths, p.level] +
		"[color=#b3a6c9]Reward: +30 skill, +30 armour, +3 Rings of Protection.[/color]%s\n" % ["  [color=#ffd45a][b]New best![/b][/color]" if best else ""] +
		"[color=#b3a6c9]Next: Episode %d[/color]" % (episode_num + 1),
		"ONWARD")


func wake_all() -> void:
	renderer.add_shake(10.0)
	audio.play("DRAGON.WAV", 0.5)
	for e in entities:
		if e.asleep:
			e.asleep = false


# ---------- combat ----------

func hostile(a: Entity, b: Entity) -> bool:
	if a == b or not a.alive or not b.alive:
		return false
	if a.is_monster():
		return not b.is_monster()
	if b.is_monster():
		return true
	return a.team != b.team


func update_projectiles(dt: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Projectile = projectiles[i]
		if p.lvl == lvl:
			p.t += dt * p.speed
			var v: Vector2i = Defs.DIR_VEC[p.dir]
			while p.alive and p.t >= 1.0:
				p.t -= 1.0
				var nx := p.x + v.x
				var ny := p.y + v.y
				if not ds.walkable(nx, ny, p.lvl):
					missile_spark(p)
					p.alive = false
					break
				p.x = nx
				p.y = ny
				p.travelled += 1
				if p.travelled >= p.max_range:
					p.alive = false
					break
				missile_hit(p)
			if p.alive:
				missile_hit(p)
			if p.alive and randf() < dt * 40.0:
				var rc := p.render_cell()
				var w := renderer.grid_to_world(rc.x, rc.y)
				renderer.spawn_particle(w.x + (randf() - 0.5) * 6.0, w.y - 30.0 + (randf() - 0.5) * 6.0, 0.0, -8.0, 0.35, 10.0,
					MurkRenderer.TRAIL_COLORS.get(p.kind, 0xffffff), -6.0)
		else:
			p.alive = false
		if not p.alive:
			p.owner.shots = maxi(0, p.owner.shots - 1)
			projectiles.remove_at(i)


func missile_spark(p: Projectile) -> void:
	var rc := p.render_cell()
	var w := renderer.grid_to_world(rc.x, rc.y)
	renderer.burst(w.x, w.y - 28, 0xffcc88, 6, 50, 0.3, 8)


func missile_hit(p: Projectile) -> void:
	for e in entities:
		if e.lvl != p.lvl or e.x != p.x or e.y != p.y or not hostile(p.owner, e):
			continue
		if p.hit_ids.has(e.id):
			continue
		apply_hit(p.owner, e, p.dir)
		if p.pierce > 0:
			p.pierce -= 1
			p.hit_ids[e.id] = true
			continue
		p.alive = false
		return


func apply_hit(attacker: Entity, target: Entity, _dir: int) -> void:
	var w := renderer.grid_to_world(target.x, target.y)
	var dmg := attacker.roll_damage()
	var res := target.take_hit(dmg)

	if res.blocked:
		pop_text(target, "BLOCKED", "#8ae8ff")
		audio.play("impact.wav", 0.3)
		renderer.burst(w.x, w.y - 34, 0x88ddff, 8, 70, 0.35, 9)
		return

	play_at("impact.wav", target, 0.5)
	renderer.burst(w.x, w.y - 34, 0xff5533, 10, 80, 0.45, 10)
	pop_text(target, "-%d" % dmg, "#ff6a5a" if target == player else "#ffffff")
	if target.asleep:
		target.asleep = false

	if target.carrying != 0:
		drop_relic(target, false)
		if target == player:
			toast("You dropped the blue treasure!", "warn")
		elif target.team == 2:
			toast("%s dropped the blue treasure!" % target.name, "warn")
	if target == player:
		audio.play("ouch.wav", 0.7)
		renderer.add_shake(6.0)
		ui.flash_hit()
		update_hud()

	if target.hp <= 0:
		kill(target, attacker)


func add_skill(n: int) -> void:
	var p := player
	p.skill += n
	while p.skill >= p.next_level_at:
		p.level += 1
		p.level_base = p.next_level_at
		p.next_level_at += 40 + p.level * 10
		p.max_hp += 10
		p.hp = mini(p.max_hp, p.hp + 10)
		toast("LEVEL %d! Choose a new talent." % p.level, "good")
		audio.play("win.wav", 0.5)
		var w := renderer.grid_to_world(p.x, p.y)
		renderer.burst(w.x, w.y - 30, 0xffe070, 26, 120, 0.9, 14)
		pending_perks += 1


func kill(target: Entity, killer: Entity) -> void:
	target.alive = false
	target.hp = 0
	target.death_timer = 0.8
	var w := renderer.grid_to_world(target.x, target.y)
	renderer.burst(w.x, w.y - 30, 0xcc2222, 16, 90, 0.7, 12)
	if target.carrying != 0:
		drop_relic(target, false)
		if target.team == 2:
			toast("%s fell and dropped the blue treasure!" % target.name, "good")

	if target == player:
		handle_player_death()
		return
	play_at("die.wav" if target.is_monster() else "dead.wav", target, 0.6)

	if killer == player or (killer != null and killer.team == 1):
		var reward := maxi(2, roundi(target.max_hp / 3.0))
		if killer == player:
			pop_text(target, "+%d" % reward, "#ffe27a")
			ep_stats.kills += 1
			add_skill(reward)
			if killer.lifesteal > 0 and killer.hp < killer.max_hp:
				killer.hp = mini(killer.max_hp, killer.hp + killer.lifesteal)
				pop_text(killer, "+%d" % killer.lifesteal, "#7dff9b")
			update_hud()

	var c := ds.cell(target.x, target.y, target.lvl)
	if target.is_monster() and c.type == DungeonSystem.T_FLOOR and c.item == "" and c.pad < 0 and randf() < 0.7:
		var r := Defs.rand_int(3)
		c.item = "a" if r == 0 else ("s" if r == 1 else "e")

	target.respawn_timer = 35.0 + randf() * 25.0 if target.is_monster() else 14.0


func handle_player_death() -> void:
	deaths += 1
	ep_stats.deaths += 1
	audio.play("dead.wav", 0.8)
	path = []
	attack_target = null
	clear_input()
	update_hud()
	var p := player
	await get_tree().create_timer(0.9).timeout
	if p != player or p.alive:
		return
	modal_action = func(): respawn_player()
	show_modal("YOU HAVE FALLEN",
		"Hero level: [b]%d[/b]     Score: [b]%d[/b]\nSlain this episode: [b]%d[/b]     Floor: [b]%d / %d[/b]\n\n" % [
			p.level, p.skill, ep_stats.kills, lvl, ds.maxlevel] +
		"[color=#b3a6c9]You rise at your home pad with full health. The dungeon and everything you found stays as you left it.[/color]",
		"RISE AGAIN")


## Death is a setback, not a reset: return to the home pad with full health and brief protection.
func respawn_player() -> void:
	var p := player
	p.alive = true
	p.death_timer = 0.0
	p.hp = p.max_hp
	p.carrying = 0
	p.shots = 0
	p.fire_timer = 0.3
	p.protection = 3.0
	p.teleport(home.x, home.y, 1)
	projectiles = []
	path = []
	attack_target = null
	lvl = 1
	setup_level_view(true)
	on_player_arrive()
	toast("You rise again at your home pad.", "good")


func respawn_entity(e: Entity) -> bool:
	var lair: Vector3i = e.lair if e.lair != null else e.spawn
	if entity_at(lair.x, lair.y, lair.z, e) != null:
		return false
	if lair.z == lvl and absi(lair.x - player.x) + absi(lair.y - player.y) < 4:
		return false
	e.hp = e.max_hp
	e.alive = true
	e.asleep = false
	e.shots = 0
	e.fire_timer = 0.5
	e.teleport(lair.x, lair.y, lair.z)
	if lair.z == lvl:
		var w := renderer.grid_to_world(lair.x, lair.y)
		renderer.burst(w.x, w.y - 28, 0xaa44ff, 14, 70, 0.6, 12)
		play_at("Spawn.wav", e, 0.5)
	return true


# ---------- AI ----------

func wake_nearby() -> void:
	var p := player
	for e in entities:
		if not e.asleep or not e.alive or e.lvl != lvl:
			continue
		if absi(e.x - p.x) <= 3 and absi(e.y - p.y) <= 3 and ds.find_path(lvl, e.x, e.y, p.x, p.y, Callable(), 120) != null:
			e.asleep = false
			e.rest_timer = 0.4
			pop_text(e, "!", "#ffd24a")
			var mdef = Defs.MONSTER_DEFS.get(e.type)
			if mdef != null:
				play_at(mdef.wake, e, 0.5)


func find_target(e: Entity):
	for dir in Defs.DIRS:
		var cells := ds.cast_line(e.lvl, e.x, e.y, dir, 9)
		for c in cells:
			var other = entity_at(c.x, c.y, e.lvl, e)
			if other == null:
				continue
			if hostile(e, other):
				return {"dir": dir, "other": other, "dist": absi(c.x - e.x) + absi(c.y - e.y)}
			break
	return null


func nearest_hostile(e: Entity, range_: int):
	var best = null
	var best_d := range_ + 1
	for o in entities:
		if o.lvl != e.lvl or not hostile(e, o):
			continue
		var d: int = absi(o.x - e.x) + absi(o.y - e.y)
		if d < best_d:
			best_d = d
			best = o
	return best


func think(e: Entity) -> void:
	if e.asleep or e.windup > 0.0:
		return
	var shot = find_target(e)
	if shot != null and e.fire_timer <= 0.0 and e.shots < e.max_shots and e.rest_timer <= 0.0:
		e.dir = shot.dir
		if randf() < e.aggr:
			# A short, visible wind-up gives the player a moment to step out of the firing line.
			e.windup = 0.26 if e.is_monster() else 0.1
			e.windup_dir = shot.dir
		e.rest_timer = 0.12 + randf() * 0.25
		return
	if shot != null and e.rest_timer > 0.0:
		return

	var goal = null
	if e.kind == "ally":
		var foe = nearest_hostile(e, 8)
		var d := absi(player.x - e.x) + absi(player.y - e.y)
		if foe != null and d < 9:
			goal = foe
		elif d > 3 and player.lvl == e.lvl:
			goal = player
	elif e.team == 2:
		var relic = ds.relic(2)
		var leader = get_team2_leader()
		var is_leader := is_team2_lead(e)

		if e.carrying == 2:
			# Whoever holds the treasure brings it back to the lair
			if e.lair != null:
				if e.lvl != e.lair.z:
					if seek_stairs(e, "down" if e.lair.z > e.lvl else "up"):
						return
				elif e.x == e.lair.x and e.y == e.lair.y:
					check_entity_lair_arrival(e)
					return
				else:
					goal = Vector2i(e.lair.x, e.lair.y)
		elif is_leader:
			if relic != null and relic.carrier != null and relic.carrier.team != 2:
				# Enemy has the treasure, hunt them down
				if relic.carrier.lvl != e.lvl:
					if seek_stairs(e, "down" if relic.carrier.lvl > e.lvl else "up"):
						return
				else:
					goal = relic.carrier
			elif relic != null and relic.carrier == null and relic.lvl > 0:
				if relic_at_lair(relic, e):
					# Guard the lair and treasure, but also hunt nearby monsters and foes
					var foe = nearest_hostile(e, 12)
					if foe != null:
						goal = foe
					else:
						var d_lair: int = absi(e.x - e.lair.x) + absi(e.y - e.lair.y)
						if d_lair > 3:
							goal = Vector2i(e.lair.x, e.lair.y)
				else:
					# Search for blue treasure
					if relic.lvl != e.lvl:
						if seek_stairs(e, "down" if relic.lvl > e.lvl else "up"):
							return
					elif e.x == relic.x and e.y == relic.y:
						check_entity_relic_pickup(e)
						return
					else:
						var foe = nearest_hostile(e, 3)
						goal = foe if foe != null else Vector2i(relic.x, relic.y)
			else:
				# Hunt monsters and non-friends
				goal = nearest_hostile(e, 14)
		elif leader != null and leader.alive:
			# Follower on Team 2: hover around leader, find monsters and other non-friend players
			if leader.lvl != e.lvl:
				if seek_stairs(e, "down" if leader.lvl > e.lvl else "up"):
					return
			else:
				var foe = nearest_hostile(e, 8)
				var d_leader: int = absi(leader.x - e.x) + absi(leader.y - e.y)
				if foe != null and d_leader < 10:
					goal = foe
				elif d_leader > 3:
					goal = leader
				elif foe != null:
					goal = foe
	else:
		goal = nearest_hostile(e, 14)

	if goal != null:
		e.stair_wander = ""
		# Creatures are engaged from range; tile goals (treasure, lair) must actually be stepped onto.
		var creature_goal: bool = goal is Entity
		var blocked := func(x, y): return entity_at(x, y, e.lvl, e) != null
		var pth = ds.find_path(e.lvl, e.x, e.y, goal.x, goal.y, blocked, 500)
		if pth != null and (pth.size() > 1 or (not creature_goal and pth.size() == 1)):
			var step: Vector2i = pth[0]
			if try_step(e, Defs.dir_from_delta(step.x - e.x, step.y - e.y)):
				return
		elif pth != null and pth.size() == 1:
			e.dir = Defs.dir_from_delta(goal.x - e.x, goal.y - e.y)
			return
		elif pth == null and e.team == 2:
			var open = ds.find_path(e.lvl, e.x, e.y, goal.x, goal.y, Callable(), 500)
			if open != null and not open.is_empty() and (open.size() > 1 or not creature_goal) and team2_push_through(e, open[0], true):
				return
	if e.is_monster() and e.stair_cd <= 0.0:
		if e.stair_wander == "" and randf() < 0.04:
			var kinds: Array = []
			if e.lvl > 1:
				kinds.append("up")
			if e.lvl < ds.maxlevel:
				kinds.append("down")
			if not kinds.is_empty():
				e.stair_wander = kinds[Defs.rand_int(kinds.size())]
		if e.stair_wander != "":
			if seek_stairs(e, e.stair_wander):
				return
			e.stair_wander = ""
	if randf() < 0.55:
		try_step(e, 1 + Defs.rand_int(4))
	else:
		e.rest_timer = 0.2 + randf() * 0.4


func update_entities(dt: float) -> void:
	for r in ds.relics:
		if r.drop_cooldown > 0.0:
			r.drop_cooldown -= dt
	for e in entities:
		if not e.alive:
			if e.death_timer > 0.0:
				e.death_timer -= dt
			if e != player:
				e.respawn_timer -= dt
				if e.respawn_timer <= 0.0:
					if not respawn_entity(e):
						e.respawn_timer = 2.0
			continue
		if e.stair_cd > 0.0:
			e.stair_cd -= dt
		var arrived: bool = e.update(dt)
		if e.carrying != 0:
			var r = ds.relic(e.carrying)
			if r != null:
				r.lvl = e.lvl
				r.x = e.x
				r.y = e.y
		if e == player:
			if arrived:
				on_player_arrive()
				# Start the next step in the same frame and carry leftover time so held movement never stutters.
				update_player_control()
				if e.is_moving():
					e.advance(e.overflow)
			check_player_relic_retake()
			continue
		if arrived and e.team == 2:
			check_entity_relic_pickup(e)
			check_entity_lair_arrival(e)
		if e.lvl != lvl or e.asleep:
			e.windup = 0.0
			if e.lvl != lvl:
				update_off_level(e, dt)
			continue
		if e.windup > 0.0:
			e.windup -= dt
			if e.windup <= 0.0:
				e.windup = 0.0
				fire(e, e.windup_dir)
		e.think_timer -= dt
		if e.think_timer <= 0.0 and not e.is_moving():
			e.think_timer = 0.06 + randf() * 0.08
			think(e)


# ---------- UI helpers ----------

func hint(key: String, msg: String) -> void:
	var now := Time.get_ticks_msec()
	if now - int(hint_cooldown.get(key, 0)) < 2500:
		return
	hint_cooldown[key] = now
	toast(msg)


func toast(msg: String, kind: String = "") -> void:
	ui.toast(msg, kind)


func pop_text(ent: Entity, text: String, color: String) -> void:
	var rc := ent.render_cell()
	var w := renderer.grid_to_world(rc.x, rc.y)
	renderer.float_text(w.x, w.y - 70.0, text, Color.html(color))


func play_at(sound: String, ent: Entity, vol: float) -> void:
	if player == null:
		return
	var now := Time.get_ticks_msec()
	if now - int(last_sound_at.get(sound, 0)) < 60:
		return
	last_sound_at[sound] = now
	if ent.lvl != lvl:
		return
	var d := absi(ent.x - player.x) + absi(ent.y - player.y)
	if d > 12:
		return
	audio.play(sound, vol * maxf(0.2, 1.0 - d / 12.0))


func episode_text() -> String:
	var ep := ds.current_episode
	var title: String = str(ep.get("title", ""))
	var suffix := ""
	if title != "" and title != "Title" and not title.begins_with("Episode"):
		suffix = " - %s" % title
	return "Episode %d%s" % [episode_num, suffix]


func update_hud() -> void:
	if player == null:
		return
	ui.update_hud(player, lvl, ds.maxlevel, episode_text())


func show_objective(first: bool = false) -> void:
	var ep := ds.current_episode
	var title: String = str(ep.get("title", ""))
	if title == "" or title == "Title":
		title = "Episode %d" % episode_num
	var body := ui.rich_text(str(ep.get("response", "Find the relic and return it home.")))
	var has_rivals := false
	for e in entities:
		if e.team == 2:
			has_rivals = true
			break
	var extra := ""
	if has_rivals:
		extra = "\n\n[color=#ffaa55]Rivals are hunting in the dungeon! They seek the blue treasure and will carry it to their lair.[/color]"
	var hint_text := ui.rich_text("Brave the lower floors, secure the blue treasure (-p) and carry it back to your glowing home pad (-k).")
	modal_action = Callable()
	show_modal(title.to_upper(), "[b]%s[/b]\n\n[color=#b3a6c9]%s[/color]%s" % [body, hint_text, extra],
		"ENTER THE DUNGEON" if first else "CONTINUE")


func show_modal(title: String, bbcode: String, button_text: String = "CONTINUE", centered: bool = true) -> void:
	ui.show_modal(title, bbcode, button_text, centered)
	state = "MODAL"
	clear_input()


func close_modal() -> void:
	ui.hide_modal()
	var action := modal_action
	var back := modal_return
	modal_action = Callable()
	modal_return = ""
	audio.play("button.wav", 0.4)
	if back == "PAUSED":
		open_pause()
		return
	state = "PLAYING"
	if not action.is_null():
		action.call()
	if not rivals_alerted and entities != null and entities.any(func(e): return e.team == 2):
		rivals_alerted = true
		toast("Rivals are in the area! Protect the blue treasure.", "warn")


func show_help() -> void:
	var row := func(keys: String, text: String) -> String:
		return "[color=#ffd45a][b]%s[/b][/color]  %s\n" % [keys, text]
	modal_action = Callable()
	show_modal("HOW TO PLAY",
		row.call("W A S D / arrows", "Move toward a screen direction. Hold one key and you follow the tunnel around its corners.") +
		row.call("Click", "Walk to a tile. Hold the button to follow the cursor, or click a monster to close in and attack it.") +
		row.call("Space / J", "Fire. Auto-aims at the nearest monster lined up on a diagonal, otherwise straight ahead.") +
		row.call("Right-click", "Fire toward the cursor.") +
		row.call("E / Enter", "Use a ladder (or double-click it).") +
		row.call("R  /  Q", "Ring of Protection  /  set the relic down.") +
		row.call("M / Tab", "Full map of the explored floor.") +
		row.call("Wheel / + -", "Zoom in and out.") +
		row.call("Esc  F  N", "Pause menu  /  fullscreen  /  mute.") +
		row.call("Gamepad", "Left stick move, RT / right stick fire, A ladder, X ring, Y relic, Back map, Start pause.") +
		"\n[color=#b3a6c9]Missiles fly along the four diagonals - line up your shots, and sidestep when a monster flashes gold: it is about to fire. " +
		"Hits make you drop the relic. Taking it wakes the whole dungeon, so use your ring and run for the home pad.[/color]",
		"CONTINUE", false)


# ---------- pause, map, talents ----------

func open_pause() -> void:
	if state != "PLAYING" and state != "MODAL" and state != "PAUSED":
		return
	if state == "MODAL":
		ui.hide_modal()
	state = "PAUSED"
	clear_input()
	ui.sync_settings(settings, DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	ui.show_pause(true)


func close_pause() -> void:
	ui.show_pause(false)
	state = "PLAYING"


func pause_open_map() -> void:
	close_pause()
	open_map()


func pause_open_help() -> void:
	ui.show_pause(false)
	modal_return = "PAUSED"
	show_help()


func pause_restart() -> void:
	close_pause()
	begin_episode()


func pause_quit() -> void:
	ui.show_pause(false)
	ui.show_hud(false)
	player = null
	entities = []
	projectiles = []
	pending_perks = 0
	clear_input()
	show_select_screen()


func toggle_mute() -> void:
	settings.muted = audio.toggle_mute()
	save_settings()
	toast("Sound off." if settings.muted else "Sound on.")


func toggle_fullscreen() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	ui.sync_settings(settings, DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)


func on_volume_changed(kind: String, value: float) -> void:
	settings[kind] = value
	save_settings()
	if kind == "sfx":
		audio.play("item.wav", 0.5)


func on_setting_pressed(key: String) -> void:
	match key:
		"mute": toggle_mute()
		"fs": toggle_fullscreen()
		_:
			settings[key] = not settings[key]
			save_settings()


func open_map() -> void:
	if state != "PLAYING" and state != "PAUSED":
		return
	map_lvl = lvl
	state = "MAP"
	clear_input()
	ui.show_map(true, map_lvl)


func close_map() -> void:
	ui.show_map(false)
	state = "PLAYING"


func map_floor(step: int) -> void:
	map_lvl = clampi(map_lvl + step, 1, ds.maxlevel)
	ui.refresh_bigmap(map_lvl)


func open_perks() -> void:
	var p := player
	var pool: Array = []
	for perk in Defs.PERKS:
		var cap: int = perk.max if perk.max > 0 else 99
		if Defs.perk_can(perk.id, p) and int(p.perks.get(perk.id, 0)) < cap:
			pool.append(perk)
	pool.shuffle()
	perk_choices = pool.slice(0, 3)
	if perk_choices.is_empty():
		pending_perks = 0
		return
	state = "PERK"
	clear_input()
	var ranks: Array = []
	for perk in perk_choices:
		ranks.append(int(p.perks.get(perk.id, 0)) + 1)
	ui.show_perks(p.level, perk_choices, ranks)
	audio.play("item.wav", 0.5)


func choose_perk(i: int) -> void:
	if state != "PERK" or i < 0 or i >= perk_choices.size():
		return
	var perk: Dictionary = perk_choices[i]
	var p := player
	Defs.perk_apply(perk.id, p)
	p.perks[perk.id] = int(p.perks.get(perk.id, 0)) + 1
	pending_perks = maxi(0, pending_perks - 1)
	ui.hide_perks()
	state = "PLAYING"
	audio.play("treasure.wav", 0.5)
	toast("%s: %s." % [perk.name, perk.desc], "good")
	var w := renderer.grid_to_world(p.x, p.y)
	renderer.burst(w.x, w.y - 30, 0x9fd8ff, 18, 100, 0.7, 12)
	update_hud()


# ---------- objective guide ----------

func up_stairs(l: int) -> Array:
	if not stair_cache.has(l):
		stair_cache[l] = ds.find_stairs(l, "up")
	return stair_cache[l]


## Points toward the home pad (or the way up to it) while the relic is being carried.
func update_guide() -> void:
	var p := player
	var target = null
	if p.carrying != 0 and p.alive:
		if lvl == home.z:
			target = Vector2i(home.x, home.y)
		else:
			var best_d := 1000000
			for s in up_stairs(lvl):
				var d: int = absi(s.x - p.x) + absi(s.y - p.y)
				if d < best_d:
					best_d = d
					target = s
	if target == null or absi(target.x - p.x) + absi(target.y - p.y) < 5:
		ui.set_guide(false)
		return
	var pc := p.render_cell()
	var a := renderer.grid_to_world(pc.x, pc.y)
	var b := renderer.grid_to_world(target.x, target.y)
	ui.set_guide(true, atan2(b.y - a.y, b.x - a.x))


# ---------- input ----------

func clear_input() -> void:
	keys.clear()
	tap = null
	mouse.left = false
	mouse.right = false
	mouse.left_on_enemy = false
	pad_state.fire = false


func _notification(what: int) -> void:
	# Losing focus pauses, so alt-tabbing never costs you a fight.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		clear_input()
		if state == "PLAYING":
			open_pause()


func key_intent() -> Vector2i:
	var ix := 0
	var iy := 0
	for code in keys:
		if MOVE_KEYS.has(code):
			ix += MOVE_KEYS[code].x
			iy += MOVE_KEYS[code].y
	return Vector2i(signi(ix), signi(iy))


func fire_held() -> bool:
	for k in FIRE_KEYS:
		if keys.has(k):
			return true
	return pad_state.fire


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var code: int = event.physical_keycode
		if not event.pressed:
			keys.erase(code)
			return
		_on_key_down(code, event.echo)
	elif event is InputEventMouseMotion:
		mouse.pos = event.position
		mouse.active = true
	elif event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			mouse.left = false
			mouse.left_on_enemy = false
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			mouse.right = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			renderer.zoom_by(1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			renderer.zoom_by(-1)
		else:
			_on_mouse_down(event)


func _on_key_down(code: int, echo: bool) -> void:
	match state:
		"SPLASH":
			if not echo and (code == KEY_SPACE or code == KEY_ENTER):
				on_splash_click()
			return
		"MODAL":
			if (code == KEY_ESCAPE or code == KEY_ENTER or code == KEY_KP_ENTER or code == KEY_SPACE) and not echo:
				close_modal()
			return
		"PAUSED":
			if (code == KEY_ESCAPE or code == KEY_P) and not echo:
				close_pause()
			return
		"PERK":
			var n: int = {KEY_1: 0, KEY_2: 1, KEY_3: 2, KEY_KP_1: 0, KEY_KP_2: 1, KEY_KP_3: 2}.get(code, -1)
			if n >= 0 and not echo:
				choose_perk(n)
			return
		"MAP":
			if echo:
				return
			if code == KEY_ESCAPE or code == KEY_M or code == KEY_TAB:
				close_map()
			elif code == KEY_LEFT or code == KEY_A:
				map_floor(-1)
			elif code == KEY_RIGHT or code == KEY_D:
				map_floor(1)
			return
	if state != "PLAYING":
		return

	keys[code] = true
	if echo:
		return

	if MOVE_KEYS.has(code):
		mouse.active = false
		var intent := key_intent()
		tap = {"ix": intent.x, "iy": intent.y, "until": time + 0.22}
		path = []
		attack_target = null
		auto_use = false
		return
	match code:
		KEY_SHIFT, KEY_E, KEY_ENTER, KEY_KP_ENTER: use_stairs()
		KEY_R: use_ring()
		KEY_Q, KEY_T: drop_relic(player, true)
		KEY_M, KEY_TAB: open_map()
		KEY_N: toggle_mute()
		KEY_F: toggle_fullscreen()
		KEY_H, KEY_F1: show_help()
		KEY_F2, KEY_G: show_objective()
		KEY_P, KEY_ESCAPE: open_pause()
		KEY_EQUAL, KEY_KP_ADD: renderer.zoom_by(1)
		KEY_MINUS, KEY_KP_SUBTRACT: renderer.zoom_by(-1)


func _on_mouse_down(event: InputEventMouseButton) -> void:
	if state != "PLAYING":
		return
	audio.start_ambience()
	mouse.pos = event.position
	mouse.active = true
	if event.button_index == MOUSE_BUTTON_LEFT:
		mouse.left = true
		last_path_cell = ""

		var now := Time.get_ticks_msec()
		var g := renderer.screen_to_grid(mouse.pos)
		var cell_key := "%d,%d" % [g.x, g.y]
		var is_dbl: bool = now - last_click_time < 400 and last_click_cell == cell_key
		last_click_time = now
		last_click_cell = cell_key

		var foe = hostile_under_mouse()
		if foe != null:
			attack_target = foe
			mouse.left_on_enemy = true
			path = []
			auto_use = false
			repath_at = 0.0
		else:
			var c := ds.cell(g.x, g.y, lvl)
			if is_dbl and c.type == DungeonSystem.T_STAIR:
				var p := player
				attack_target = null
				mouse.left_on_enemy = false
				if g.x == p.x and g.y == p.y:
					use_stairs()
					return
				var pth = ds.find_path(lvl, p.x, p.y, g.x, g.y)
				if pth != null:
					path = pth
					auto_use = true
					return
			attack_target = null
			mouse.left_on_enemy = false
			path_to_mouse(true)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		mouse.right = true


func hostile_under_mouse():
	var ent = renderer.entity_at_screen(mouse.pos, frame_state())
	return ent if ent != null and hostile(player, ent) else null


func frame_state() -> Dictionary:
	return {"ds": ds, "lvl": lvl, "entities": entities, "player": player}


# ---------- gamepad ----------

func poll_gamepad() -> void:
	var pads := Input.get_connected_joypads()
	var st := pad_state
	if pads.is_empty():
		st.ix = 0
		st.iy = 0
		st.fire = false
		st.aim_dir = 0
		return
	var id: int = pads[0]
	var dead := 0.32
	var ix := 0
	var iy := 0
	var sx := Input.get_joy_axis(id, JOY_AXIS_LEFT_X)
	var sy := Input.get_joy_axis(id, JOY_AXIS_LEFT_Y)
	if Vector2(sx, sy).length() > dead:
		var sector := (roundi(atan2(sy, sx) / (PI / 4.0)) + 8) % 8
		ix = STICK_SECTORS[sector].x
		iy = STICK_SECTORS[sector].y
	if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_LEFT): ix -= 1
	if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_RIGHT): ix += 1
	if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_UP): iy -= 1
	if Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_DOWN): iy += 1
	st.ix = signi(ix)
	st.iy = signi(iy)

	var rx := Input.get_joy_axis(id, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(id, JOY_AXIS_RIGHT_Y)
	st.aim_dir = 0
	if Vector2(rx, ry).length() > 0.5:
		st.aim_dir = diagonal_for(-1 if rx < 0.0 else 1, -1 if ry < 0.0 else 1)
	st.fire = Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT) > 0.5 or Input.is_joy_button_pressed(id, JOY_BUTTON_RIGHT_SHOULDER) \
		or Input.is_joy_button_pressed(id, JOY_BUTTON_B) or st.aim_dir != 0
	if st.ix != 0 or st.iy != 0 or st.aim_dir != 0:
		mouse.active = false

	var edge := func(button: int, fn: Callable) -> void:
		var now := Input.is_joy_button_pressed(id, button)
		if now and not st.prev.get(button, false):
			fn.call()
		st.prev[button] = now
	edge.call(JOY_BUTTON_A, func(): use_stairs())
	edge.call(JOY_BUTTON_X, func(): use_ring())
	edge.call(JOY_BUTTON_Y, func(): drop_relic(player, true))
	edge.call(JOY_BUTTON_BACK, func(): open_map())
	edge.call(JOY_BUTTON_START, func(): open_pause())
	if st.ix != 0 or st.iy != 0:
		path = []
		attack_target = null


# ---------- movement ----------

## Screen-space diagonals: up-left is x-1 (NW), up-right y-1 (NE), down-left y+1 (SW), down-right x+1 (SE).
func diagonal_for(ix: int, iy: int) -> int:
	if ix < 0:
		return Defs.DIR_NW if iy < 0 else Defs.DIR_SW
	return Defs.DIR_NE if iy < 0 else Defs.DIR_SE


## A single screen axis maps to the two diagonals on that side.
func candidates_for(ix: int, iy: int) -> Array:
	if ix < 0:
		return [Defs.DIR_NW, Defs.DIR_SW]
	if ix > 0:
		return [Defs.DIR_NE, Defs.DIR_SE]
	return [Defs.DIR_NW, Defs.DIR_NE] if iy < 0 else [Defs.DIR_SW, Defs.DIR_SE]


func can_step(e: Entity, dir: int) -> bool:
	var v: Vector2i = Defs.DIR_VEC[dir]
	var nx := e.x + v.x
	var ny := e.y + v.y
	return ds.walkable(nx, ny, e.lvl) and entity_at(nx, ny, e.lvl, e) == null


## Turns a screen-space intent into one grid step, following the tunnel when only one axis is held.
func resolve_intent(p: Entity, ix: int, iy: int) -> int:
	if ix == 0 and iy == 0:
		return 0
	if ix != 0 and iy != 0:
		return diagonal_for(ix, iy)
	var cands := candidates_for(ix, iy)
	var open: Array = []
	for d in cands:
		if can_step(p, d):
			open.append(d)
	if open.is_empty():
		return cands[0]
	if open.size() == 1:
		return open[0]
	if open.has(p.dir):
		return p.dir
	var run0 := ds.cast_line(p.lvl, p.x, p.y, open[0], 8).size()
	var run1 := ds.cast_line(p.lvl, p.x, p.y, open[1], 8).size()
	return open[1] if run1 > run0 else open[0]


func current_intent() -> Vector2i:
	var intent := key_intent()
	if intent.x == 0 and intent.y == 0:
		intent = Vector2i(pad_state.ix, pad_state.iy)
	return intent


func try_step(e: Entity, dir: int) -> bool:
	e.dir = dir
	if not can_step(e, dir):
		return false
	var v: Vector2i = Defs.DIR_VEC[dir]
	e.start_move(e.x + v.x, e.y + v.y, dir)
	return true


func update_player_control() -> void:
	var p := player
	if not p.alive or p.is_moving() or transition:
		return

	var dir := 0
	var intent := current_intent()
	var ix := intent.x
	var iy := intent.y
	if ix == 0 and iy == 0 and tap != null and tap.until > time:
		ix = tap.ix
		iy = tap.iy
	if ix != 0 or iy != 0:
		tap = null
		mouse.left_on_enemy = false
		dir = resolve_intent(p, ix, iy)
	else:
		tap = null
		if mouse.left and not mouse.left_on_enemy:
			path_to_mouse(false)
		if attack_target != null and update_attack_target():
			return
		dir = next_path_dir()

	if dir != 0 and try_step(p, dir):
		step_flip += 1
		if (step_flip - 1) % 2 == 0:
			audio.play("walk.wav", 0.25)
	elif dir == 0 and auto_use:
		auto_use = false
		if ds.cell(p.x, p.y, lvl).type == DungeonSystem.T_STAIR:
			use_stairs()


func next_path_dir() -> int:
	var p := player
	if path.is_empty():
		return 0
	var nxt: Vector2i = path[0]
	var dx := nxt.x - p.x
	var dy := nxt.y - p.y
	if absi(dx) + absi(dy) != 1:
		path = []
		return 0
	if entity_at(nxt.x, nxt.y, lvl, p) != null:
		p.dir = Defs.dir_from_delta(dx, dy)
		path = []
		last_path_cell = ""
		return 0
	path.pop_front()
	return Defs.dir_from_delta(dx, dy)


func path_to_mouse(force: bool) -> void:
	var g := renderer.screen_to_grid(mouse.pos)
	var cell_key := "%d,%d" % [g.x, g.y]
	if not force and cell_key == last_path_cell:
		return
	last_path_cell = cell_key
	var p := player
	if g.x == p.x and g.y == p.y:
		if force and settings.autoStairs:
			use_stairs()
		return
	var c := ds.cell(g.x, g.y, lvl)
	if not ds.walkable(g.x, g.y, lvl) or not c.explored:
		return
	var pth = ds.find_path(lvl, p.x, p.y, g.x, g.y)
	if pth != null:
		path = pth
		auto_use = c.type == DungeonSystem.T_STAIR and settings.autoStairs


# ---------- attacking ----------

## Direction to shoot `t` from `a` if they share a clear diagonal within missile range, otherwise 0.
func line_of_fire(a: Entity, t: Entity, max_dist: int = 10) -> int:
	if a.lvl != t.lvl:
		return 0
	var dir := 0
	if a.x == t.x and a.y != t.y:
		dir = Defs.DIR_NE if t.y < a.y else Defs.DIR_SW
	elif a.y == t.y and a.x != t.x:
		dir = Defs.DIR_NW if t.x < a.x else Defs.DIR_SE
	else:
		return 0
	var dist := absi(t.x - a.x) + absi(t.y - a.y)
	if dist > max_dist:
		return 0
	return dir if ds.cast_line(a.lvl, a.x, a.y, dir, dist).size() == dist else 0


## Walks toward the clicked monster until it is in the firing line. Returns true while standing to shoot.
func update_attack_target() -> bool:
	var p := player
	var t := attack_target
	var lost := t == null or not t.alive or t.lvl != lvl or renderer.entity_visibility(ds, t, p) <= 0.0 \
		or absi(t.x - p.x) + absi(t.y - p.y) > 22
	if lost:
		attack_target = null
		return false
	var shot := line_of_fire(p, t)
	if shot != 0:
		p.dir = shot
		path = []
		return true
	if time >= repath_at or path.is_empty():
		repath_at = time + 0.3
		var blocked := func(x, y): return entity_at(x, y, lvl, p) != null and not (x == t.x and y == t.y)
		var pth = ds.find_path(lvl, p.x, p.y, t.x, t.y, blocked)
		if pth == null:
			attack_target = null
			hint("noroute", "No way through to that target.")
			return false
		path = pth.slice(0, pth.size() - 1) if pth.size() > 1 else []
	return false


## Space / fire button: shoot the nearest visible enemy lined up on any diagonal, else straight ahead.
func auto_aim_dir(p: Entity) -> int:
	if not settings.aim:
		return p.dir
	var best := 0
	var best_dist := 99
	for dir in Defs.DIRS:
		var cells := ds.cast_line(p.lvl, p.x, p.y, dir, 10)
		for c in cells:
			var other = entity_at(c.x, c.y, p.lvl, p)
			if other == null:
				continue
			if hostile(p, other) and renderer.entity_visibility(ds, other, p) > 0.15:
				var d: int = absi(c.x - p.x) + absi(c.y - p.y)
				if d < best_dist or (d == best_dist and dir == p.dir):
					best = dir
					best_dist = d
			break
	return best if best != 0 else p.dir


func aim_dir_at_mouse(p: Entity) -> int:
	var foe = hostile_under_mouse()
	if foe != null and settings.aim:
		var shot := line_of_fire(p, foe)
		if shot != 0:
			return shot
	var g := renderer.screen_to_grid(mouse.pos)
	var rc := p.render_cell()
	return Defs.dir_from_delta(g.fx - rc.x, g.fy - rc.y)


func update_player_fire() -> void:
	var p := player
	if not p.alive or transition:
		return
	var dir := 0
	if pad_state.aim_dir != 0:
		dir = pad_state.aim_dir
	elif mouse.right:
		dir = aim_dir_at_mouse(p)
	elif fire_held():
		dir = auto_aim_dir(p)
	elif attack_target != null:
		dir = line_of_fire(p, attack_target)
	if dir != 0:
		fire(p, dir)


## Hover and path state the renderer draws as overlays.
func ui_state() -> Dictionary:
	var p := player
	hover_entity = null
	hover_cell = null
	if mouse.active and p != null and p.alive:
		var foe = hostile_under_mouse()
		hover_entity = foe
		if foe == null:
			var g := renderer.screen_to_grid(mouse.pos)
			var c := ds.cell(g.x, g.y, lvl)
			if c.explored and ds.walkable(g.x, g.y, lvl):
				hover_cell = {"x": g.x, "y": g.y, "ok": true}
	return {
		"hover_cell": hover_cell,
		"hover_entity": hover_entity,
		"target": attack_target,
		"path": path if not path.is_empty() else [],
	}


# ---------- main loop ----------

func update(dt: float) -> void:
	time += dt
	ep_stats.time += dt
	wake_timer -= dt
	if wake_timer <= 0.0:
		wake_timer = 0.25
		wake_nearby()

	poll_gamepad()
	update_player_control()
	update_player_fire()
	update_entities(dt)
	update_projectiles(dt)
	update_pits(dt)
	update_guide()

	minimap_timer -= dt
	if minimap_timer <= 0.0:
		minimap_timer = 0.1
		ui.refresh_minimap()
		update_hud()
	if pending_perks > 0 and player.alive and not transition:
		open_perks()


func _process(delta: float) -> void:
	var dt := minf(0.05, delta)
	if state == "PLAYING":
		update(dt)

	var live: bool = state in ["PLAYING", "MODAL", "PAUSED", "PERK", "MAP"]
	if player != null and not ds.levels.is_empty() and live:
		renderer.frame({
			"ds": ds, "lvl": lvl, "entities": entities, "projectiles": projectiles, "player": player,
			"ui": ui_state() if state == "PLAYING" else null,
		}, dt if state == "PLAYING" else 0.0)
	else:
		renderer.clear_frame()
