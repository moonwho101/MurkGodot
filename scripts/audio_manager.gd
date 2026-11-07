# Copyright (c) Mark Longo 2026
class_name MurkAudio
extends Node
## Murk audio: playback of the original WAV effects plus an ambient loop.

const FILES := [
	"alive.wav", "back.wav", "bsword.wav", "button.wav", "dead.wav", "deathorb.wav", "die.wav",
	"DRAGON.WAV", "Drip2.wav", "ewizard.wav", "fireball.wav", "impact.wav", "item.wav", "mouther.wav",
	"orb.wav", "ouch.wav", "Protection.wav", "Skeleton.wav", "Spawn.wav", "tcleric.wav", "throw.wav",
	"throw2.wav", "treasure.wav", "tsword.wav", "walk.wav", "win.wav",
]
const POOL_SIZE := 20

var muted := false
var sfx_volume := 1.0
var amb_volume := 1.0

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _ambient: AudioStreamPlayer
var _drip_timer: Timer
var _started := false


func _ready() -> void:
	# Names are stored lower-cased so lookups are case-insensitive, like the web version.
	for file in FILES:
		var stream = load("res://assets/sound/%s" % file)
		if stream:
			_streams[file.to_lower()] = stream
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_ambient = AudioStreamPlayer.new()
	_ambient.finished.connect(func(): _ambient.play())
	add_child(_ambient)
	_drip_timer = Timer.new()
	_drip_timer.one_shot = true
	_drip_timer.timeout.connect(_on_drip)
	add_child(_drip_timer)


## Called after the first user interaction; starts the ambience.
func start_ambience() -> void:
	if _started or not _streams.has("back.wav"):
		return
	_started = true
	_ambient.stream = _streams["back.wav"]
	_ambient.volume_db = linear_to_db(0.18 * amb_volume)
	_ambient.play()
	_drip_timer.start(3.0)


func _on_drip() -> void:
	play("drip2.wav", 0.12, 1.0, true)
	_drip_timer.start(4.0 + randf() * 9.0)


func set_volumes(sfx: float, amb: float) -> void:
	sfx_volume = sfx
	amb_volume = amb
	if _ambient:
		_ambient.volume_db = linear_to_db(maxf(0.0001, 0.18 * amb_volume))


func set_muted(value: bool) -> void:
	muted = value
	AudioServer.set_bus_mute(0, muted)


func toggle_mute() -> bool:
	set_muted(not muted)
	return muted


func play(sound_name: String, volume: float = 0.5, rate: float = 1.0, ambient: bool = false) -> void:
	if muted:
		return
	var stream = _streams.get(sound_name.to_lower())
	if stream == null:
		return
	var bus_volume := amb_volume if ambient else sfx_volume
	var vol := volume * bus_volume
	if vol <= 0.0001:
		return
	for p in _pool:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = rate
			p.volume_db = linear_to_db(vol)
			p.play()
			return
