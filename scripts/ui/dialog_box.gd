extends CanvasLayer
## Typewriter text box at the top of the play field. Also shows short toasts.

const CHAR_TIME := 0.04

var _typing := false
var _skip := false
## Bumped whenever the box is reused, so stale toast timers don't hide new text.
var _serial := 0

@onready var box: Panel = $Box
@onready var label: Label = $Box/Text


func _ready() -> void:
	box.visible = false
	Game.toast_requested.connect(toast)


func is_typing() -> bool:
	return _typing


## Types ``text`` out with blips; the attack/confirm button reveals it all at once.
func type_text(text: String) -> void:
	_serial += 1
	label.text = text
	label.visible_characters = 0
	box.visible = true
	_typing = true
	_skip = false
	for i in text.length():
		if _skip:
			break
		label.visible_characters = i + 1
		if text[i] != " " and i % 2 == 0:
			Sound.play(&"text")
		await get_tree().create_timer(CHAR_TIME).timeout
	label.visible_characters = -1
	_typing = false


func toast(text: String, seconds: float = 2.4) -> void:
	_serial += 1
	var serial := _serial
	label.text = text
	label.visible_characters = -1
	box.visible = true
	await get_tree().create_timer(seconds).timeout
	if serial == _serial:
		box.visible = false


func hide_box() -> void:
	_serial += 1
	_skip = true
	box.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _typing and (event.is_action_pressed("attack") or event.is_action_pressed("confirm")):
		_skip = true
		get_viewport().set_input_as_handled()
