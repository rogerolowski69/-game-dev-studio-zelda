class_name Pickup
extends Area2D
## Hearts, gems, keys, the sword and the Sunstone. Dropped loot hops in and
## blinks out after a while; items placed in the world stay until collected.

enum Kind { HEART, GEM, BIG_GEM, KEY, SWORD, RELIC }

const ITEMS := preload("res://assets/sprites/items.png")
const SWORD_TEXTURE := preload("res://assets/sprites/sword.png")
## Frame index of each kind inside items.png (16x16 cells in one row).
const ITEM_FRAME := {Kind.HEART: 0, Kind.GEM: 1, Kind.BIG_GEM: 2, Kind.KEY: 3, Kind.RELIC: 4}
const NAMES := {Kind.HEART: &"heart", Kind.GEM: &"gem", Kind.BIG_GEM: &"big_gem", Kind.KEY: &"key",
	Kind.SWORD: &"sword", Kind.RELIC: &"relic"}
const LIFETIME := 9.0

@export var kind := Kind.GEM
## Dropped loot disappears after LIFETIME seconds.
@export var expires := false

var _age := 0.0

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	if kind == Kind.SWORD:
		sprite.texture = SWORD_TEXTURE
		sprite.region_enabled = false
	else:
		sprite.texture = ITEMS
		sprite.region_enabled = true
		sprite.region_rect = Rect2(ITEM_FRAME[kind] * 16, 0, 16, 16)
	body_entered.connect(_on_body_entered)
	if expires:
		var hop := create_tween()
		hop.tween_property(sprite, "position:y", -6.0, 0.12).set_ease(Tween.EASE_OUT)
		hop.tween_property(sprite, "position:y", 0.0, 0.18).set_ease(Tween.EASE_IN)
	elif kind == Kind.RELIC:
		var bob := create_tween().set_loops()
		bob.tween_property(sprite, "position:y", -2.0, 0.6)
		bob.tween_property(sprite, "position:y", 0.0, 0.6)


func _process(delta: float) -> void:
	if not expires:
		return
	_age += delta
	if _age > LIFETIME - 2.5:
		sprite.visible = fmod(_age, 0.2) < 0.12
	if _age >= LIFETIME:
		queue_free()


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if player == null or not player.can_collect():
		return
	match kind:
		Kind.HEART:
			Game.heal(2)
			Sound.play(&"heart")
		Kind.GEM:
			Game.add_gems(1)
			Sound.play(&"gem")
		Kind.BIG_GEM:
			Game.add_gems(5)
			Sound.play(&"gem")
		Kind.KEY:
			Game.add_key()
			Sound.play(&"heart")
		Kind.SWORD:
			Game.give_sword()
	Game.item_collected.emit(NAMES[kind], global_position)
	queue_free()
