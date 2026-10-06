extends Node
## Run state for one playthrough, plus the event bus scenes use to talk to
## the game flow (scripts/main.gd) without holding references to each other.

signal hp_changed(hp: int, max_hp: int)
signal gems_changed(gems: int)
signal keys_changed(keys: int)
signal sword_changed(has_sword: bool)
signal item_collected(kind: StringName, at: Vector2)
signal enemy_died(enemy: Node)
signal warp_requested(warp: Node)
signal toast_requested(text: String)
signal player_died

## Health is counted in half hearts: 6 = three full hearts.
const START_HP := 6

var max_hp := START_HP
var hp := START_HP
var gems := 0
var keys := 0
var has_sword := false
var foes_defeated := 0
var play_time := 0.0
## Rooms whose clear-the-room key has dropped: Vector2i -> &"dropped" | &"taken".
var key_rooms := {}
## Set before reloading the scene so a retry skips the title screen.
var skip_title := false


func reset() -> void:
	max_hp = START_HP
	hp = START_HP
	gems = 0
	keys = 0
	has_sword = false
	foes_defeated = 0
	play_time = 0.0
	key_rooms.clear()
	hp_changed.emit(hp, max_hp)
	gems_changed.emit(gems)
	keys_changed.emit(keys)
	sword_changed.emit(has_sword)


func damage(amount: int) -> void:
	if hp <= 0:
		return
	hp = maxi(hp - amount, 0)
	hp_changed.emit(hp, max_hp)
	if hp == 0:
		player_died.emit()


func heal(amount: int) -> void:
	hp = mini(hp + amount, max_hp)
	hp_changed.emit(hp, max_hp)


func add_gems(amount: int) -> void:
	gems = mini(gems + amount, 999)
	gems_changed.emit(gems)


func add_key() -> void:
	keys += 1
	keys_changed.emit(keys)


## Spends a key if one is held.
func use_key() -> bool:
	if keys <= 0:
		return false
	keys -= 1
	keys_changed.emit(keys)
	return true


func give_sword() -> void:
	has_sword = true
	sword_changed.emit(true)


func toast(text: String) -> void:
	toast_requested.emit(text)


func format_time() -> String:
	var t := int(play_time)
	return "%02d:%02d" % [floori(t / 60.0), t % 60]
