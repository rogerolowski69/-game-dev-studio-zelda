class_name Player
extends CharacterBody2D
## The hero: 8-way movement with 4-way facing, a sword swing, knockback with
## invulnerability frames, a front-facing shield that blocks rocks, and the
## "hold the item overhead" pose.

enum State { IDLE, WALK, ATTACK, HURT, ITEM, DEAD, FROZEN }

const SPEED := 80.0
const ATTACK_TIME := 0.26
const SWORD_ACTIVE_TIME := 0.18
const KNOCKBACK_SPEED := 200.0
const KNOCKBACK_TIME := 0.15
const INVULNERABLE_TIME := 1.0
## Pixels of misalignment forgiven when walking into a gap: instead of
## snagging on a tile corner the hero slides around it.
const CORNER_SLIDE := 6

const WALK_FRAMES := {Vector2i.DOWN: 0, Vector2i.UP: 2, Vector2i.RIGHT: 4, Vector2i.LEFT: 4}
const ATTACK_FRAMES := {Vector2i.DOWN: 6, Vector2i.UP: 7, Vector2i.RIGHT: 8, Vector2i.LEFT: 8}
const ITEM_FRAME := 9
## Where the (upward-pointing) sword sprite goes for each facing: [offset, rotation].
const SWORD_POSES := {
	Vector2i.UP: [Vector2(1, -12), 0.0],
	Vector2i.DOWN: [Vector2(-1, 12), PI],
	Vector2i.RIGHT: [Vector2(12, 2), PI / 2.0],
	Vector2i.LEFT: [Vector2(-12, 2), -PI / 2.0],
}
const DEATH_SPIN: Array[Vector2i] = [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]

var state := State.IDLE
var facing := Vector2i.DOWN

var _state_time := 0.0
var _anim_time := 0.0
var _invulnerable := 0.0
var _knockback := Vector2.ZERO
var _swing_hits: Array[Node] = []
var _walk_while_frozen := false

@onready var sprite: Sprite2D = $Sprite
@onready var sword: Node2D = $Sword
@onready var sword_hitbox: Area2D = $Sword/Hitbox
@onready var hurtbox: Area2D = $Hurtbox
@onready var held_item: Sprite2D = $HeldItem


func _physics_process(delta: float) -> void:
	_state_time += delta
	match state:
		State.IDLE, State.WALK:
			_step_free(delta)
		State.ATTACK:
			_step_attack()
		State.HURT:
			velocity = _knockback
			move_and_slide()
			if _state_time >= KNOCKBACK_TIME:
				_set_state(State.IDLE)
		_:
			velocity = Vector2.ZERO
	if _invulnerable > 0.0:
		_invulnerable -= delta
	_check_hurtbox()
	_update_sprite(delta)


func can_collect() -> bool:
	return state != State.DEAD and state != State.ITEM


## Stop all control (dialog, warps, scrolling). ``walking`` keeps the walk cycle going.
func freeze(walking: bool = false) -> void:
	_end_attack()
	_walk_while_frozen = walking
	_set_state(State.FROZEN)


func unfreeze() -> void:
	if state == State.FROZEN:
		_set_state(State.IDLE)


func hold_up(texture: Texture2D, region: Rect2) -> void:
	_end_attack()
	held_item.texture = texture
	held_item.region_rect = region
	held_item.visible = true
	_set_state(State.ITEM)


func lower_item() -> void:
	held_item.visible = false
	if state == State.ITEM:
		_set_state(State.IDLE)


func _set_state(new_state: State) -> void:
	state = new_state
	_state_time = 0.0


func _step_free(delta: float) -> void:
	if Game.has_sword and Input.is_action_just_pressed("attack"):
		_start_attack()
		return
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir == Vector2.ZERO:
		velocity = Vector2.ZERO
		state = State.IDLE
		return
	state = State.WALK
	_face(dir)
	dir = dir.normalized()
	velocity = dir * SPEED
	if move_and_slide() and (is_zero_approx(dir.x) or is_zero_approx(dir.y)):
		_slide_around_corner(dir, delta)


func _face(dir: Vector2) -> void:
	# Keep the current facing while that direction is still held, so moving
	# diagonally doesn't flicker between two facings.
	if (facing.x != 0 and signf(dir.x) == facing.x) or (facing.y != 0 and signf(dir.y) == facing.y):
		return
	if absf(dir.x) > absf(dir.y):
		facing = Vector2i(int(signf(dir.x)), 0)
	else:
		facing = Vector2i(0, int(signf(dir.y)))


func _slide_around_corner(dir: Vector2, delta: float) -> void:
	var across := Vector2(absf(dir.y), absf(dir.x))
	for offset in range(1, CORNER_SLIDE + 1):
		for side: float in [-1.0, 1.0]:
			var shift := across * offset * side
			if test_move(global_transform, shift):
				continue
			if not test_move(global_transform.translated(shift), dir * 2.0):
				move_and_collide(across * side * minf(SPEED * delta, offset))
				return


func _start_attack() -> void:
	_set_state(State.ATTACK)
	velocity = Vector2.ZERO
	_swing_hits.clear()
	var pose: Array = SWORD_POSES[facing]
	sword.position = pose[0]
	sword.rotation = pose[1]
	sword.visible = true
	sword_hitbox.monitoring = true
	Sound.play(&"sword", 0.06)


func _step_attack() -> void:
	velocity = Vector2.ZERO
	if sword_hitbox.monitoring:
		for area in sword_hitbox.get_overlapping_areas():
			var target := area.owner
			if target and target.has_method(&"take_hit") and not _swing_hits.has(target):
				_swing_hits.append(target)
				target.take_hit(1, Vector2(facing))
		if _state_time >= SWORD_ACTIVE_TIME:
			sword_hitbox.set_deferred(&"monitoring", false)
	if _state_time >= ATTACK_TIME:
		_end_attack()
		_set_state(State.IDLE)


func _end_attack() -> void:
	sword.visible = false
	sword_hitbox.set_deferred(&"monitoring", false)


func _check_hurtbox() -> void:
	if _invulnerable > 0.0 or state in [State.ITEM, State.DEAD, State.FROZEN]:
		return
	for area in hurtbox.get_overlapping_areas():
		if area is Projectile:
			var rock := area as Projectile
			if state != State.ATTACK and Vector2(facing).dot(rock.direction) < -0.7:
				rock.deflect()
				continue
			rock.burst()
			_take_damage(rock.damage, rock.global_position)
			return
		var enemy := area.owner as Enemy
		if enemy and enemy.is_dangerous():
			_take_damage(enemy.contact_damage, enemy.global_position)
			return


func _take_damage(amount: int, source: Vector2) -> void:
	_end_attack()
	_invulnerable = INVULNERABLE_TIME
	Sound.play(&"hurt")
	if Game.hp <= amount:
		_set_state(State.DEAD)
	Game.damage(amount)
	if state == State.DEAD:
		return
	# Knocked straight back along one axis, like the 8-bit classics.
	var away := global_position - source
	if absf(away.x) > absf(away.y):
		_knockback = Vector2(signf(away.x), 0.0) * KNOCKBACK_SPEED
	else:
		_knockback = Vector2(0.0, signf(away.y)) * KNOCKBACK_SPEED
	if _knockback == Vector2.ZERO:
		_knockback = -Vector2(facing) * KNOCKBACK_SPEED
	_set_state(State.HURT)


func _update_sprite(delta: float) -> void:
	var blinking := _invulnerable > 0.0 and state != State.DEAD
	sprite.visible = not blinking or fmod(_invulnerable, 0.1) < 0.06
	var frame: int = WALK_FRAMES[facing]
	match state:
		State.ATTACK:
			frame = ATTACK_FRAMES[facing]
		State.ITEM:
			frame = ITEM_FRAME
		State.DEAD:
			facing = DEATH_SPIN[int(_state_time / 0.07) % 4] if _state_time < 1.1 else Vector2i.DOWN
			frame = WALK_FRAMES[facing]
		State.WALK:
			_anim_time += delta
			frame += int(_anim_time * 8.0) % 2
		State.FROZEN:
			if _walk_while_frozen:
				_anim_time += delta
				frame += int(_anim_time * 8.0) % 2
	sprite.frame = frame
	sprite.flip_h = facing == Vector2i.LEFT and state != State.ITEM
