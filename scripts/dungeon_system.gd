# Copyright (c) Mark Longo 2026
class_name DungeonSystem
extends RefCounted
## Murk dungeon model: episode parsing, procedural generation and grid queries.
## Generation follows the original C++ (MurkInit.cpp): winding single-width tunnels carved by
## random walks that never complete a 2x2 block, stacked floors joined by ladders.

const T_VOID := 0
const T_FLOOR := 1
const T_STAIR := 2
const T_ROCK := 3

const MIN_DUNGEON_SIZE := 8
const MAX_DUNGEON_SIZE := 200

const EPISODE_KEYS := [
	"gametype", "beholders", "bspeed", "deathorb", "dspeed", "skeletons", "sspeed", "mouther", "mspeed",
	"ogre", "ospeed", "fighter", "fteam", "fspeed", "cleric", "cteam", "cspeed", "thief", "tteam", "tspeed",
	"wizard", "wteam", "wspeed", "dungeonx", "dungeony", "dungeonlvl", "pits", "maxpit",
]


class Cell:
	var type := 0
	var item := ""
	var explored := false
	var pad := -1
	var stair := ""


class Relic:
	var id := 2
	var x := 0
	var y := 0
	var lvl := 0
	var carrier = null
	var drop_cooldown := 0.0
	var voluntary_drop := false


class Pit:
	var x := 0
	var y := 0
	var lvl := 1
	var frame := 1
	var age := 0.0
	var active := false


var n := 14
var maxlevel := 3
var levels: Array = []
var pits: Array = []
var relics: Array = []
var tile_type: Array = []
var level_definitions: Dictionary = {}
var current_episode: Dictionary = {}
var _void_cell := Cell.new()


func load_level_defs(json: Dictionary) -> void:
	level_definitions = json


func get_episode(filename: String, episode_num: int) -> Dictionary:
	var raw = level_definitions.get(filename, level_definitions.get("levelsb.dat", []))
	var eps: Array = []
	if raw is Array:
		for e in raw:
			eps.append(_normalise_episode(e))
	if eps.is_empty():
		eps.append(_fallback_episode())
	return eps[(maxi(1, episode_num) - 1) % eps.size()]


func _normalise_episode(src: Dictionary) -> Dictionary:
	var ep := {"title": str(src.get("title", "Episode")), "response": str(src.get("response", ""))}
	for k in EPISODE_KEYS:
		ep[k] = int(src.get(k, 0))
	return ep


func _fallback_episode() -> Dictionary:
	return {
		"response": "Find the -p and return it to -k .", "title": "Episode 1", "gametype": 1,
		"beholders": 1, "bspeed": 2, "deathorb": 0, "dspeed": 1, "skeletons": 4, "sspeed": 2,
		"mouther": 2, "mspeed": 2, "ogre": 1, "ospeed": 2,
		"fighter": 0, "fteam": 0, "fspeed": 1, "cleric": 0, "cteam": 0, "cspeed": 1,
		"thief": 0, "tteam": 0, "tspeed": 1, "wizard": 0, "wteam": 0, "wspeed": 1,
		"dungeonx": 14, "dungeony": 14, "dungeonlvl": 3, "pits": 1, "maxpit": 6,
	}


# ---------- grid access ----------

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x <= n + 1 and y <= n + 1


func cell(x: int, y: int, lvl: int) -> Cell:
	if not in_bounds(x, y) or lvl < 1 or lvl >= levels.size():
		return _void_cell
	return levels[lvl][y * (n + 2) + x]


func walkable(x: int, y: int, lvl: int) -> bool:
	var t: int = cell(x, y, lvl).type
	return t == T_FLOOR or t == T_STAIR


# ---------- generation ----------

func build(ep: Dictionary) -> void:
	current_episode = ep
	var size := maxi(int(ep.get("dungeonx", 14)), int(ep.get("dungeony", 14)))
	n = mini(MAX_DUNGEON_SIZE, maxi(MIN_DUNGEON_SIZE, size))
	maxlevel = maxi(2, int(ep.get("dungeonlvl", 3)))
	pits = []
	relics = []
	tile_type = [0]
	for l in range(1, maxlevel + 1):
		tile_type.append(((l - 1) % 3) + 1)

	levels = [null]
	for l in range(1, maxlevel + 1):
		levels.append(_carve_level())
		if l > 1:
			_link_levels(l - 1, l)

	_assign_relics()
	_assign_items(8 + maxlevel * 2)


func _new_level_grid() -> Array:
	var size := (n + 2) * (n + 2)
	var grid := []
	grid.resize(size)
	for i in size:
		grid[i] = Cell.new()
	return grid


func _carve_level() -> Array:
	var w := n + 2
	var center := n / 2
	var jumps := 4
	var steps := int(round(1.3 * 75 * (n * n) / 196.0))
	var grid: Array = []

	for attempt in 30:
		grid = _new_level_grid()

		var k := int(floor(n * 0.35))
		for y in range(1, n + 1):
			for x in range(1, n + 1):
				if x + y <= k or x + y >= 2 * n - k or x - y >= n - k or y - x >= n - k:
					grid[y * w + x].type = T_ROCK

		for j in jumps:
			var x := center
			var y := center
			grid[y * w + x].type = T_FLOOR
			for i in steps:
				var v: Vector2i = Defs.DIR_VEC[1 + randi() % 4]
				var nx := x + v.x
				var ny := y + v.y
				if nx <= 0 or nx >= n or ny <= 0 or ny >= n:
					continue
				var t: int = grid[ny * w + nx].type
				if t == T_ROCK or t == T_STAIR:
					continue
				if randi() % 30 != 1 and _completes_block(grid, nx, ny):
					continue
				grid[ny * w + nx].type = T_FLOOR
				x = nx
				y = ny

		var floors := 0
		for c in grid:
			if c.type == T_FLOOR:
				floors += 1
		if floors >= maxf(40.0, n * n * 0.25):
			break
	return grid


func _completes_block(grid: Array, x: int, y: int) -> bool:
	var w := n + 2
	for sx in [-1, 1]:
		for sy in [-1, 1]:
			if grid[y * w + x + sx].type == T_FLOOR and grid[(y + sy) * w + x].type == T_FLOOR \
					and grid[(y + sy) * w + x + sx].type == T_FLOOR:
				return true
	return false


func _link_levels(upper: int, lower: int) -> void:
	var candidates := []
	for y in range(1, n + 1):
		for x in range(1, n + 1):
			if cell(x, y, upper).type == T_FLOOR and cell(x, y, lower).type == T_FLOOR:
				candidates.append(Vector2i(x, y))
	candidates.shuffle()

	var placed: Array = []
	for c in candidates:
		if placed.size() >= 3:
			break
		var too_close := false
		for p in placed:
			if absi(p.x - c.x) + absi(p.y - c.y) < 4:
				too_close = true
				break
		if too_close:
			continue
		placed.append(c)
	if placed.is_empty() and not candidates.is_empty():
		placed.append(candidates[0])

	for p in placed:
		var a := cell(p.x, p.y, upper)
		var b := cell(p.x, p.y, lower)
		a.type = T_STAIR
		a.stair = "down"
		a.item = ""
		b.type = T_STAIR
		b.stair = "up"
		b.item = ""


func is_free_floor(x: int, y: int, lvl: int) -> bool:
	var c := cell(x, y, lvl)
	return c.type == T_FLOOR and c.item == "" and c.pad < 0


## Random free floor tile on `lvl` as Vector3i(x, y, lvl); `accept` (optional) may veto candidates.
## Returns null if none is found.
func random_floor(lvl: int, accept: Callable = Callable()):
	for tries in 1000:
		var x := randi() % n + 1
		var y := randi() % n + 1
		if is_free_floor(x, y, lvl) and (accept.is_null() or accept.call(x, y)):
			return Vector3i(x, y, lvl)
	return null


func _assign_relics() -> void:
	# Both the player and rivals seek the blue treasure (relic 2), hidden deeper in the dungeon.
	var deep_lvl := (randi() % (maxlevel - 1)) + 2 if maxlevel > 1 else 1
	var p = random_floor(deep_lvl)
	if p == null:
		p = random_floor(maxlevel)
	if p != null:
		var r := Relic.new()
		r.id = 2
		r.x = p.x
		r.y = p.y
		r.lvl = p.z
		relics.append(r)


func relic(id: int):
	for r in relics:
		if r.id == id:
			return r
	return null


func _assign_items(count: int) -> void:
	for i in count:
		var p = random_floor(randi() % maxlevel + 1)
		if p != null:
			var r := randi() % 5
			cell(p.x, p.y, p.z).item = "a" if r == 0 else ("s" if r == 2 else "e")
	for i in 2:
		var p = random_floor(randi() % maxlevel + 1)
		if p != null:
			cell(p.x, p.y, p.z).item = "r"


# ---------- queries ----------

## Marks nearby tunnel cells (reachable within `depth` steps) as explored; returns true if anything new appeared.
func reveal(lvl: int, x: int, y: int, depth: int = 4) -> bool:
	var changed := false
	var w := n + 2
	var seen := {y * w + x: true}
	var frontier: Array = [Vector2i(x, y)]
	var start := cell(x, y, lvl)
	if start.type != T_VOID and not start.explored:
		start.explored = true
		changed = true

	for d in depth:
		if frontier.is_empty():
			break
		var next: Array = []
		for f in frontier:
			for dir in Defs.DIRS:
				var v: Vector2i = Defs.DIR_VEC[dir]
				var nx: int = f.x + v.x
				var ny: int = f.y + v.y
				var key := ny * w + nx
				if seen.has(key) or not walkable(nx, ny, lvl):
					continue
				seen[key] = true
				var c := cell(nx, ny, lvl)
				if not c.explored:
					c.explored = true
					changed = true
				next.append(Vector2i(nx, ny))
		frontier = next
	return changed


## Shortest walkable route from (sx,sy) to (tx,ty); `blocked(x,y)` may veto cells.
## Returns the steps (excluding start) as an Array of Vector2i, or null if unreachable.
func find_path(lvl: int, sx: int, sy: int, tx: int, ty: int, blocked: Callable = Callable(), max_nodes: int = -1):
	if max_nodes < 0:
		max_nodes = maxi(900, n * n)
	if not walkable(tx, ty, lvl):
		return null
	var w := n + 2
	var prev := {}
	var start := sy * w + sx
	prev[start] = -1
	var queue: Array = [Vector2i(sx, sy)]
	var head := 0
	while head < queue.size() and head < max_nodes:
		var cur: Vector2i = queue[head]
		head += 1
		if cur.x == tx and cur.y == ty:
			var path: Array = []
			var k := cur.y * w + cur.x
			while k != start:
				path.append(Vector2i(k % w, k / w))
				k = prev[k]
			path.reverse()
			return path
		for dir in Defs.DIRS:
			var v: Vector2i = Defs.DIR_VEC[dir]
			var nx := cur.x + v.x
			var ny := cur.y + v.y
			var key := ny * w + nx
			if prev.has(key) or not walkable(nx, ny, lvl):
				continue
			if not blocked.is_null() and not (nx == tx and ny == ty) and blocked.call(nx, ny):
				continue
			prev[key] = cur.y * w + cur.x
			queue.append(Vector2i(nx, ny))
	return null


## Walks from a cell along a direction until a wall; returns the cells passed (nearest first).
func cast_line(lvl: int, x: int, y: int, dir: int, max_dist: int) -> Array:
	var cells: Array = []
	var cx := x
	var cy := y
	var v: Vector2i = Defs.DIR_VEC[dir]
	for i in max_dist:
		cx += v.x
		cy += v.y
		if not walkable(cx, cy, lvl):
			break
		cells.append(Vector2i(cx, cy))
	return cells


func find_stairs(lvl: int, kind: String) -> Array:
	var out: Array = []
	for y in range(1, n + 1):
		for x in range(1, n + 1):
			var c := cell(x, y, lvl)
			if c.type == T_STAIR and c.stair == kind:
				out.append(Vector2i(x, y))
	return out
