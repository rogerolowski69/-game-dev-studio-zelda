extends CanvasLayer
## Full-screen layers drawn over everything: the title card, pause, game over,
## victory and the black fade used by warps.

## End screens ignore input for a moment so a mashed button doesn't skip them.
var accepting_input := false
var _blink := 0.0

@onready var fade: ColorRect = $Fade
@onready var dim: ColorRect = $Dim
@onready var title: Control = $Title
@onready var paused: Control = $Paused
@onready var game_over: Control = $GameOver
@onready var victory: Control = $Victory
@onready var victory_stats: Label = $Victory/Stats
@onready var _prompts: Array[Label] = [$Title/Prompt, $GameOver/Prompt, $Victory/Prompt]


func _process(delta: float) -> void:
	_blink += delta
	var on := fmod(_blink, 1.0) < 0.65
	for prompt in _prompts:
		prompt.self_modulate.a = 1.0 if on else 0.0


func show_title() -> void:
	_show(title, Color(0, 0, 0, 0.55))


func show_paused(on: bool) -> void:
	if on:
		_show(paused, Color(0, 0, 0, 0.5))
	else:
		hide_all()


func show_game_over() -> void:
	_show(game_over, Color(0.35, 0.0, 0.04, 0.75))


func show_victory(stats: String) -> void:
	victory_stats.text = stats
	_show(victory, Color(0.0, 0.0, 0.0, 0.7))


func hide_all() -> void:
	for layer: Control in [dim, title, paused, game_over, victory]:
		layer.visible = false


func fade_out(seconds: float) -> void:
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 1.0, seconds)
	await tween.finished


func fade_in(seconds: float) -> void:
	var tween := create_tween()
	tween.tween_property(fade, "color:a", 0.0, seconds)
	await tween.finished


func _show(layer: Control, dim_color: Color) -> void:
	hide_all()
	dim.color = dim_color
	dim.visible = true
	layer.visible = true
	_blink = 0.0
