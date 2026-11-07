# Copyright (c) Mark Longo 2026
class_name Defs
extends RefCounted
## Shared constants and stat tables from the original game (MurkInit.cpp), plus small helpers.

const DIR_NW := 1
const DIR_NE := 2
const DIR_SW := 3
const DIR_SE := 4

## Grid step per direction: 1 = x-1, 2 = y-1, 3 = y+1, 4 = x+1 (matches the original sprite sheet).
const DIR_VEC := {
	1: Vector2i(-1, 0),
	2: Vector2i(0, -1),
	3: Vector2i(0, 1),
	4: Vector2i(1, 0),
}
const DIRS := [1, 2, 3, 4]

## Row of each creature in p256.png (two 64px rows per creature: back-facing then front-facing).
const SPRITE_ROW := {1: 0, 2: 128, 3: 256, 4: 384, 5: 512, 6: 768, 7: 896, 8: 1024, 9: 128}

## Base time (seconds) to cross one tile; matches the original 6 frames at 50ms.
const BASE_TILE_TIME := 0.28

const CLASS_DEFS := {
	"fighter": {
		"name": "Warrior", "image": 1, "file": "levelsb.dat", "pad": 0,
		"hp": 40, "dmin": 2, "dmax": 3, "shots": 4, "fireCd": 0.30, "tileTime": 0.29, "rings": 1, "armour": 5,
		"wearsArmour": true, "readsScrolls": false, "fireSound": "throw.wav", "avatarRow": 0,
		"desc": "Sturdy and armoured. Hurls throwing blades.",
		"stats": [["Health", "High"], ["Damage", "2 - 3"], ["Wears", "Armour"]],
	},
	"cleric": {
		"name": "Cleric", "image": 5, "file": "levelsc.dat", "pad": 3,
		"hp": 36, "dmin": 1, "dmax": 3, "shots": 4, "fireCd": 0.30, "tileTime": 0.28, "rings": 2, "armour": 0,
		"wearsArmour": false, "readsScrolls": true, "fireSound": "fireball.wav", "avatarRow": 512,
		"desc": "Casts frost bolts and carries extra Rings of Protection.",
		"stats": [["Health", "Medium"], ["Damage", "1 - 3"], ["Reads", "Scrolls"]],
	},
	"thief": {
		"name": "Thief", "image": 3, "file": "levelst.dat", "pad": 1,
		"hp": 34, "dmin": 1, "dmax": 3, "shots": 4, "fireCd": 0.22, "tileTime": 0.24, "rings": 1, "armour": 3,
		"wearsArmour": true, "readsScrolls": false, "fireSound": "tsword.wav", "avatarRow": 256,
		"desc": "Quick on his feet with a rapid-fire dagger.",
		"stats": [["Health", "Medium"], ["Damage", "1 - 3"], ["Speed", "Fastest"]],
	},
	"wizard": {
		"name": "Wizard", "image": 4, "file": "levelsw.dat", "pad": 2,
		"hp": 30, "dmin": 2, "dmax": 4, "shots": 4, "fireCd": 0.34, "tileTime": 0.28, "rings": 1, "armour": 0,
		"wearsArmour": false, "readsScrolls": true, "fireSound": "fireball.wav", "avatarRow": 384,
		"desc": "Frail but deadly. Hurls fireballs that hit hard.",
		"stats": [["Health", "Low"], ["Damage", "2 - 4"], ["Reads", "Scrolls"]],
	},
}
const CLASS_ORDER := ["fighter", "cleric", "thief", "wizard"]

## Monster stats from MurkInit.cpp: hp, damage range, missile cap, fire delay, how eagerly it opens fire.
const MONSTER_DEFS := {
	"beholder": {"name": "Beholder", "image": 2, "hp": 30, "dmin": 2, "dmax": 4, "shots": 3, "fireCd": 0.55, "aggr": 0.7, "sound": "orb.wav", "wake": "dragon.wav"},
	"mouther": {"name": "Gibbering Mouther", "image": 7, "hp": 6, "dmin": 1, "dmax": 1, "shots": 2, "fireCd": 0.8, "aggr": 0.9, "sound": "mouther.wav", "wake": "mouther.wav"},
	"ogre": {"name": "Brute", "image": 8, "hp": 15, "dmin": 1, "dmax": 3, "shots": 4, "fireCd": 0.7, "aggr": 0.7, "sound": "throw2.wav", "wake": "dragon.wav"},
	"skeleton": {"name": "Skeleton", "image": 6, "hp": 10, "dmin": 1, "dmax": 1, "shots": 2, "fireCd": 0.9, "aggr": 0.8, "sound": "skeleton.wav", "wake": "skeleton.wav"},
	"deathorb": {"name": "Death Orb", "image": 9, "hp": 50, "dmin": 2, "dmax": 6, "shots": 8, "fireCd": 0.3, "aggr": 0.7, "sound": "deathorb.wav", "wake": "deathorb.wav"},
}

## Level-up talents. `max` limits how often one can be taken (0 = unlimited).
const PERKS := [
	{"id": "volley", "icon": "\u2735", "name": "Volley", "desc": "+1 missile in flight at once", "max": 4},
	{"id": "power", "icon": "\u2694", "name": "Heavy Hand", "desc": "+1 maximum damage", "max": 5},
	{"id": "edge", "icon": "\u2726", "name": "Keen Edge", "desc": "+1 minimum damage", "max": 4},
	{"id": "rapid", "icon": "\u27A4", "name": "Quick Draw", "desc": "Fire 12% faster", "max": 4},
	{"id": "swift", "icon": "\u2748", "name": "Fleet Foot", "desc": "Move 8% faster", "max": 3},
	{"id": "vital", "icon": "\u2665", "name": "Vitality", "desc": "+15 maximum health and a full heal", "max": 0},
	{"id": "bulwark", "icon": "\u25C8", "name": "Bulwark", "desc": "+8 armour", "max": 0},
	{"id": "charm", "icon": "\u25CB", "name": "Charmed Life", "desc": "+1 Ring of Protection", "max": 0},
	{"id": "pierce", "icon": "\u27B6", "name": "Piercing Shots", "desc": "Missiles pass through one more monster", "max": 2},
	{"id": "leech", "icon": "\u2620", "name": "Soul Leech", "desc": "Heal 2 health for every monster you slay", "max": 3},
]

const SHEET_SIZES := {"p256": Vector2(800, 1280), "dungeon": Vector2(1024, 1176)}


static func dir_from_delta(dx: float, dy: float) -> int:
	if absf(dx) >= absf(dy):
		return DIR_NW if dx < 0 else DIR_SE
	return DIR_NE if dy < 0 else DIR_SW


static func manhattan(ax: int, ay: int, bx: int, by: int) -> int:
	return absi(ax - bx) + absi(ay - by)


static func rand_int(n: int) -> int:
	return randi() % maxi(1, n)


static func perk_can(id: String, p) -> bool:
	match id:
		"volley": return p.max_shots < 8
		"edge": return p.dmin < p.dmax
		"rapid": return p.fire_cd > 0.14
		"swift": return p.tile_time > 0.17
		_: return true


static func perk_apply(id: String, p) -> void:
	match id:
		"volley": p.max_shots += 1
		"power": p.dmax += 1
		"edge": p.dmin += 1
		"rapid": p.fire_cd = maxf(0.12, p.fire_cd * 0.88)
		"swift": p.tile_time = maxf(0.16, p.tile_time * 0.92)
		"vital":
			p.max_hp += 15
			p.hp = p.max_hp
		"bulwark": p.armour += 8
		"charm": p.rings += 1
		"pierce": p.pierce += 1
		"leech": p.lifesteal += 2


## Artwork for the inline icon codes used by the original episode texts ("-p", "-k", ...).
static func icon_codes() -> Dictionary:
	var map := {}
	var letters := "abcdefghi"
	for i in letters.length():
		map[letters[i]] = {"sheet": "p256", "x": 384, "y": i * 128 + 64, "w": 64, "h": 64, "scale": 0.6}
	var tiles := {
		"j": [0, 294], "k": [113, 294], "l": [226, 294], "m": [339, 294], "n": [452, 294], "o": [565, 294],
		"p": [678, 294], "q": [458, 0], "r": [226, 490], "s": [571, 0], "t": [684, 0], "u": [678, 294],
		"v": [339, 490], "w": [565, 490], "x": [113, 0], "y": [226, 0],
	}
	for c in tiles:
		map[c] = {"sheet": "dungeon", "x": tiles[c][0], "y": tiles[c][1], "w": 113, "h": 98, "scale": 0.5}
	return map
