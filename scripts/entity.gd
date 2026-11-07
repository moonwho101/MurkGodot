# Copyright (c) Mark Longo 2026
class_name Entity
extends RefCounted
## Murk entities: characters and monsters, with the stat tables from the original game.

static var id_counter := 1

var id := 0
var kind := "monster"  # player | ally | rival | monster
var type := "monster"
var name := "Creature"
var image := 1
var team := 0

var x := 0
var y := 0
var lvl := 1
var from_x := 0
var from_y := 0
var dir := Defs.DIR_SE
var move_t := 1.0
var tile_time := Defs.BASE_TILE_TIME

var max_hp := 10
var hp := 10
var armour := 0
var rings := 0
var protection := 0.0
var skill := 0
var dmin := 1
var dmax := 1
var max_shots := 2
var fire_cd := 0.5
var fire_timer := 0.0
var shots := 0
var fire_sound := ""
var aggr := 0.8

var asleep := false
var alive := true
var death_timer := 0.0
var respawn_timer := 0.0
var hit_flash := 0.0
var rest_timer := 0.0
var think_timer := 0.0
var shot_flash := 0.0
var spawn := Vector3i.ZERO
var lair = null  # Vector3i(x, y, lvl) or null
var class_key := ""
var carrying := 0
var bob := 0.0
var windup := 0.0
var windup_dir := 0
var overflow := 0.0
var pierce := 0
var lifesteal := 0
var perks := {}
var stair_cd := 0.0
var stair_timer := 0.0
var stair_goal = null  # Vector2i or null
var stair_wander := ""
var off_step_timer := 0.0
var is_leader := false

# Player progression
var level := 1
var level_base := 0
var next_level_at := 25


func _init(cfg: Dictionary) -> void:
	id = id_counter
	id_counter += 1
	kind = cfg.get("kind", "monster")
	type = cfg.get("type", "monster")
	name = cfg.get("name", "Creature")
	image = cfg.get("image", 1)
	team = cfg.get("team", 0)
	x = cfg.x
	y = cfg.y
	lvl = cfg.lvl
	from_x = x
	from_y = y
	dir = cfg.get("dir", Defs.DIR_SE)
	tile_time = cfg.get("tileTime", Defs.BASE_TILE_TIME)
	max_hp = cfg.hp
	hp = cfg.hp
	armour = cfg.get("armour", 0)
	rings = cfg.get("rings", 0)
	dmin = cfg.dmin
	dmax = cfg.dmax
	max_shots = cfg.shots
	fire_cd = cfg.fireCd
	fire_sound = cfg.get("fireSound", "")
	aggr = cfg.get("aggr", 0.8)
	asleep = cfg.get("asleep", false)
	think_timer = randf() * 0.3
	spawn = Vector3i(x, y, lvl)
	lair = cfg.get("lair", Vector3i(x, y, lvl))
	class_key = cfg.get("classKey", "")
	bob = randf() * 6.28
	is_leader = cfg.get("isLeader", false)


func is_monster() -> bool:
	return kind == "monster"


func is_moving() -> bool:
	return move_t < 1.0


## Renders from the tile it left toward the tile it is entering.
func render_cell() -> Vector2:
	return Vector2(from_x + (x - from_x) * move_t, from_y + (y - from_y) * move_t)


func start_move(nx: int, ny: int, d: int) -> void:
	from_x = x
	from_y = y
	x = nx
	y = ny
	dir = d
	move_t = 0.0


func teleport(nx: int, ny: int, new_lvl: int) -> void:
	x = nx
	y = ny
	from_x = nx
	from_y = ny
	lvl = new_lvl
	move_t = 1.0


## Returns true on the frame the entity finishes entering its tile; `overflow` keeps the leftover time
## so chained steps stay perfectly smooth.
func update(dt: float) -> bool:
	var arrived := false
	overflow = 0.0
	if move_t < 1.0:
		var t := move_t + dt / tile_time
		move_t = minf(1.0, t)
		if t >= 1.0:
			overflow = (t - 1.0) * tile_time
			from_x = x
			from_y = y
			arrived = true
	if fire_timer > 0.0:
		fire_timer -= dt
	if hit_flash > 0.0:
		hit_flash -= dt
	if shot_flash > 0.0:
		shot_flash -= dt
	if rest_timer > 0.0:
		rest_timer -= dt
	if protection > 0.0:
		protection = maxf(0.0, protection - dt)
	return arrived


## Continues a step that was started in the same frame the previous one finished.
func advance(dt: float) -> void:
	if move_t < 1.0:
		move_t = minf(1.0, move_t + dt / tile_time)


## Source rectangle in the creature sheet.
func sprite_rect() -> Rect2:
	var col := 0
	if image == 9:
		col = 1
	elif image != 2 and move_t < 1.0:
		col = 1 + mini(4, int(floor(move_t * 5.0)))

	var east := dir == Defs.DIR_NE or dir == Defs.DIR_SE
	var front := dir == Defs.DIR_SW or dir == Defs.DIR_SE
	return Rect2(
		(384 if east else 0) + col * 64,
		Defs.SPRITE_ROW[image] + (64 if front else 0),
		64, 64)


func roll_damage() -> int:
	return dmin + randi() % (dmax - dmin + 1)


## Armour soaks damage first (as in the original). Returns {hp, armour, blocked}.
func take_hit(amount: int) -> Dictionary:
	if protection > 0.0:
		return {"hp": 0, "armour": 0, "blocked": true}
	var left := amount
	var armour_lost := 0
	if armour > 0:
		armour_lost = mini(armour, left)
		armour -= armour_lost
		left -= armour_lost
	hp -= left
	hit_flash = 0.18
	return {"hp": left, "armour": armour_lost, "blocked": false}
