# Copyright (c) Mark Longo 2026
class_name MurkUI
extends Node
## Murk user interface built in code: splash, champion select, HUD, modal panels, pause menu, talents and map.
## Game rules and state transitions live in game.gd; this script only owns the widgets.

const GOLD := Color(1.0, 0.83, 0.35)
const TEXT := Color(0.92, 0.875, 0.79)
const MUTED := Color(0.70, 0.65, 0.79)
const PANEL_BG := Color(0.11, 0.08, 0.16, 0.97)
const PANEL_BORDER := Color(0.42, 0.35, 0.52)

var game: Node
var ui_theme := Theme.new()

var _hud: Control
var _splash: Control
var _splash_label: Label
var _select: Control
var _modal: Control
var _pause: Control
var _perk: Control
var _map: Control
var _fade_rect: ColorRect
var _vignette: ColorRect

var _cards := {}
var _select_title_best: Label
var _btn_continue: Button
var _btn_confirm: Button

var _modal_title: Label
var _modal_body: RichTextLabel
var _modal_btn: Button

var _episode_label: Label
var _log: VBoxContainer
var _prompt: Label
var _hint: Label
var _guide: Control
var _guide_angle := 0.0
var _portrait: TextureRect
var _portrait_class := ""
var _relic_icon: TextureRect
var _hp_bar: Control
var _ar_bar: Control
var _xp_bar: Control
var _stat_values := {}
var _hud_buttons := {}
var minimap: MapView
var bigmap: MapView
var _map_floor_label: Label
var _map_prev: Button
var _map_next: Button

var _perk_cards: HBoxContainer
var _perk_level: Label

var _set_buttons := {}
var _set_sfx: HSlider
var _set_amb: HSlider
var _pause_restart: Button
var _pause_quit: Button
var _armed := {}
var _flash_tween: Tween
var _icons := Defs.icon_codes()


class HudBar extends Control:
	var frac := 1.0
	var fill := Color.RED
	var left_text := ""
	var right_text := ""
	var thin := false

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.05, 0.03, 0.08, 0.9))
		draw_rect(Rect2(Vector2(1, 1), Vector2((size.x - 2.0) * clampf(frac, 0.0, 1.0), size.y - 2.0)), fill)
		draw_rect(r, Color(0.42, 0.35, 0.52), false, 1.0)
		var font := ThemeDB.fallback_font
		var fs := 9 if thin else 12
		var base := Vector2(6, size.y / 2.0 + fs * 0.36)
		draw_string_outline(font, base, left_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
		draw_string(font, base, left_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		var ts := font.get_string_size(right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var rp := Vector2(size.x - ts.x - 6, base.y)
		draw_string_outline(font, rp, right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8))
		draw_string(font, rp, right_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


class GuideArrow extends Control:
	var angle := 0.0

	func _draw() -> void:
		var c := size / 2.0
		var d := Vector2(cos(angle), sin(angle))
		var n := Vector2(-d.y, d.x)
		var pts := PackedVector2Array([c + d * 22.0, c - d * 12.0 + n * 14.0, c - d * 5.0, c - d * 12.0 - n * 14.0])
		draw_colored_polygon(pts, Color(1.0, 0.85, 0.3, 0.9))
		pts.append(pts[0])
		draw_polyline(pts, Color(0, 0, 0, 0.8), 2.0, true)


func _ready() -> void:
	_build_theme()


# ---------- construction helpers ----------

func _style(bg: Color, border: Color, radius: int = 6, margin: int = 8, bw: int = 2) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(margin)
	return s


func _build_theme() -> void:
	ui_theme.set_color("font_color", "Label", TEXT)
	ui_theme.set_color("font_color", "RichTextLabel", TEXT)
	ui_theme.set_color("default_color", "RichTextLabel", TEXT)
	ui_theme.set_stylebox("panel", "PanelContainer", _style(PANEL_BG, PANEL_BORDER, 12, 28))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var bg := Color(0.23, 0.18, 0.30)
		var border := PANEL_BORDER
		if state == "hover":
			border = GOLD
		elif state == "pressed":
			bg = Color(0.30, 0.24, 0.40)
			border = GOLD
		elif state == "disabled":
			bg = Color(0.14, 0.11, 0.19)
			border = Color(0.25, 0.21, 0.32)
		var sb: StyleBox = _style(bg, border, 6, 10)
		if state == "focus":
			sb = StyleBoxEmpty.new()
		ui_theme.set_stylebox(state, "Button", sb)
	ui_theme.set_color("font_color", "Button", TEXT)
	ui_theme.set_color("font_hover_color", "Button", GOLD)
	ui_theme.set_color("font_pressed_color", "Button", GOLD)
	ui_theme.set_color("font_disabled_color", "Button", Color(0.45, 0.4, 0.5))
	ui_theme.set_font_size("font_size", "Button", 15)
	ui_theme.set_font_size("font_size", "Label", 15)
	ui_theme.set_font_size("normal_font_size", "RichTextLabel", 16)
	ui_theme.set_font_size("bold_font_size", "RichTextLabel", 16)


func _primary(btn: Button, font_size: int = 18) -> void:
	for state in ["normal", "hover", "pressed"]:
		var bg := Color(1.0, 0.89, 0.48)
		if state == "hover":
			bg = Color(1.0, 0.93, 0.6)
		elif state == "pressed":
			bg = Color(0.88, 0.7, 0.2)
		btn.add_theme_stylebox_override(state, _style(bg, Color(1.0, 0.94, 0.69), 6, 12))
	for c in ["font_color", "font_hover_color", "font_pressed_color"]:
		btn.add_theme_color_override(c, Color(0.1, 0.07, 0.03))
	btn.add_theme_font_size_override("font_size", font_size)


func _screen(parent: Node, bg: Color) -> Control:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = ui_theme
	parent.add_child(root)
	var rect := ColorRect.new()
	rect.color = bg
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(rect)
	root.visible = false
	return root


func _center(parent: Control) -> CenterContainer:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


func _label(text: String, size: int = 15, color: Color = TEXT, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, callback: Callable, secondary: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(callback)
	if not secondary:
		_primary(b)
	return b


func _atlas(sheet: String, rect: Rect2) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = load("res://assets/%s.png" % sheet)
	a.region = rect
	return a


func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## Adds a styled card that reacts to clicks.
func _card(callback: Callable) -> PanelContainer:
	var card := PanelContainer.new()
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			callback.call())
	card.mouse_entered.connect(func(): card.set_meta("hover", true); _refresh_card(card))
	card.mouse_exited.connect(func(): card.set_meta("hover", false); _refresh_card(card))
	card.set_meta("selected", false)
	card.set_meta("hover", false)
	_refresh_card(card)
	return card


func _refresh_card(card: PanelContainer) -> void:
	var selected: bool = card.get_meta("selected", false)
	var hover: bool = card.get_meta("hover", false)
	var bg := Color(0.26, 0.20, 0.37) if selected else Color(0.14, 0.10, 0.20)
	var border := GOLD if (selected or hover) else Color(0.35, 0.29, 0.45)
	card.add_theme_stylebox_override("panel", _style(bg, border, 8, 14))


# ---------- build ----------

func setup(p_game: Node) -> void:
	game = p_game
	_build_effects_layer()
	_build_hud()
	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 3
	add_child(fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade_rect)

	var screens := CanvasLayer.new()
	screens.layer = 4
	add_child(screens)
	_build_splash(screens)
	_build_select(screens)
	_build_modal(screens)
	_build_pause(screens)
	_build_perk(screens)
	_build_map(screens)


func _build_effects_layer() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/vignette.gdshader")
	_vignette.material = mat
	layer.add_child(_vignette)


func _build_splash(parent: Node) -> void:
	_splash = _screen(parent, Color.BLACK)
	_splash.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			game.on_splash_click())
	var img := TextureRect.new()
	img.texture = load("res://assets/murk256.png")
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	img.offset_bottom = -90
	img.offset_top = 20
	img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	img.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_splash.add_child(img)
	_splash_label = _label("CLICK TO ENTER THE DUNGEON", 20, Color(1.0, 0.8, 0.33), HORIZONTAL_ALIGNMENT_CENTER)
	_splash_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_splash_label.offset_top = -70
	_splash_label.offset_bottom = -30
	_splash_label.modulate.a = 0.0
	_splash.add_child(_splash_label)


func set_splash_ready() -> void:
	var tw := create_tween().set_loops()
	_splash_label.modulate.a = 1.0
	tw.tween_property(_splash_label, "modulate:a", 0.25, 0.55)
	tw.tween_property(_splash_label, "modulate:a", 1.0, 0.55)


func _build_select(parent: Node) -> void:
	_select = _screen(parent, Color(0.07, 0.05, 0.1, 0.97))
	var center := _center(_select)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(v)
	v.add_child(_label("CHOOSE YOUR CHAMPION", 30, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(_spacer(12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	for key in Defs.CLASS_ORDER:
		var def: Dictionary = Defs.CLASS_DEFS[key]
		var card := _card(func(): game.on_class_picked(key))
		card.custom_minimum_size = Vector2(210, 0)
		var cv := VBoxContainer.new()
		cv.add_theme_constant_override("separation", 8)
		card.add_child(cv)
		var box := PanelContainer.new()
		box.add_theme_stylebox_override("panel", _style(Color(0.1, 0.08, 0.15), Color(0.24, 0.19, 0.31), 4, 8))
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(box)
		var av := TextureRect.new()
		av.texture = _atlas("p256", Rect2(384, def.avatarRow + 64, 64, 64))
		av.custom_minimum_size = Vector2(96, 96)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		av.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(av)
		cv.add_child(_label(str(def.name).to_upper(), 19, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
		var desc := _label(def.desc, 12, Color(0.73, 0.73, 0.73), HORIZONTAL_ALIGNMENT_CENTER)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(180, 52)
		cv.add_child(desc)
		for st in def.stats:
			var r := HBoxContainer.new()
			var a := _label(st[0], 12, Color(0.62, 0.89, 0.75))
			a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.add_child(a)
			r.add_child(_label(st[1], 12, Color(0.62, 0.89, 0.75)))
			cv.add_child(r)
		row.add_child(card)
		_cards[key] = card
	v.add_child(_spacer(10))
	_btn_confirm = _button("DESCEND INTO MURK", func(): game.on_select_confirm(), false)
	_btn_confirm.custom_minimum_size = Vector2(300, 0)
	_btn_confirm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_btn_confirm)
	_btn_continue = _button("CONTINUE", func(): game.on_continue())
	_btn_continue.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_btn_continue.visible = false
	v.add_child(_btn_continue)
	_select_title_best = _label("", 13, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_select_title_best)


func _build_modal(parent: Node) -> void:
	_modal = _screen(parent, Color(0.016, 0.012, 0.03, 0.78))
	var center := _center(_modal)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	_modal_title = _label("", 24, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_modal_title)
	v.add_child(HSeparator.new())
	_modal_body = RichTextLabel.new()
	_modal_body.bbcode_enabled = true
	_modal_body.fit_content = true
	_modal_body.scroll_active = false
	_modal_body.custom_minimum_size = Vector2(560, 0)
	_modal_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_modal_body)
	_modal_btn = _button("CONTINUE", func(): game.close_modal(), false)
	_modal_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_modal_btn.custom_minimum_size = Vector2(200, 0)
	v.add_child(_modal_btn)


func _build_pause(parent: Node) -> void:
	_pause = _screen(parent, Color(0.016, 0.012, 0.03, 0.8))
	var center := _center(_pause)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(460, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_label("PAUSED", 24, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(HSeparator.new())
	var resume := _button("RESUME", func(): game.close_pause(), false)
	v.add_child(resume)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for spec in [["Map", func(): game.pause_open_map()], ["How to play", func(): game.pause_open_help()]]:
		var b := _button(spec[0], spec[1])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
	v.add_child(row)
	_set_sfx = _slider_row(v, "Effects", func(val: float): game.on_volume_changed("sfx", val / 100.0))
	_set_amb = _slider_row(v, "Ambience", func(val: float): game.on_volume_changed("amb", val / 100.0))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	for spec in [["mute", "Sound"], ["fs", "Fullscreen"], ["aim", "Aim assist"], ["shake", "Screen shake"],
			["hints", "Control hints"], ["autoStairs", "Auto-climb"]]:
		var key: String = spec[0]
		var b := _button(spec[1], func(): game.on_setting_pressed(key))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(b)
		_set_buttons[key] = b
	v.add_child(grid)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	_pause_restart = _button("Restart episode", func(): _confirm_then(_pause_restart, func(): game.pause_restart()))
	_pause_restart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_quit = _button("Quit to title", func(): _confirm_then(_pause_quit, func(): game.pause_quit()))
	_pause_quit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(_pause_restart)
	row2.add_child(_pause_quit)
	v.add_child(row2)


func _slider_row(parent: Control, text: String, callback: Callable) -> HSlider:
	var row := HBoxContainer.new()
	var l := _label(text, 14)
	l.custom_minimum_size = Vector2(90, 0)
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 100
	s.step = 1
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(callback)
	row.add_child(s)
	parent.add_child(row)
	return s


## Two-step buttons guard destructive actions without a modal.
func _confirm_then(btn: Button, action: Callable) -> void:
	if _armed.has(btn):
		btn.text = _armed[btn]
		_armed.erase(btn)
		action.call()
		return
	_armed[btn] = btn.text
	btn.text = "Click to confirm"
	get_tree().create_timer(3.0).timeout.connect(func():
		if _armed.has(btn):
			btn.text = _armed[btn]
			_armed.erase(btn))


func _build_perk(parent: Node) -> void:
	_perk = _screen(parent, Color(0.016, 0.012, 0.03, 0.82))
	var center := _center(_perk)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)
	v.add_child(_label("LEVEL UP", 30, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	_perk_level = _label("", 16, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_perk_level)
	v.add_child(_label("Choose a talent  (press 1, 2 or 3)", 14, TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_perk_cards = HBoxContainer.new()
	_perk_cards.add_theme_constant_override("separation", 18)
	_perk_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_perk_cards)


func _build_map(parent: Node) -> void:
	_map = _screen(parent, Color(0.016, 0.012, 0.03, 0.85))
	var center := _center(_map)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	v.add_child(_label("MAP", 24, GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	_map_floor_label = _label("", 16, MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_map_floor_label)
	bigmap = MapView.new()
	bigmap.big = true
	bigmap.custom_minimum_size = Vector2(900, 520)
	v.add_child(bigmap)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	_map_prev = _button("\u25C0 Floor up", func(): game.map_floor(-1))
	_map_next = _button("Floor down \u25B6", func(): game.map_floor(1))
	var close := _button("CLOSE", func(): game.close_map(), false)
	row.add_child(_map_prev)
	row.add_child(close)
	row.add_child(_map_next)
	v.add_child(row)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.theme = ui_theme
	_hud.visible = false
	layer.add_child(_hud)

	_episode_label = _label("Episode 1", 18, GOLD)
	_episode_label.position = Vector2(16, 10)
	_episode_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_episode_label.add_theme_constant_override("outline_size", 5)
	_hud.add_child(_episode_label)

	minimap = MapView.new()
	minimap.game = game
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.offset_left = -236
	minimap.offset_right = -16
	minimap.offset_top = 12
	minimap.offset_bottom = 142
	_hud.add_child(minimap)

	_log = VBoxContainer.new()
	_log.position = Vector2(16, 42)
	_log.custom_minimum_size = Vector2(520, 0)
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_log)

	var guide := GuideArrow.new()
	guide.custom_minimum_size = Vector2(56, 56)
	guide.size = Vector2(56, 56)
	guide.set_anchors_preset(Control.PRESET_CENTER_TOP)
	guide.offset_left = -28
	guide.offset_right = 28
	guide.offset_top = 60
	guide.offset_bottom = 116
	guide.mouse_filter = Control.MOUSE_FILTER_IGNORE
	guide.visible = false
	_guide = guide
	_hud.add_child(guide)

	_prompt = _label("", 20, Color(1.0, 0.89, 0.55), HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt.offset_top = -190
	_prompt.offset_bottom = -160
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.visible = false
	_hud.add_child(_prompt)

	_hint = _label("WASD move  |  Click walk / attack  |  Space fire (auto-aim)  |  E ladder\nR ring  |  Q drop relic  |  M map  |  Esc menu  |  H help",
		12, Color(0.78, 0.72, 0.66, 0.8), HORIZONTAL_ALIGNMENT_CENTER)
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -150
	_hint.offset_bottom = -112
	_hint.add_theme_color_override("font_outline_color", Color.BLACK)
	_hint.add_theme_constant_override("outline_size", 4)
	_hud.add_child(_hint)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -10
	panel.add_theme_stylebox_override("panel", _style(Color(0.08, 0.06, 0.12, 0.92), PANEL_BORDER, 10, 10))
	_hud.add_child(panel)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	panel.add_child(h)

	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(80, 80)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	h.add_child(_portrait)

	var bars := VBoxContainer.new()
	bars.add_theme_constant_override("separation", 4)
	bars.custom_minimum_size = Vector2(250, 0)
	bars.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(bars)
	_hp_bar = _make_bar(bars, "HEALTH", Color(0.75, 0.2, 0.17), 22)
	_ar_bar = _make_bar(bars, "ARMOUR", Color(0.3, 0.5, 0.75), 22)
	_xp_bar = _make_bar(bars, "XP", Color(0.55, 0.35, 0.8), 14)
	_xp_bar.thin = true

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 14)
	for spec in [["floor", "Floor"], ["skill", "Score"], ["level", "Hero Lv"], ["rings", "Rings"]]:
		var sv := VBoxContainer.new()
		sv.add_child(_label(spec[1], 11, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		var val := _label("0", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		sv.add_child(val)
		stats.add_child(sv)
		_stat_values[spec[0]] = val
	h.add_child(stats)

	_relic_icon = TextureRect.new()
	_relic_icon.custom_minimum_size = Vector2(56, 49)
	_relic_icon.texture = _atlas("dungeon", Rect2(678, 294, 112, 97))
	_relic_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_relic_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_relic_icon.tooltip_text = "Relic you are carrying"
	_relic_icon.modulate.a = 0.0
	h.add_child(_relic_icon)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var specs := [
		["ring", "Ring", "Ring of Protection [R]", func(): game.use_ring()],
		["drop", "Drop", "Set down relic [Q]", func(): game.drop_relic(game.player, true)],
		["stairs", "Ladder", "Use ladder [E]", func(): game.use_stairs()],
		["zoom_in", "+", "Zoom in [+]", func(): game.renderer.zoom_by(1)],
		["map", "Map", "Map [M]", func(): game.open_map()],
		["obj", "Goal", "Objective [F2]", func(): game.show_objective()],
		["menu", "Menu", "Menu [Esc]", func(): game.open_pause()],
		["zoom_out", "\u2212", "Zoom out [-]", func(): game.renderer.zoom_by(-1)],
	]
	for s in specs:
		var b := _button(s[1], s[3])
		b.tooltip_text = s[2]
		b.custom_minimum_size = Vector2(58, 30)
		b.add_theme_font_size_override("font_size", 13)
		grid.add_child(b)
		_hud_buttons[s[0]] = b
	h.add_child(grid)


func _make_bar(parent: Control, label: String, color: Color, height: int) -> HudBar:
	var bar := HudBar.new()
	bar.custom_minimum_size = Vector2(250, height)
	bar.fill = color
	bar.left_text = label
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar


# ---------- visibility ----------

func show_hud(on: bool) -> void:
	_hud.visible = on


func show_splash(on: bool) -> void:
	_splash.visible = on


func show_select(on: bool, selected: String = "fighter", save = null, best = null) -> void:
	_select.visible = on
	if not on:
		return
	select_class(selected)
	_btn_continue.visible = save != null
	if save != null:
		var cls: Dictionary = Defs.CLASS_DEFS[save.classKey]
		_btn_continue.text = "CONTINUE \u2014 %s, Level %d, Episode %d" % [cls.name, int(save.hero.level), int(save.episodeNum)]
	_select_title_best.text = "Best run: Episode %d \u00B7 Score %d" % [int(best.episode), int(best.score)] if best != null else ""


func select_class(key: String) -> void:
	for k in _cards:
		_cards[k].set_meta("selected", k == key)
		_refresh_card(_cards[k])


func fade(on: bool) -> void:
	create_tween().tween_property(_fade_rect, "color:a", 1.0 if on else 0.0, 0.25)


func set_fade_instant(value: float) -> void:
	_fade_rect.color.a = value


func flash_hit() -> void:
	if _flash_tween:
		_flash_tween.kill()
	var mat := _vignette.material as ShaderMaterial
	mat.set_shader_parameter("flash", 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_method(func(v: float): mat.set_shader_parameter("flash", v), 1.0, 0.0, 0.45)


# ---------- modal ----------

func show_modal(title: String, bbcode: String, button_text: String, centered: bool = true) -> void:
	_modal_title.text = title
	_modal_body.text = ""
	_modal_body.append_text("[center]%s[/center]" % bbcode if centered else bbcode)
	_modal_btn.text = button_text
	_modal.visible = true


func hide_modal() -> void:
	_modal.visible = false


func is_modal_visible() -> bool:
	return _modal.visible


## Turns original episode text ("~" line breaks, "-x" icons) into BBCode.
func rich_text(text: String) -> String:
	var out := ""
	var i := 0
	while i < text.length():
		var ch := text[i]
		if ch == "~":
			out += "\n"
		elif ch == "-" and i + 1 < text.length() and _icons.has(text[i + 1]):
			var ic: Dictionary = _icons[text[i + 1]]
			var s: float = ic.scale
			out += "[img width=%d height=%d region=%d,%d,%d,%d]res://assets/%s.png[/img]" % [
				roundi(ic.w * s), roundi(ic.h * s), ic.x, ic.y, ic.w, ic.h, ic.sheet]
			i += 1
			while i + 1 < text.length() and text[i + 1] == " ":
				i += 1
		elif ch == "[":
			out += "[lb]"
		else:
			out += ch
		i += 1
	while out.contains("  "):
		out = out.replace("  ", " ")
	return out


# ---------- pause / settings ----------

func show_pause(on: bool) -> void:
	_pause.visible = on


func sync_settings(s: Dictionary, fullscreen: bool) -> void:
	_set_sfx.set_value_no_signal(roundf(float(s.sfx) * 100.0))
	_set_amb.set_value_no_signal(roundf(float(s.amb) * 100.0))
	_set_buttons.aim.text = "Aim assist: %s" % ("On" if s.aim else "Off")
	_set_buttons.shake.text = "Screen shake: %s" % ("On" if s.shake else "Off")
	_set_buttons.hints.text = "Control hints: %s" % ("On" if s.hints else "Off")
	_set_buttons.autoStairs.text = "Auto-climb: %s" % ("On" if s.autoStairs else "Off")
	_set_buttons.mute.text = "Sound: Off" if s.muted else "Sound: On"
	_set_buttons.fs.text = "Exit fullscreen" if fullscreen else "Fullscreen"
	_hint.visible = s.hints


# ---------- perks ----------

func show_perks(level: int, choices: Array, ranks: Array) -> void:
	_perk_level.text = "You reached level %d" % level
	for c in _perk_cards.get_children():
		c.queue_free()
	for i in choices.size():
		var perk: Dictionary = choices[i]
		var index := i
		var card := _card(func(): game.choose_perk(index))
		card.custom_minimum_size = Vector2(200, 230)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(v)
		v.add_child(_label(str(i + 1), 14, GOLD, HORIZONTAL_ALIGNMENT_RIGHT))
		v.add_child(_label(perk.icon, 40, Color(1.0, 0.89, 0.55), HORIZONTAL_ALIGNMENT_CENTER))
		v.add_child(_label(perk.name, 18, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
		var d := _label(perk.desc, 13, Color(0.84, 0.8, 0.89), HORIZONTAL_ALIGNMENT_CENTER)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(170, 0)
		v.add_child(d)
		var rank: int = ranks[i]
		v.add_child(_label("Rank %d" % rank if rank > 1 else "New", 12, MUTED, HORIZONTAL_ALIGNMENT_CENTER))
		_perk_cards.add_child(card)
	_perk.visible = true


func hide_perks() -> void:
	_perk.visible = false


# ---------- map ----------

func show_map(on: bool, lvl: int = 1) -> void:
	_map.visible = on
	if on:
		var vp := get_viewport().get_visible_rect().size
		bigmap.custom_minimum_size = Vector2(minf(1100.0, floorf(vp.x * 0.8)), minf(640.0, floorf(vp.y * 0.6)))
		bigmap.size = bigmap.custom_minimum_size
		refresh_bigmap(lvl)


func refresh_bigmap(lvl: int) -> void:
	bigmap.game = game
	bigmap.map_lvl = lvl
	bigmap.queue_redraw()
	_map_floor_label.text = "Floor %d of %d" % [lvl, game.ds.maxlevel]
	_map_prev.disabled = lvl <= 1
	_map_next.disabled = lvl >= game.ds.maxlevel


# ---------- HUD ----------

func toast(msg: String, kind: String = "") -> void:
	var l := _label(msg, 15, TEXT)
	match kind:
		"good": l.add_theme_color_override("font_color", Color(0.62, 0.95, 0.68))
		"warn": l.add_theme_color_override("font_color", Color(1.0, 0.69, 0.38))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	_log.add_child(l)
	while _log.get_child_count() > 4:
		_log.get_child(0).queue_free()
		_log.remove_child(_log.get_child(0))
	var tw := l.create_tween()
	tw.tween_interval(3.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func clear_log() -> void:
	for c in _log.get_children():
		c.queue_free()


func set_prompt(text: String) -> void:
	_prompt.visible = text != ""
	_prompt.text = text


func update_hud(p: Entity, lvl: int, maxlevel: int, episode_text: String) -> void:
	var hp_pct := clampf(float(p.hp) / p.max_hp, 0.0, 1.0)
	_hp_bar.frac = hp_pct
	_hp_bar.fill = Color(0.95, 0.35, 0.2) if hp_pct < 0.3 else Color(0.75, 0.2, 0.17)
	_hp_bar.right_text = "%d / %d" % [maxi(0, ceili(p.hp)), p.max_hp]
	_ar_bar.frac = minf(1.0, p.armour * 0.02)
	_ar_bar.right_text = str(p.armour)
	var prev: int = p.level_base
	_xp_bar.frac = clampf(float(p.skill - prev) / maxf(1.0, p.next_level_at - prev), 0.0, 1.0)
	_xp_bar.right_text = "%d / %d" % [p.skill, p.next_level_at]
	for b in [_hp_bar, _ar_bar, _xp_bar]:
		b.queue_redraw()
	_stat_values.skill.text = str(p.skill)
	_stat_values.level.text = str(p.level)
	_stat_values.rings.text = str(p.rings)
	_stat_values.floor.text = "%d / %d" % [lvl, maxlevel]
	_episode_label.text = episode_text
	_relic_icon.modulate.a = 1.0 if p.carrying != 0 else 0.0
	var ring: Button = _hud_buttons.ring
	ring.modulate = Color(0.6, 1.0, 0.85) if p.protection > 0.0 else Color.WHITE
	ring.text = "Ring %d" % ceili(p.protection) if p.protection > 0.0 else "Ring"
	if _portrait_class != p.class_key:
		_portrait_class = p.class_key
		_portrait.texture = _atlas("p256", Rect2(384, Defs.CLASS_DEFS[p.class_key].avatarRow + 64, 64, 64))


func set_guide(visible_arrow: bool, angle: float = 0.0) -> void:
	_guide.visible = visible_arrow
	if visible_arrow:
		_guide.angle = angle
		_guide.queue_redraw()


func refresh_minimap() -> void:
	minimap.game = game
	minimap.queue_redraw()
