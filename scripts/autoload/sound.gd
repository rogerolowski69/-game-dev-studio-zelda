extends Node
## Fire-and-forget sound effects over a small voice pool, plus one music channel.

const VOICES := 8
const MUSIC_DB := -7.0

const SFX := {
	&"sword": preload("res://assets/audio/sfx/sword.wav"),
	&"hit": preload("res://assets/audio/sfx/hit.wav"),
	&"enemy_die": preload("res://assets/audio/sfx/enemy_die.wav"),
	&"hurt": preload("res://assets/audio/sfx/hurt.wav"),
	&"gem": preload("res://assets/audio/sfx/gem.wav"),
	&"heart": preload("res://assets/audio/sfx/heart.wav"),
	&"key": preload("res://assets/audio/sfx/key.wav"),
	&"unlock": preload("res://assets/audio/sfx/unlock.wav"),
	&"item_get": preload("res://assets/audio/sfx/item_get.wav"),
	&"text": preload("res://assets/audio/sfx/text.wav"),
	&"shield": preload("res://assets/audio/sfx/shield.wav"),
	&"stairs": preload("res://assets/audio/sfx/stairs.wav"),
	&"game_over": preload("res://assets/audio/sfx/game_over.wav"),
	&"victory": preload("res://assets/audio/sfx/victory.wav"),
	&"spawn": preload("res://assets/audio/sfx/spawn.wav"),
	&"shoot": preload("res://assets/audio/sfx/shoot.wav"),
	&"pause": preload("res://assets/audio/sfx/pause.wav"),
	&"start": preload("res://assets/audio/sfx/start.wav"),
}

const MUSIC := {
	&"overworld": preload("res://assets/audio/music/overworld.wav"),
	&"cave": preload("res://assets/audio/music/cave.wav"),
}

var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _music: AudioStreamPlayer
var _music_key := &""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in VOICES:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	_music = AudioStreamPlayer.new()
	_music.volume_db = MUSIC_DB
	add_child(_music)


func play(sfx: StringName, pitch_jitter: float = 0.0) -> void:
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	voice.stream = SFX[sfx]
	voice.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	voice.play()


func play_music(key: StringName) -> void:
	if key == _music_key and _music.playing:
		return
	_music_key = key
	_music.stream = MUSIC[key]
	_music.volume_db = MUSIC_DB
	_music.play()


func stop_music() -> void:
	_music_key = &""
	_music.stop()


## Dip the music under a jingle (item fanfare) and bring it back.
func duck_music(seconds: float) -> void:
	var tween := create_tween()
	tween.tween_property(_music, "volume_db", -40.0, 0.08)
	tween.tween_interval(seconds)
	tween.tween_property(_music, "volume_db", MUSIC_DB, 0.4)


func toggle_mute() -> void:
	AudioServer.set_bus_mute(0, not AudioServer.is_bus_mute(0))
