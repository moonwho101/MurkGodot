# Copyright (c) Mark Longo 2026
class_name DrawLayer
extends Node2D
## A canvas layer whose drawing is delegated to a callable, so one script can render several differently
## shaded layers (lit world, additive glow, unlit overlay, screen-space text).

var draw_fn: Callable


func _draw() -> void:
	if draw_fn.is_valid():
		draw_fn.call(self)
