extends Node2D
## Game flow and room logic.
##
## Flow: TITLE -> PLAY <-> (SCROLL | WARP | DIALOG | ITEM | PAUSED) -> GAME_OVER / VICTORY.
## The world is a grid of 16x11-tile rooms. The camera shows one room at a
## time; walking off an edge scrolls to the neighbour (overworld only), and
## each room re-spawns its enemies on entry, as in the 8-bit classics.

enum Flow { TITLE, PLAY, SCROLL, WARP, DIALOG, ITEM, PAUSED, GAME_OVER, VICTORY }

const ROOM_SIZE := Vector2(256, 176)
const HUD_HEIGHT := 48.0
## Rooms that make up the scrollable overworld; anything else (the cave) is
## only reachable through warps.
const OVERWORLD := Rect2i(0, 0, 3, 3)
const SCROLL_TIME := 0.6
## How far the hero walks into the next room while the screen scrolls.
const SCROLL_STEP := 22.0
const ENEMY_SCENES := {
	"slime": preload("res://scenes/actors/slime.tscn"),
	"spitter": preload("res://scenes/actors/spitter.tscn"),
}
const PICKUP := preload("res://scenes/objects/pickup.tscn")
const SWORD_TEXTURE := preload("res://assets/sprites/sword.png")
const ITEMS_TEXTURE := preload("res://assets/sprites/items.png")
const SUNSTONE_REGION := Rect2(64, 0, 16, 16)

var flow := Flow.TITLE
var room := Vector2i(1, 1)

## Room -> Array of [position, enemy kind], read from the world's spawn markers.
var _spawns := {}
## Room -> position where its clear-the-room key appears.
var _key_spots := {}
var _alive_in_room := 0

@onready var world: Node2D = $World
@onready var player: Player = $Actors/Player
@onready var room_actors: Node2D = $Actors/RoomActors
@onready var camera: Camera2D = $Camera
@onready var hud: CanvasLayer = $HUD
@onready var dialog: CanvasLayer = $DialogBox
@onready var overlay: CanvasLayer = $Overlay
@onready var sage: Node2D = world.get_node("Objects/Sage")


func _ready() -> void:
	_index_spawns()
	Game.reset()
	Game.enemy_died.connect(_on_enemy_died)
	Game.warp_requested.connect(_on_warp_requested)
	Game.item_collected.connect(_on_item_collected)
	Game.player_died.connect(_on_player_died)
	player.global_position = world.get_node("PlayerStart").global_position
	_enter_room(_room_at(player.global_position))
	if Game.skip_title:
		Game.skip_title = false
		_begin_play()
	else:
		player.freeze()
		hud.visible = false
		overlay.show_title()


func _physics_process(delta: float) -> void:
	if flow != Flow.PLAY:
		return
	Game.play_time += delta
	_check_room_exit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mute"):
		Sound.toggle_mute()
	elif event.is_action_pressed("fullscreen"):
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		var mode := DisplayServer.WINDOW_MODE_WINDOWED if fullscreen else DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(mode)
	match flow:
		Flow.TITLE:
			if event.is_action_pressed("confirm") or event.is_action_pressed("attack"):
				get_viewport().set_input_as_handled()
				Sound.play(&"start")
				_begin_play()
		Flow.PLAY:
			if event.is_action_pressed("pause"):
				_set_paused(true)
		Flow.PAUSED:
			if event.is_action_pressed("pause"):
				_set_paused(false)
		Flow.GAME_OVER, Flow.VICTORY:
			if overlay.accepting_input and event.is_action_pressed("confirm"):
				Game.skip_title = flow == Flow.GAME_OVER
				get_tree().reload_current_scene()


func _begin_play() -> void:
	overlay.hide_all()
	hud.visible = true
	flow = Flow.PLAY
	player.unfreeze()
	if not Game.has_sword:
		Game.toast("AN OLD SAGE WAITS IN THE CAVE.")


func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	flow = Flow.PAUSED if paused else Flow.PLAY
	overlay.show_paused(paused)
	Sound.play(&"pause")


# ------------------------------------------------------------------ rooms

func _index_spawns() -> void:
	for marker: Node2D in world.get_node("Spawns").get_children():
		var r := _room_at(marker.global_position)
		if marker.has_meta(&"enemy"):
			if not _spawns.has(r):
				_spawns[r] = []
			_spawns[r].append([marker.global_position, marker.get_meta(&"enemy")])
		elif marker.has_meta(&"key"):
			_key_spots[r] = marker.global_position


func _room_at(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / ROOM_SIZE.x), floori(point.y / ROOM_SIZE.y))


func _room_rect(r: Vector2i) -> Rect2:
	return Rect2(Vector2(r) * ROOM_SIZE, ROOM_SIZE)


func _camera_origin(r: Vector2i) -> Vector2:
	# The camera anchors top-left; the HUD covers the strip above the room.
	return Vector2(r) * ROOM_SIZE - Vector2(0, HUD_HEIGHT)


func _enter_room(r: Vector2i) -> void:
	room = r
	camera.position = _camera_origin(r)
	hud.set_room(r, OVERWORLD.has_point(r))
	Sound.play_music(&"overworld" if OVERWORLD.has_point(r) else &"cave")
	_alive_in_room = 0
	for spawn: Array in _spawns.get(r, []):
		var enemy: Enemy = ENEMY_SCENES[spawn[1]].instantiate()
		enemy.position = spawn[0]
		enemy.room_rect = _room_rect(r)
		room_actors.add_child(enemy)
		_alive_in_room += 1
	if _alive_in_room > 0:
		Sound.play(&"spawn")
	if Game.key_rooms.get(r) == &"dropped":
		_spawn_pickup(Pickup.Kind.KEY, _key_spots[r])


func _clear_room_actors() -> void:
	for child in room_actors.get_children():
		child.queue_free()


func _check_room_exit() -> void:
	var rect := _room_rect(room)
	var p := player.global_position
	var dir := Vector2i.ZERO
	if p.x < rect.position.x:
		dir = Vector2i.LEFT
	elif p.x > rect.end.x:
		dir = Vector2i.RIGHT
	elif p.y < rect.position.y:
		dir = Vector2i.UP
	elif p.y > rect.end.y:
		dir = Vector2i.DOWN
	if dir == Vector2i.ZERO:
		return
	if player.state == Player.State.WALK and OVERWORLD.has_point(room) and OVERWORLD.has_point(room + dir):
		_scroll(dir)
	else:
		# Knockback (or a gap in a map edge) must never carry the hero off-screen.
		player.global_position = p.clamp(rect.position, rect.end)


func _scroll(dir: Vector2i) -> void:
	flow = Flow.SCROLL
	player.freeze(true)
	dialog.hide_box()
	room_actors.process_mode = Node.PROCESS_MODE_DISABLED
	var next := room + dir
	var tween := create_tween().set_parallel(true)
	tween.tween_property(camera, "position", _camera_origin(next), SCROLL_TIME)
	tween.tween_property(player, "global_position", player.global_position + Vector2(dir) * SCROLL_STEP, SCROLL_TIME)
	await tween.finished
	_clear_room_actors()
	room_actors.process_mode = Node.PROCESS_MODE_INHERIT
	_enter_room(next)
	player.unfreeze()
	flow = Flow.PLAY


func _spawn_pickup(kind: Pickup.Kind, at: Vector2) -> void:
	var pickup: Pickup = PICKUP.instantiate()
	pickup.kind = kind
	pickup.position = at
	room_actors.add_child.call_deferred(pickup)


# ----------------------------------------------------------------- events

func _on_enemy_died(_enemy: Node) -> void:
	_alive_in_room -= 1
	if _alive_in_room <= 0 and _key_spots.has(room) and not Game.key_rooms.has(room):
		Game.key_rooms[room] = &"dropped"
		Sound.play(&"key")
		_spawn_pickup(Pickup.Kind.KEY, _key_spots[room])


func _on_warp_requested(warp: Node) -> void:
	if flow != Flow.PLAY:
		return
	flow = Flow.WARP
	player.freeze()
	dialog.hide_box()
	Sound.play(&"stairs")
	await overlay.fade_out(0.3)
	_clear_room_actors()
	player.global_position = warp.target
	player.facing = warp.arrive_facing
	_enter_room(_room_at(warp.target))
	await overlay.fade_in(0.3)
	player.unfreeze()
	flow = Flow.PLAY
	if _room_at(sage.global_position) == room:
		_talk(sage.lines_after if Game.has_sword else sage.lines)


func _on_item_collected(kind: StringName, _at: Vector2) -> void:
	match kind:
		&"key":
			Game.key_rooms[room] = &"taken"
		&"sword":
			await _fanfare(SWORD_TEXTURE, Rect2(0, 0, 16, 16))
			_talk(sage.lines_after)
		&"relic":
			_victory()


func _on_player_died() -> void:
	flow = Flow.GAME_OVER
	overlay.accepting_input = false
	dialog.hide_box()
	room_actors.process_mode = Node.PROCESS_MODE_DISABLED
	Sound.stop_music()
	await get_tree().create_timer(1.4).timeout  # let the hero spin
	Sound.play(&"game_over")
	overlay.show_game_over()
	await get_tree().create_timer(0.8).timeout
	overlay.accepting_input = true


func _talk(text: String) -> void:
	flow = Flow.DIALOG
	player.freeze()
	await dialog.type_text(text)
	if flow == Flow.DIALOG:
		player.unfreeze()
		flow = Flow.PLAY


func _fanfare(texture: Texture2D, region: Rect2) -> void:
	flow = Flow.ITEM
	dialog.hide_box()
	player.hold_up(texture, region)
	Sound.duck_music(1.2)
	Sound.play(&"item_get")
	await get_tree().create_timer(1.3).timeout
	player.lower_item()
	flow = Flow.PLAY


func _victory() -> void:
	flow = Flow.VICTORY
	overlay.accepting_input = false
	dialog.hide_box()
	room_actors.process_mode = Node.PROCESS_MODE_DISABLED
	player.hold_up(ITEMS_TEXTURE, SUNSTONE_REGION)
	Sound.stop_music()
	Sound.play(&"victory")
	await get_tree().create_timer(3.2).timeout
	overlay.show_victory("TIME   %s\nGEMS   %03d\nFOES   %d" % [Game.format_time(), Game.gems, Game.foes_defeated])
	await get_tree().create_timer(0.8).timeout
	overlay.accepting_input = true
