# Copyright (c) Mark Longo 2026
class_name Projectile
extends RefCounted
## A missile flying along one of the four grid diagonals.

var owner: Entity
var dir := 1
var x := 0
var y := 0
var lvl := 1
var t := 0.0
var speed := 7.0
var travelled := 0
var max_range := 11
var kind := 1
var pierce := 0
var hit_ids: Dictionary = {}
var alive := true
var spin := 0.0


func _init(p_owner: Entity, p_dir: int) -> void:
	owner = p_owner
	dir = p_dir
	x = p_owner.x
	y = p_owner.y
	lvl = p_owner.lvl
	kind = missile_kind_for(p_owner.image)
	pierce = p_owner.pierce
	spin = randf() * 6.28


## Missile sprites in the sheet: 1 dagger, 2 axe, 3 fireball, 4 frost bolt, 5 rock, 6 venom.
static func missile_kind_for(image: int) -> int:
	match image:
		1: return 1
		2: return 3
		3: return 1
		4: return 3
		5: return 4
		6: return 1
		7: return 6
		8: return 2 if randf() < 0.5 else 5
		9: return 4
		_: return 1


func render_cell() -> Vector2:
	var v: Vector2i = Defs.DIR_VEC[dir]
	return Vector2(x + v.x * t, y + v.y * t)


func sprite_rect() -> Rect2:
	var east := dir == Defs.DIR_NE or dir == Defs.DIR_SE
	var front := dir == Defs.DIR_SW or dir == Defs.DIR_SE
	return Rect2((384 if east else 0) + (kind - 1) * 64, 640 + (64 if front else 0), 64, 64)
