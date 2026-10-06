extends Area2D
## A doorway: stepping in asks the game flow to move the hero to ``target``.

@export var target := Vector2.ZERO
@export var arrive_facing := Vector2i.DOWN
## Trigger size in pixels; wide exits span several tiles.
@export var size := Vector2(14, 14)


func _ready() -> void:
	var shape := RectangleShape2D.new()
	shape.size = size
	$Shape.shape = shape
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		Game.warp_requested.emit(self)
