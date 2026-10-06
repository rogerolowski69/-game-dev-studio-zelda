class_name Enemy
extends CharacterBody2D
## Shared enemy brain: a spawn puff, random cardinal wandering confined to its
## room, optional chasing (slimes) and rock-spitting (spitters), knockback on
## hit, and a loot roll on death. Variants are configured by the exports.

enum State { SPAWN, WANDER, PAUSE, SHOOT, HURT, DEAD }

const PROJECTILE := preload("res://scenes/actors/projectile.tscn")
const POOF := preload("res://scenes/fx/poof.tscn")
const PICKUP := preload("res://scenes/objects/pickup.tscn")
const DIRECTIONS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]

@export var max_hp := 2
@export var speed := 30.0
## Damage dealt on touch, in half hearts.
@export var contact_damage := 1
## Chance to step toward the hero whenever a new direction is picked.
@export_range(0.0, 1.0) var chase_chance := 0.0
@export var shoots := false
## Rotate the sprite toward the travel direction (the art faces down).
@export var rotates := false
@export var anim_fps := 4.0

## Assigned by the spawner. The enemy never wanders outside it.
var room_rect := Rect2(-1e6, -1e6, 2e6, 2e6)
var hp := 0
var dir := Vector2.DOWN
var state := State.SPAWN

var _state_time := 0.0
var _state_length := 0.0
var _knockback := Vector2.ZERO
var _anim_time := 0.0
var _has_fired := false

@onready var sprite: Sprite2D = $Sprite
@onready var hurtbox: Area2D = $Hurtbox


func _ready() -> void:
	hp = max_hp
	_anim_time = randf()
	sprite.visible = false
	hurtbox.monitorable = false
	add_child(POOF.instantiate())
	_enter(State.SPAWN, 0.4)


func is_dangerous() -> bool:
	return state != State.SPAWN and state != State.DEAD


func take_hit(damage: int, push: Vector2) -> void:
	if not is_dangerous() or state == State.HURT:
		return
	hp -= damage
	sprite.modulate = Color(4, 4, 4)
	create_tween().tween_property(sprite, "modulate", Color.WHITE, 0.2)
	if hp <= 0:
		_die()
		return
	Sound.play(&"hit")
	_knockback = push * 170.0
	_enter(State.HURT, 0.14)


func _physics_process(delta: float) -> void:
	_state_time += delta
	match state:
		State.SPAWN:
			if _state_time >= _state_length:
				sprite.visible = true
				hurtbox.monitorable = true
				_pick_direction()
				_enter(State.WANDER, randf_range(0.5, 1.4))
		State.WANDER:
			velocity = dir * speed
			if move_and_slide() or not _inside(global_position + dir * 6.0):
				_pick_direction()
			if _state_time >= _state_length:
				if shoots and randf() < 0.55:
					_aim_at_player(0.7)
					_has_fired = false
					_enter(State.SHOOT, 0.55)
				else:
					_enter(State.PAUSE, randf_range(0.2, 0.6))
		State.PAUSE:
			velocity = Vector2.ZERO
			if _state_time >= _state_length:
				_pick_direction()
				_enter(State.WANDER, randf_range(0.6, 1.6))
		State.SHOOT:
			velocity = Vector2.ZERO
			if not _has_fired and _state_time >= 0.25:
				_has_fired = true
				_fire()
			if _state_time >= _state_length:
				_enter(State.PAUSE, 0.3)
		State.HURT:
			velocity = _knockback
			move_and_slide()
			global_position = global_position.clamp(room_rect.position + Vector2(8, 8), room_rect.end - Vector2(8, 8))
			if _state_time >= _state_length:
				_enter(State.PAUSE, 0.25)
	_animate(delta)


func _enter(new_state: State, length: float) -> void:
	state = new_state
	_state_time = 0.0
	_state_length = length


func _inside(point: Vector2) -> bool:
	return room_rect.grow(-12.0).has_point(point)


func _player() -> Node2D:
	return get_tree().get_first_node_in_group(&"player") as Node2D


func _pick_direction() -> void:
	if randf() < chase_chance and _aim_at_player(1.0):
		return
	var open := DIRECTIONS.filter(func(d: Vector2) -> bool:
		return _inside(global_position + d * 8.0) and not test_move(global_transform, d * 4.0))
	dir = open.pick_random() if not open.is_empty() else DIRECTIONS.pick_random()


## Turn toward the hero along the dominant axis (with some probability).
func _aim_at_player(chance: float) -> bool:
	var player := _player()
	if player == null or randf() > chance:
		return false
	var to_player := player.global_position - global_position
	var aim := Vector2(signf(to_player.x), 0.0)
	if absf(to_player.y) >= absf(to_player.x):
		aim = Vector2(0.0, signf(to_player.y))
	if aim == Vector2.ZERO or not _inside(global_position + aim * 8.0):
		return false
	dir = aim
	return true


func _fire() -> void:
	var rock: Projectile = PROJECTILE.instantiate()
	rock.direction = dir
	rock.position = position + dir * 8.0
	get_parent().add_child(rock)
	Sound.play(&"shoot")


func _die() -> void:
	_enter(State.DEAD, 0.0)
	hurtbox.set_deferred(&"monitorable", false)
	Sound.play(&"enemy_die")
	var poof := POOF.instantiate()
	poof.position = position
	get_parent().add_child.call_deferred(poof)
	_drop_loot()
	Game.foes_defeated += 1
	Game.enemy_died.emit(self)
	queue_free()


func _drop_loot() -> void:
	var roll := randf()
	var kind := -1
	if roll < 0.06:
		kind = Pickup.Kind.BIG_GEM
	elif roll < 0.42:
		kind = Pickup.Kind.GEM
	elif roll < 0.62:
		kind = Pickup.Kind.HEART
	if kind < 0:
		return
	var loot: Pickup = PICKUP.instantiate()
	loot.kind = kind as Pickup.Kind
	loot.expires = true
	loot.position = position
	get_parent().add_child.call_deferred(loot)


func _animate(delta: float) -> void:
	_anim_time += delta
	var fps := anim_fps * (1.8 if state == State.WANDER else 1.0)
	sprite.frame = int(_anim_time * fps) % 2
	if rotates:
		sprite.rotation = dir.angle() - PI / 2.0
