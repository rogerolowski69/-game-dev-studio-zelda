extends StaticBody2D
## A solid, flickering brazier flame.

var _time := randf()

@onready var sprite: Sprite2D = $Sprite


func _process(delta: float) -> void:
	_time += delta
	sprite.frame = int(_time * 8.0) % 2
