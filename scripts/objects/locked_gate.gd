extends StaticBody2D
## Seals the shrine until the hero walks into it carrying a key.

var _opened := false

@onready var sprite: Sprite2D = $Sprite
@onready var touch: Area2D = $Touch


func _ready() -> void:
	touch.body_entered.connect(_on_touched)


func _on_touched(body: Node2D) -> void:
	if _opened or not body is Player:
		return
	if not Game.use_key():
		Game.toast("THE GATE IS LOCKED. FIND A KEY!")
		return
	_opened = true
	Sound.play(&"unlock")
	$Collision.set_deferred(&"disabled", true)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(sprite, "scale:y", 0.0, 0.45).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(sprite, "position:y", -8.0, 0.45)
	tween.chain().tween_callback(queue_free)
