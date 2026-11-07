# Copyright (c) Mark Longo 2026
class_name MurkRenderer
extends Node2D
## Murk renderer.
##
## The original art is pre-rendered isometric sprites, so the scene is an orthographic, pixel-aligned sprite world.
## Sprites are painter-sorted by grid cell exactly like the DirectDraw original, then lit by a flickering torch
## shader, with additive glow, particles, floating text and screen shake layered on top.

const TILE_W := 112
const TILE_H := 97
const FOOT := Vector2(51, 68)
const SPRITE_OFFSET := Vector2(-31, -58)

const TILE_RECTS := {
	1: [0, 98], 2: [113, 98], 3: [226, 98], 4: [339, 98], 12: [452, 98], 23: [565, 98], 34: [678, 98],
	14: [0, 196], 13: [113, 196], 24: [226, 196], 123: [339, 196], 234: [452, 196], 134: [565, 196], 124: [678, 196],
	1234: [0, 0],
}

const ITEM_ART := {
	"e": {"rect": Rect2(226, 490, 112, 97), "dy": 20},
	"s": {"rect": Rect2(565, 0, 113, 97), "dy": 0},
	"r": {"rect": Rect2(678, 0, 113, 97), "dy": 0},
	"a": {"rect": Rect2(450, 0, 113, 97), "dy": 0},
}

## Home pad art per class pad index, the monsters' lair marker, and the rivals' lair pad.
const PAD_ART := [
	Rect2(113, 294, 112, 97), # 0: green (warrior)
	Rect2(337, 294, 112, 97), # 1: blue (thief)
	Rect2(449, 294, 112, 97), # 2: dark green (wizard)
	Rect2(561, 294, 112, 97), # 3: cyan (cleric)
	Rect2(224, 294, 113, 97), # 4: monster lair
	Rect2(337, 294, 112, 97), # 5: rival lair pad
]

const PIT_ART := [Rect2(452, 490, 113, 98), Rect2(565, 490, 113, 98), Rect2(678, 490, 113, 98)]
const RELIC_RECT := Rect2(678, 294, 112, 97)
const STAIR_UP_RECT := Rect2(224, 0, 112, 97)
const STAIR_DOWN_RECT := Rect2(112, 0, 112, 97)

const ZOOM_LEVELS := [1.0, 1.5, 2.0, 3.0, 4.0]
const MISSILE_COLORS := {1: 0xcfe8ff, 2: 0xff7755, 3: 0xff8a2a, 4: 0x55c8ff, 5: 0xaaaaaa, 6: 0x66ff55}
const TRAIL_COLORS := {1: 0xdddddd, 2: 0xff6644, 3: 0xffa030, 4: 0x66ccff, 5: 0x999999, 6: 0x77ff55}

var textures := {}
var scale_px := 2.0
var user_zoom := 0.0  # 0 = automatic
var cam := Vector2.ZERO
var cam_snap := true
var shake := 0.0
var shake_enabled := true
var light_radius := 300.0
var time := 0.0
var view_size := Vector2(1280, 720)

var _holder: Node2D
var _world: DrawLayer
var _overlay: DrawLayer
var _glow: DrawLayer
var _text: DrawLayer
var _lit_material: ShaderMaterial
var _glow_tex: ImageTexture
var _ring_tex: ImageTexture
var _shadow_tex: ImageTexture
var _font: Font

var _st := {}
var _cells: Array = []  # floor tiles of the current level, in painter order
var _ent_buckets := {}
var _proj_buckets := {}
var _bars: Array = []
var _glows: Array = []  # {center, size, color, opacity, ring}
var _rings: Array = []  # {center, size, color, opacity}
var _pit_at := {}
var _relic_at := {}
var _particles: Array = []
var _floaters: Array = []


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_glow_tex = _make_radial(64, [[0.0, 1.0], [0.35, 0.45], [1.0, 0.0]])
	_ring_tex = _make_radial(64, [[0.0, 0.05], [0.7, 0.15], [0.9, 0.9], [1.0, 0.0]])
	_shadow_tex = _make_shadow()

	_lit_material = ShaderMaterial.new()
	_lit_material.shader = load("res://shaders/lit.gdshader")

	_holder = Node2D.new()
	add_child(_holder)
	_world = _make_layer(_holder, _draw_world)
	_world.material = _lit_material
	_overlay = _make_layer(_holder, _draw_overlay)
	_glow = _make_layer(_holder, _draw_glow)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow.material = add_mat
	_text = _make_layer(self, _draw_text)
	_text.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR


func _make_layer(parent: Node, fn: Callable) -> DrawLayer:
	var layer := DrawLayer.new()
	layer.draw_fn = fn
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(layer)
	return layer


func load_textures() -> void:
	var parts: Texture2D = load("res://assets/dungeon.png")
	textures = {
		"creatures": load("res://assets/p256.png"),
		"parts": parts,
		"floor1": parts,
		"floor2": load("res://assets/dungeon2.png"),
		"floor3": load("res://assets/dungeon3.png"),
	}


func _make_radial(size: int, stops: Array) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / (size / 2.0)
			var a := 0.0
			if d < 1.0:
				for i in range(1, stops.size()):
					if d <= stops[i][0]:
						var t: float = (d - stops[i - 1][0]) / (stops[i][0] - stops[i - 1][0])
						a = lerpf(stops[i - 1][1], stops[i][1], t)
						break
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


func _make_shadow() -> ImageTexture:
	var img := Image.create(64, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 64:
			var d := Vector2((x - 31.5) / 30.0, (y - 15.5) / 15.0).length()
			var a := 0.0
			if d < 1.0:
				a = lerpf(0.75, 0.45, minf(d / 0.7, 1.0)) if d < 0.7 else lerpf(0.45, 0.0, (d - 0.7) / 0.3)
			img.set_pixel(x, y, Color(0, 0, 0, a))
	return ImageTexture.create_from_image(img)


# ---------- projection ----------

func grid_to_world(x: float, y: float) -> Vector2:
	return Vector2(49.0 * x - 48.0 * y + FOOT.x, 25.0 * x + 24.0 * y + FOOT.y)


func world_to_grid(w: Vector2) -> Vector2:
	var u := w.x - FOOT.x
	var v := w.y - FOOT.y
	return Vector2((24.0 * u + 48.0 * v) / 2376.0, (-25.0 * u + 49.0 * v) / 2376.0)


func screen_to_world(p: Vector2) -> Vector2:
	return (p - _holder.position) / scale_px


func world_to_screen(w: Vector2) -> Vector2:
	return w * scale_px + _holder.position


## Returns {x, y, fx, fy}: the nearest grid cell and the fractional grid position under a screen point.
func screen_to_grid(p: Vector2) -> Dictionary:
	var g := world_to_grid(screen_to_world(p))
	return {"x": int(round(g.x)), "y": int(round(g.y)), "fx": g.x, "fy": g.y}


func zoom_by(step: int) -> void:
	var cur := 0
	var best := 1e9
	for i in ZOOM_LEVELS.size():
		var d := absf(ZOOM_LEVELS[i] - scale_px)
		if d < best:
			best = d
			cur = i
	user_zoom = ZOOM_LEVELS[clampi(cur + step, 0, ZOOM_LEVELS.size() - 1)]


func _update_scale() -> void:
	var auto := maxf(1.0, round(view_size.y / 420.0))
	scale_px = user_zoom if user_zoom > 0.0 else auto
	var half_h := view_size.y / (2.0 * scale_px)
	light_radius = clampf(half_h * 1.15, 260.0, 420.0)


# ---------- level ----------

func build_level(ds: DungeonSystem, lvl: int) -> void:
	_cells = []
	var sheet := "floor%d" % ds.tile_type[lvl]
	var w := ds.n + 3
	for y in range(1, ds.n + 1):
		for x in range(1, ds.n + 1):
			var c := ds.cell(x, y, lvl)
			if c.type != DungeonSystem.T_FLOOR and c.type != DungeonSystem.T_STAIR:
				continue
			var code := ""
			if ds.walkable(x - 1, y, lvl): code += "1"
			if ds.walkable(x, y - 1, lvl): code += "2"
			if ds.walkable(x + 1, y, lvl): code += "3"
			if ds.walkable(x, y + 1, lvl): code += "4"
			var key := int(code) if code != "" else 1234
			var tr: Array = TILE_RECTS.get(key, TILE_RECTS[1234])
			_cells.append({
				"x": x, "y": y, "key": y * w + x, "cell": c, "sheet": sheet,
				"origin": Vector2(49 * x - 48 * y, 25 * x + 24 * y),
				"src": Rect2(tr[0], tr[1], TILE_W, TILE_H),
			})
	cam_snap = true


# ---------- visibility ----------

func entity_visibility(ds: DungeonSystem, e: Entity, player: Entity) -> float:
	if not ds.cell(e.x, e.y, e.lvl).explored and not (e.from_x != e.x and ds.cell(e.from_x, e.from_y, e.lvl).explored):
		return 0.0
	if e == player:
		return 1.0
	var pc := player.render_cell()
	var p := grid_to_world(pc.x, pc.y)
	var rc := e.render_cell()
	var w := grid_to_world(rc.x, rc.y)
	var dx := w.x - p.x
	var dy := (w.y - p.y) * 2.0
	var dist := sqrt(dx * dx + dy * dy)
	var r := light_radius * 0.92
	if dist >= r:
		return 0.0
	return minf(1.0, (r - dist) / (r * 0.35))


## Finds the creature under a screen position (sprites are tall, so the ground cell alone is not enough).
func entity_at_screen(p: Vector2, state: Dictionary):
	var wp := screen_to_world(p)
	var best = null
	var best_d := 1e9
	for e in state.entities:
		if e == state.player or not e.alive or e.lvl != state.lvl:
			continue
		if entity_visibility(state.ds, e, state.player) < 0.25:
			continue
		var rc: Vector2 = e.render_cell()
		var w := grid_to_world(rc.x, rc.y)
		if absf(wp.x - w.x) > 26.0 or wp.y < w.y - 64.0 or wp.y > w.y + 14.0:
			continue
		var d := absf(wp.x - w.x) + absf(wp.y - (w.y - 24.0))
		if d < best_d:
			best_d = d
			best = e
	return best


# ---------- effects ----------

func add_shake(amount: float) -> void:
	if not shake_enabled:
		return
	shake = minf(14.0, maxf(shake, amount))


## Spawns a glow particle at world position (wx, wy) (y grows downward).
func spawn_particle(wx: float, wy: float, vx: float, vy: float, life: float, size: float, color: int, grow: float = 0.0) -> void:
	if _particles.size() >= 220:
		return
	_particles.append({
		"x": wx, "y": wy, "vx": vx, "vy": vy, "life": life, "max": life, "size": size,
		"grow": grow, "color": Color.hex((color << 8) | 0xff),
	})


func burst(wx: float, wy: float, color: int, count: int, speed: float, life: float, size: float) -> void:
	for i in count:
		var a := randf() * TAU
		var s := speed * (0.4 + randf() * 0.8)
		spawn_particle(wx, wy, cos(a) * s, sin(a) * s * 0.6, life * (0.6 + randf() * 0.6), size, color, -size * 0.6)


func float_text(wx: float, wy: float, text: String, color: Color) -> void:
	_floaters.append({"x": wx, "y": wy, "text": text, "color": color, "life": 1.1, "max": 1.1})


func _update_effects(dt: float) -> void:
	for i in range(_particles.size() - 1, -1, -1):
		var p: Dictionary = _particles[i]
		p.life -= dt
		if p.life <= 0.0:
			_particles.remove_at(i)
			continue
		p.x += p.vx * dt
		p.y += p.vy * dt
		p.vx *= 0.96
		p.vy *= 0.96
	for i in range(_floaters.size() - 1, -1, -1):
		var f: Dictionary = _floaters[i]
		f.life -= dt
		if f.life <= 0.0:
			_floaters.remove_at(i)
			continue
		f.y -= 26.0 * dt


# ---------- per frame ----------

func frame(state: Dictionary, dt: float) -> void:
	_st = state
	time += dt
	view_size = get_viewport_rect().size
	_update_scale()

	var ds: DungeonSystem = state.ds
	var player: Entity = state.player
	var pc := player.render_cell()
	var pw := grid_to_world(pc.x, pc.y)
	var target := Vector2(pw.x, pw.y - 18.0)
	if cam_snap:
		cam = target
		cam_snap = false
	else:
		cam = cam.lerp(target, 1.0 - exp(-maxf(dt, 0.016) * 9.0))
	_lit_material.set_shader_parameter("light_pos", Vector2(pw.x, pw.y - 10.0))
	_lit_material.set_shader_parameter("radius", light_radius)

	_gather(state, ds, player)
	_update_effects(dt)

	shake *= pow(0.001, dt)
	if shake < 0.2:
		shake = 0.0
	var off := Vector2(randf() - 0.5, randf() - 0.5) * shake if shake > 0.0 else Vector2.ZERO
	_holder.position = (view_size / 2.0 - cam * scale_px).round() + off
	_holder.scale = Vector2(scale_px, scale_px)

	_world.queue_redraw()
	_overlay.queue_redraw()
	_glow.queue_redraw()
	_text.queue_redraw()


func clear_frame() -> void:
	_st = {}
	_world.queue_redraw()
	_overlay.queue_redraw()
	_glow.queue_redraw()
	_text.queue_redraw()


func _bucket_key(ds: DungeonSystem, x: int, y: int) -> int:
	return y * (ds.n + 3) + x


# Collects everything that moves into per-cell buckets so the world draw stays in painter order.
func _gather(state: Dictionary, ds: DungeonSystem, player: Entity) -> void:
	var lvl: int = state.lvl
	var ui = state.get("ui")
	_ent_buckets = {}
	_proj_buckets = {}
	_bars = []
	_glows = []
	_rings = []
	_pit_at = {}
	_relic_at = {}

	for pit in ds.pits:
		if pit.active and pit.lvl == lvl and ds.cell(pit.x, pit.y, lvl).explored:
			_pit_at[_bucket_key(ds, pit.x, pit.y)] = pit
	for r in ds.relics:
		if r.lvl == lvl and r.carrier == null and ds.cell(r.x, r.y, lvl).explored:
			_relic_at[_bucket_key(ds, r.x, r.y)] = r
			var w := grid_to_world(r.x, r.y)
			_glows.append({"center": Vector2(w.x, w.y - 12.0), "size": 90.0, "color": Color.hex(0x55aaffff),
				"opacity": 0.35 + sin(time * 3.0 + r.id) * 0.12, "ring": false})

	for e in state.entities:
		if e.lvl != lvl:
			continue
		var dying: bool = not e.alive
		if dying and e.death_timer <= 0.0:
			continue
		var vis := entity_visibility(ds, e, player)
		if vis <= 0.0:
			continue
		var rc: Vector2 = e.render_cell()
		var w := grid_to_world(rc.x, rc.y)
		var hover := sin(time * 3.0 + e.bob) * 3.0 if (e.image == 2 or e.image == 9) else 0.0
		var alpha := vis
		var squash := 1.0
		if dying:
			var k := maxf(0.0, e.death_timer / 0.8)
			squash = maxf(0.05, k)
			alpha *= minf(1.0, k * 1.5)

		var tint := Color(1, 1, 1, alpha)
		if e.windup > 0.0 and not dying:
			var k2 := 0.5 + 0.5 * sin(time * 40.0)
			tint = Color(1.7, 1.25 + 0.2 * k2, 0.55, alpha)
		if e.hit_flash > 0.0:
			var f := minf(1.0, e.hit_flash / 0.12) * 0.7
			tint = Color(tint.r + f, tint.g * (1.0 - f * 0.6), tint.b * (1.0 - f * 0.6), alpha)

		var use_from: bool = e.move_t < 0.5
		var key := _bucket_key(ds, e.from_x if use_from else e.x, e.from_y if use_from else e.y)
		var item := {
			"e": e, "w": w, "hover": hover, "alpha": alpha, "squash": squash, "tint": tint, "dying": dying,
			"rect": e.sprite_rect(),
		}
		if not _ent_buckets.has(key):
			_ent_buckets[key] = []
		_ent_buckets[key].append(item)

		var focus: bool = ui != null and (ui.get("hover_entity") == e or ui.get("target") == e)
		if focus and not dying:
			var targeted: bool = ui.get("target") == e
			var rs := 72.0 + sin(time * 8.0) * 3.0 if targeted else 66.0
			_rings.append({
				"center": Vector2(w.x, w.y), "size": rs,
				"color": Color.hex(0xff4a3aff if targeted else 0xffd27aff),
				"opacity": (1.0 if targeted else 0.8) * minf(1.0, alpha),
			})
		if not dying and e != player and (e.hp < e.max_hp or focus) and e.kind != "ally":
			_bars.append({"w": w, "hover": hover, "frac": clampf(float(e.hp) / e.max_hp, 0.0, 1.0), "alpha": minf(1.0, alpha)})
		if e.protection > 0.0 and not dying:
			var pulse := 74.0 + sin(time * 9.0) * 4.0
			var op := 0.75
			if e.protection < 1.5:
				op = 0.8 if sin(time * 30.0) > 0.0 else 0.2
			_glows.append({"center": Vector2(w.x, w.y - 30.0), "size": pulse, "color": Color.hex(0x66ddffff),
				"opacity": op, "ring": true})

	for p in state.projectiles:
		if p.lvl != lvl:
			continue
		var key := _bucket_key(ds, p.x, p.y)
		if not _proj_buckets.has(key):
			_proj_buckets[key] = []
		_proj_buckets[key].append(p)
		var rc: Vector2 = p.render_cell()
		var w := grid_to_world(rc.x, rc.y)
		if p.kind != 5:
			var col: int = MISSILE_COLORS.get(p.kind, 0xffffff)
			_glows.append({"center": Vector2(w.x, w.y - 30.0), "size": 54.0 + sin(time * 25.0 + p.spin) * 6.0,
				"color": Color.hex((col << 8) | 0xff), "opacity": 0.55, "ring": false})


func _view_rect() -> Rect2:
	var half := view_size / (2.0 * scale_px)
	return Rect2(cam - half - Vector2(130, 130), half * 2.0 + Vector2(260, 260))


# ---------- drawing ----------

func _draw_world(L: DrawLayer) -> void:
	if _st.is_empty():
		return
	var ds: DungeonSystem = _st.ds
	var lvl: int = _st.lvl
	var view := _view_rect()
	var parts: Texture2D = textures.parts

	for v in _cells:
		var o: Vector2 = v.origin
		if not view.has_point(o):
			continue
		var c: DungeonSystem.Cell = v.cell
		var key: int = v.key
		if c.explored:
			L.draw_texture_rect_region(textures[v.sheet], Rect2(o, Vector2(TILE_W, TILE_H)), v.src)
			if c.type == DungeonSystem.T_STAIR:
				var sr := STAIR_UP_RECT if c.stair == "up" else STAIR_DOWN_RECT
				L.draw_texture_rect_region(parts, Rect2(o, sr.size), sr)
			if _pit_at.has(key):
				var f: int = _pit_at[key].frame
				var art: Rect2 = PIT_ART[0] if (f <= 6 or f >= 30) else (PIT_ART[1] if (f <= 12 or f >= 24) else PIT_ART[2])
				L.draw_texture_rect_region(parts, Rect2(o + Vector2(0, 20), art.size), art)
			if c.pad >= 0:
				var pr: Rect2 = PAD_ART[c.pad]
				L.draw_texture_rect_region(parts, Rect2(o + Vector2(0, 20), pr.size), pr)
			if c.item != "":
				var ia: Dictionary = ITEM_ART[c.item]
				var ir: Rect2 = ia.rect
				var bob := roundf(sin(time * 2.2 + v.x * 1.7 + v.y) * 2.0)
				L.draw_texture_rect_region(parts, Rect2(o + Vector2(0, ia.dy + bob), ir.size), ir)
			if _relic_at.has(key):
				var rbob := sin(time * 2.5 + _relic_at[key].id) * 2.0
				L.draw_texture_rect_region(parts, Rect2(o + Vector2(0, 20 + rbob), RELIC_RECT.size), RELIC_RECT)

		var ents = _ent_buckets.get(key)
		if ents != null:
			for it in ents:
				var w: Vector2 = it.w
				var sh_a: float = minf(1.0, it.alpha)
				L.draw_texture_rect(_shadow_tex, Rect2(roundf(w.x - 23.0), roundf(w.y - 11.0), 46, 23), false, Color(1, 1, 1, sh_a))
			for it in ents:
				var w: Vector2 = it.w
				var sq: float = it.squash
				var top: float = roundf(w.y + SPRITE_OFFSET.y - it.hover) + 64.0 * (1.0 - sq)
				L.draw_texture_rect_region(textures.creatures, Rect2(roundf(w.x + SPRITE_OFFSET.x), top, 64, 64.0 * sq), it.rect, it.tint)
			for it in ents:
				var e: Entity = it.e
				if e.carrying != 0 and not it.dying:
					var w: Vector2 = it.w
					var bob2 := sin(time * 4.0) * 2.0
					L.draw_texture_rect_region(parts, Rect2(roundf(w.x - 28.0), roundf(w.y - 78.0 - bob2), 56, 49), RELIC_RECT, Color(1, 1, 1, it.alpha))
		var projs = _proj_buckets.get(key)
		if projs != null:
			for p in projs:
				var rc: Vector2 = p.render_cell()
				var w := grid_to_world(rc.x, rc.y)
				L.draw_texture_rect_region(textures.creatures, Rect2(roundf(w.x + SPRITE_OFFSET.x), roundf(w.y + SPRITE_OFFSET.y), 64, 64), p.sprite_rect())


func _draw_diamond(L: DrawLayer, center: Vector2, w: float, h: float, color: Color, opacity: float) -> void:
	var pts := PackedVector2Array([
		center + Vector2(0, -h / 2.0), center + Vector2(w / 2.0, 0),
		center + Vector2(0, h / 2.0), center + Vector2(-w / 2.0, 0),
	])
	L.draw_colored_polygon(pts, Color(color.r, color.g, color.b, 0.16 * opacity))
	pts.append(pts[0])
	L.draw_polyline(pts, Color(color.r, color.g, color.b, 0.95 * opacity), maxf(1.0, w / 32.0), true)


# Cursor tile, click-to-move breadcrumbs and a destination marker.
func _draw_overlay(L: DrawLayer) -> void:
	var ui = _st.get("ui")
	if ui == null:
		return
	var hc = ui.get("hover_cell")
	if hc != null and ui.get("hover_entity") == null:
		var col := Color.hex(0xffe9a0ff) if hc.ok else Color.hex(0xff6a5aff)
		var op := 0.55 + sin(time * 5.0) * 0.15 if hc.ok else 0.35
		_draw_diamond(L, grid_to_world(hc.x, hc.y), 97, 49, col, op)
	var path: Array = ui.get("path", [])
	if path.is_empty():
		return
	var last: Vector2i = path[path.size() - 1]
	var pulse := 1.0 + sin(time * 8.0) * 0.06
	_draw_diamond(L, grid_to_world(last.x, last.y), 97 * pulse, 49 * pulse, Color.hex(0x6cff9aff), 0.7 + sin(time * 8.0) * 0.25)
	for i in mini(path.size() - 1, 48):
		_draw_diamond(L, grid_to_world(path[i].x, path[i].y), 30, 15, Color.hex(0xffe9a0ff), 0.35)


func _draw_glow(L: DrawLayer) -> void:
	for r in _rings:
		var c: Vector2 = r.center
		var s: float = r.size
		var pts := PackedVector2Array()
		for i in 41:
			var a := TAU * i / 40.0
			pts.append(c + Vector2(cos(a) * s * 0.42, sin(a) * s * 0.21))
		var col: Color = r.color
		L.draw_polyline(pts, Color(col.r, col.g, col.b, r.opacity * 0.35), 7.0, true)
		L.draw_polyline(pts, Color(col.r, col.g, col.b, r.opacity), 3.5, true)
	for g in _glows:
		var s: float = g.size
		var col: Color = g.color
		col.a = g.opacity
		L.draw_texture_rect(_ring_tex if g.ring else _glow_tex, Rect2(g.center - Vector2(s, s) / 2.0, Vector2(s, s)), false, col)
	for p in _particles:
		var k: float = p.life / p.max
		var size := maxf(1.0, p.size + p.grow * (1.0 - k))
		var col: Color = p.color
		col.a = minf(1.0, k * 1.4)
		L.draw_texture_rect(_glow_tex, Rect2(roundf(p.x - size / 2.0), roundf(p.y - size / 2.0), size, size), false, col)


func _draw_text(L: DrawLayer) -> void:
	if _st.is_empty():
		return
	for b in _bars:
		var w: Vector2 = b.w
		var bw := 40.0
		var base := world_to_screen(Vector2(roundf(w.x - bw / 2.0), roundf(w.y - 62.0 - b.hover)))
		var s := scale_px
		var a: float = b.alpha
		L.draw_rect(Rect2(base + Vector2(-2, -2) * s, Vector2(bw + 4, 8) * s), Color(0, 0, 0, 0.85 * a))
		var frac: float = b.frac
		var col := Color.hex(0x5fd35fff) if frac > 0.5 else (Color.hex(0xe6c84aff) if frac > 0.25 else Color.hex(0xd9342aff))
		col.a = a
		L.draw_rect(Rect2(base, Vector2(maxf(1.0, roundf(bw * frac)), 4) * s), col)
	var size := maxi(11, int(11.0 * scale_px))
	for f in _floaters:
		var txt: String = f.text
		var ts := _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		var sp := world_to_screen(Vector2(f.x, f.y)) - Vector2(ts.x / 2.0, 0.0)
		var col: Color = f.color
		col.a = minf(1.0, f.life / (f.max * 0.4))
		L.draw_string_outline(_font, sp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, col.a * 0.9))
		L.draw_string(_font, sp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
