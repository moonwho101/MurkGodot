# Copyright (c) Mark Longo 2026
class_name MapView
extends Control
## Follow-the-hero minimap and the full-floor map, drawn as isometric diamonds.

var game: Node
var big := false
var map_lvl := 1


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _diamond(px: float, py: float, rx: float, ry: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(px, py - ry), Vector2(px + rx, py), Vector2(px, py + ry), Vector2(px - rx, py)])


func _arrow(px: float, py: float, size: float, down: bool, color: Color) -> void:
	var s := size * 0.5
	var pts: PackedVector2Array
	if down:
		pts = PackedVector2Array([Vector2(px - s, py - s * 0.6), Vector2(px + s, py - s * 0.6), Vector2(px, py + s * 0.7)])
	else:
		pts = PackedVector2Array([Vector2(px - s, py + s * 0.6), Vector2(px + s, py + s * 0.6), Vector2(px, py - s * 0.7)])
	draw_colored_polygon(pts, color)


func _draw() -> void:
	if game == null or game.player == null or game.ds.levels.is_empty():
		return
	if big:
		_draw_big()
	else:
		_draw_mini()


func _draw_mini() -> void:
	var ds: DungeonSystem = game.ds
	var p: Entity = game.player
	var lvl: int = game.lvl
	var sx := 12.0
	var sy := sx / 2.0
	var ox := size.x / 2.0 - (p.x - p.y) * sx
	var oy := size.y / 2.0 - (p.x + p.y) * sy

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.02, 0.06, 0.55))
	for y in range(1, ds.n + 1):
		for x in range(1, ds.n + 1):
			var cell := ds.cell(x, y, lvl)
			if not cell.explored or (cell.type != DungeonSystem.T_FLOOR and cell.type != DungeonSystem.T_STAIR):
				continue
			var px := ox + (x - y) * sx
			var py := oy + (x + y) * sy
			if px < -sx or px > size.x + sx or py < -sy or py > size.y + sy:
				continue
			var d := _diamond(px, py, sx, sy)
			draw_colored_polygon(d, Color.hex(0xe0a040ff) if cell.type == DungeonSystem.T_STAIR else Color.hex(0x6a5a48ff))
			d.append(d[0])
			draw_polyline(d, Color(1, 0.9, 0.67, 0.18), 1.0)
			if cell.type == DungeonSystem.T_STAIR:
				_arrow(px, py, sx * 0.6, cell.stair == "down", Color.hex(0x1a1208ff))
			if cell.pad >= 0:
				var col := Color.hex(0x55aaffff) if cell.pad == 5 else (Color.hex(0x8a3a20ff) if cell.pad == 4 else Color.hex(0x4fe08aff))
				draw_rect(Rect2(px - sx * 0.22, py - sy * 0.22, sx * 0.44, sy * 0.44), col)

	for r in ds.relics:
		if r.lvl == lvl and r.carrier == null and ds.cell(r.x, r.y, lvl).explored:
			var px: float = ox + (r.x - r.y) * sx
			var py: float = oy + (r.x + r.y) * sy
			draw_rect(Rect2(px - sx * 0.3, py - sy * 0.3, sx * 0.6, sy * 0.6), Color.hex(0x55aaffff))
	for e in game.entities:
		if e == p or not e.alive or e.lvl != lvl:
			continue
		if game.renderer.entity_visibility(ds, e, p) <= 0.0:
			continue
		var px: float = ox + (e.x - e.y) * sx
		var py: float = oy + (e.x + e.y) * sy
		var col := Color.hex(0x66d0ffff) if e.kind == "ally" else (Color.hex(0xff7733ff) if e.team == 2 else Color.hex(0xff4a3aff))
		draw_rect(Rect2(px - sx * 0.22, py - sy * 0.22, sx * 0.44, sy * 0.44), col)
		if e.carrying != 0:
			draw_rect(Rect2(px - sx * 0.15, py - sy * 0.35, sx * 0.3, sy * 0.2), Color.hex(0x55aaffff))
	var ppx := ox + (p.x - p.y) * sx
	var ppy := oy + (p.x + p.y) * sy
	var rad := maxf(3.5, sx * 0.28)
	draw_circle(Vector2(ppx, ppy), rad + 1.5, Color.BLACK)
	draw_circle(Vector2(ppx, ppy), rad, Color.hex(0xfff36aff))
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.42, 0.35, 0.52, 1.0), false, 2.0)


func _draw_big() -> void:
	var ds: DungeonSystem = game.ds
	var p: Entity = game.player
	var lvl := map_lvl
	var w := size.x
	var h := size.y

	var umin := 1e9
	var umax := -1e9
	var vmin := 1e9
	var vmax := -1e9
	var count := 0
	for y in range(1, ds.n + 1):
		for x in range(1, ds.n + 1):
			var c := ds.cell(x, y, lvl)
			if not c.explored or (c.type != DungeonSystem.T_FLOOR and c.type != DungeonSystem.T_STAIR):
				continue
			count += 1
			umin = minf(umin, x - y)
			umax = maxf(umax, x - y)
			vmin = minf(vmin, x + y)
			vmax = maxf(vmax, x + y)
	if count == 0:
		var font := ThemeDB.fallback_font
		var msg := "Nothing explored on this floor yet."
		var ts := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		draw_string(font, Vector2((w - ts.x) / 2.0, h / 2.0), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.hex(0x8f82a8ff))
		return

	var sx := minf(28.0, minf((w * 0.92) / (umax - umin + 3.0), (h * 0.92) / ((vmax - vmin + 3.0) / 2.0)))
	var sy := sx / 2.0
	var ox := w / 2.0 - ((umin + umax) / 2.0) * sx
	var oy := h / 2.0 - ((vmin + vmax) / 2.0) * sy

	for y in range(1, ds.n + 1):
		for x in range(1, ds.n + 1):
			var c := ds.cell(x, y, lvl)
			if not c.explored or (c.type != DungeonSystem.T_FLOOR and c.type != DungeonSystem.T_STAIR):
				continue
			var px := ox + (x - y) * sx
			var py := oy + (x + y) * sy
			var d := _diamond(px, py, sx, sy)
			draw_colored_polygon(d, Color.hex(0xd9983aff) if c.type == DungeonSystem.T_STAIR else Color.hex(0x6a5a48ff))
			if c.type == DungeonSystem.T_FLOOR:
				d.append(d[0])
				draw_polyline(d, Color(1, 0.9, 0.67, 0.12), 1.0)
			else:
				_arrow(px, py, maxf(8.0, sx * 1.2), c.stair == "down", Color.hex(0x1a1208ff))

	var home = game.home
	if home != null and lvl == home.z:
		_mark(ox, oy, sx, sy, home.x, home.y, Color.hex(0x4fe08aff), sx * 0.9)
	var lair = game.team2_lair
	if lair != null and lvl == lair.z and ds.cell(lair.x, lair.y, lvl).explored:
		_mark(ox, oy, sx, sy, lair.x, lair.y, Color.hex(0x55aaffff), sx * 0.9)
	for r in ds.relics:
		if r.lvl != lvl:
			continue
		if r.carrier == null and ds.cell(r.x, r.y, lvl).explored:
			_mark(ox, oy, sx, sy, r.x, r.y, Color.hex(0x55aaffff), sx * 0.8)
		elif r.carrier != null and ds.cell(r.carrier.x, r.carrier.y, lvl).explored:
			_mark(ox, oy, sx, sy, r.carrier.x, r.carrier.y, Color.hex(0x55aaffff), sx * 0.8)
	if p.lvl == lvl:
		_mark(ox, oy, sx, sy, p.x, p.y, Color.hex(0xfff36aff), sx * 0.9)


func _mark(ox: float, oy: float, sx: float, sy: float, x: int, y: int, color: Color, r: float) -> void:
	var c := Vector2(ox + (x - y) * sx, oy + (y + x) * sy)
	var rad := maxf(3.0, minf(9.0, r))
	draw_circle(c, rad + 1.5, Color.BLACK)
	draw_circle(c, rad, color)
