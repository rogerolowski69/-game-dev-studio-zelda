class_name Projectile
extends Area2D
## A spat rock: flies straight, shatters on walls, and can be blocked by the
## hero's shield (see Player._check_hurtbox).

const POOF := preload("res://scenes/fx/poof.tscn")

@export var speed := 110.0
## Damage in half hearts.
@export var damage := 1

var direction := Vector2.DOWN
var _life := 2.5


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _physics_process(delta: float) -> void:
	position += direction * speed * delta
	_life -= delta
	if _life <= 0.0:
		queue_free()


func burst() -> void:
	if is_queued_for_deletion():
		return
	var poof: Node2D = POOF.instantiate()
	poof.position = position
	poof.scale = Vector2(0.6, 0.6)
	get_parent().add_child.call_deferred(poof)
	queue_free()


func deflect() -> void:
	Sound.play(&"shield")
	burst()


func _on_body_entered(_body: Node2D) -> void:
	burst()
