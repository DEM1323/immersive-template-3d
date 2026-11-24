extends Node
class_name EphemeralAudioManager

## Manages ethereal SFX and loopable ambient drone for the Ephemeral Jeopardy room.
## Gracefully handles missing audio files in headless test environments.

const AUDIO_DIR := "res://audio"
const SFX_FILES := {
	"tap": "tap_glass.wav",
	"dissolve": "tile_dissolve.wav",
	"correct": "correct_chord.wav",
	"wrong": "wrong_tone.wav",
	"daily_double": "daily_double.wav",
	"tick": "timer_tick.wav",
	"time_up": "time_up.wav",
	"finale": "finale_fanfare.wav",
}
const AMBIENT_FILE := "ambient_drone.wav"

signal mute_changed(is_muted: bool)

var is_muted: bool = false
var _streams: Dictionary = {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _pool_cursor: int = 0
var _ambient_player: AudioStreamPlayer = null


func _ready() -> void:
	for _i in range(6):
		var player := AudioStreamPlayer.new()
		player.volume_db = -4.0
		add_child(player)
		_sfx_pool.append(player)

	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.volume_db = -16.0
	add_child(_ambient_player)

	_load_assets()


func _load_assets() -> void:
	for key in SFX_FILES:
		var path := "%s/%s" % [AUDIO_DIR, SFX_FILES[key]]
		if ResourceLoader.exists(path):
			var stream := load(path) as AudioStream
			if stream != null:
				_streams[key] = stream

	var amb_path := "%s/%s" % [AUDIO_DIR, AMBIENT_FILE]
	if ResourceLoader.exists(amb_path):
		var amb := load(amb_path) as AudioStream
		if amb != null:
			if amb is AudioStreamWAV:
				(amb as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
			_ambient_player.stream = amb
			if not is_muted and DisplayServer.get_name() != "headless":
				_ambient_player.play()


func play_sfx(key: String, pitch_jitter: float = 0.04, volume_offset_db: float = 0.0) -> void:
	if is_muted or DisplayServer.get_name() == "headless":
		return
	if not _streams.has(key) or _sfx_pool.is_empty():
		return
	var player := _sfx_pool[_pool_cursor]
	_pool_cursor = (_pool_cursor + 1) % _sfx_pool.size()
	player.stream = _streams[key]
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.volume_db = -4.0 + volume_offset_db
	player.play()


func toggle_mute() -> void:
	set_muted(not is_muted)


func set_muted(muted: bool) -> void:
	is_muted = muted
	if _ambient_player != null:
		if is_muted:
			_ambient_player.stop()
		elif _ambient_player.stream != null and DisplayServer.get_name() != "headless":
			_ambient_player.play()
	mute_changed.emit(is_muted)
