extends Sprite2D
## One-shot smoke puff; frees itself when the animation ends.


func _ready() -> void:
	frame = 0
	var tween := create_tween()
	tween.tween_property(self, "frame", hframes - 1, 0.3)
	tween.tween_interval(0.06)
	tween.tween_callback(queue_free)
