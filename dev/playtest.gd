extends Node
## End-to-end playtest. Plays the whole quest through the real game scene
## with simulated input and asserts on game state at every step.
##
## Headless (fast, deterministic):
##   godot --headless --fixed-fps 60 --path . res://dev/playtest.tscn
## With screenshots (needs a renderer, e.g. under xvfb-run):
##   godot --fixed-fps 60 --path . res://dev/playtest.tscn -- --shots=/abs/dir
##
## Exits with code 0 when every check passes, 1 otherwise.

const MAIN_SCENE := "res://scenes/main.tscn"
const PROJECTILE := preload("res://scenes/actors/projectile.tscn")
const Main := preload("res://scripts/main.gd")

var _shots_dir := ""
var _passed := 0
var _failed: PackedStringArray = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")
			DirAccess.make_dir_recursive_absolute(_shots_dir)
	# Run from the root so the driver survives the game's own scene reloads.
	var driver := Node.new()
	driver.name = "PlaytestDriver"
	driver.set_script(get_script())
	driver.set_meta(&"driver", true)
	if has_meta(&"driver"):
		_run.call_deferred()
		return
	get_tree().root.add_child.call_deferred(driver)
	get_tree().change_scene_to_file.call_deferred(MAIN_SCENE)


func main() -> Node:
	return get_tree().current_scene


func _run() -> void:
	await _until(func() -> bool: return main() != null and main().name == "Main", 5.0)
	await _frames(10)
	await _title_and_cave()
	await _sword()
	await _scroll_and_fight()
	await _shield_and_damage()
	await _key_room()
	await _shrine_and_victory()
	await _pause_game_over_and_retry()
	_check(Sound._music.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "music loops (WAV smpl chunk detected)")
	var verdict := "PASS" if _failed.is_empty() else "FAIL"
	print("\n==== PLAYTEST %s: %d passed, %d failed ====" % [verdict, _passed, _failed.size()])
	for failure in _failed:
		print("  FAILED: ", failure)
	get_tree().quit(0 if _failed.is_empty() else 1)


# ------------------------------------------------------------------ steps

func _title_and_cave() -> void:
	_check(main().flow == Main.Flow.TITLE, "game boots to the title screen")
	_check(main().overlay.title.visible, "title card visible")
	await _shot("01_title")
	_tap("confirm")
	await _frames(5)
	_check(main().flow == Main.Flow.PLAY, "confirm starts the game")
	_check(main().room == Vector2i(1, 1), "hero starts in the central room")
	await _seconds(0.5)
	await _shot("02_start_room")
	# Walk to the cave doorway: up the path, left along the cliff, then in.
	await _walk("move_up", func() -> bool: return main().player.global_position.y <= 216.0, 5.0)
	await _walk("move_left", func() -> bool: return main().player.global_position.x <= 296.0, 5.0)
	await _walk("move_up", func() -> bool: return main().flow == Main.Flow.WARP, 3.0)
	_check(main().flow == Main.Flow.WARP, "walking into the doorway starts a warp")
	await _until(func() -> bool: return main().flow == Main.Flow.DIALOG, 3.0)
	_check(main().room == Vector2i(4, 1), "warp lands in the cave")
	_check(main().dialog.box.visible, "the sage starts talking")
	await _seconds(1.2)
	await _shot("03_cave_dialog")
	await _until(func() -> bool: return main().flow == Main.Flow.PLAY, 6.0)


func _sword() -> void:
	await _walk("move_up", func() -> bool: return Game.has_sword, 3.0)
	_check(Game.has_sword, "walking onto the sword picks it up")
	await _frames(20)
	_check(main().flow == Main.Flow.ITEM and main().player.state == Player.State.ITEM, "item fanfare pose")
	await _shot("04_item_get")
	await _until(func() -> bool: return main().flow == Main.Flow.PLAY, 10.0)
	_check(main().dialog.label.text.begins_with("THE SUNSTONE"), "sage gives the quest hint after the sword")
	await _walk("move_down", func() -> bool: return main().room == Vector2i(1, 1) and main().flow == Main.Flow.PLAY, 6.0)
	_check(main().room == Vector2i(1, 1), "cave exit returns to the overworld")
	_check(main().player.global_position.distance_to(Vector2(296, 216)) < 4.0, "hero reappears below the doorway")


func _scroll_and_fight() -> void:
	await _walk("move_down", func() -> bool: return main().player.global_position.y >= 264.0, 3.0)
	await _walk("move_right", func() -> bool: return main().flow == Main.Flow.SCROLL, 6.0)
	_check(main().flow == Main.Flow.SCROLL, "walking off the east edge scrolls the screen")
	await _seconds(0.3)
	await _shot("05_scrolling")
	await _until(func() -> bool: return main().flow == Main.Flow.PLAY, 3.0)
	_check(main().room == Vector2i(2, 1), "scroll lands in the east room")
	_check(main().camera.position == Vector2(512, 128), "camera snapped to the room")
	_check(_enemies().size() == 4, "east room spawns its 4 enemies (got %d)" % _enemies().size())
	await _seconds(0.8)
	await _shot("06_stonefield")
	var target: Enemy = _enemies()[0]
	var hp_before := target.hp
	await _swing_at(target)
	_check(not is_instance_valid(target) or target.hp < hp_before, "a sword swing damages an enemy")
	var defeated := Game.foes_defeated
	await _clear_room()
	_check(_enemies().is_empty(), "all enemies in the room can be defeated")
	_check(Game.foes_defeated - defeated >= 3, "defeated enemies are counted")


func _shield_and_damage() -> void:
	await _teleport(Vector2(392, 264))
	var hero: Player = main().player
	hero.facing = Vector2i.UP
	Game.heal(99)
	var hp := Game.hp
	_fire_rock_at_hero(Vector2.DOWN)
	await _seconds(0.6)
	_check(Game.hp == hp, "a rock hitting the shield from the front is blocked")
	hero.facing = Vector2i.DOWN
	_fire_rock_at_hero(Vector2.DOWN)
	await _seconds(0.6)
	_check(Game.hp == hp - 1, "a rock from behind costs half a heart")
	_check(hero.state == Player.State.HURT or hero.state == Player.State.IDLE, "hit hero is knocked back then recovers")
	await _seconds(1.2)


func _key_room() -> void:
	await _teleport(Vector2(632, 300))   # east room, near its south opening
	await _clear_room()
	main().player.global_position = Vector2(632, 300)  # fighting moved the hero around
	await _walk("move_down", func() -> bool: return main().flow == Main.Flow.SCROLL, 4.0)
	await _until(func() -> bool: return main().flow == Main.Flow.PLAY, 3.0)
	_check(main().room == Vector2i(2, 2), "scrolling south reaches the graveyard")
	await _seconds(0.6)
	_check(_enemies().size() == 4, "graveyard spawns 4 guardians (got %d)" % _enemies().size())
	await _clear_room(main()._key_spots[Vector2i(2, 2)])
	await _frames(5)
	var keys: Array = main().room_actors.get_children().filter(func(n: Node) -> bool:
		return n is Pickup and n.kind == Pickup.Kind.KEY)
	_check(Game.key_rooms.get(Vector2i(2, 2)) == &"dropped" and keys.size() == 1, "clearing the graveyard drops a key")
	await _shot("07_key_drop")
	if not keys.is_empty():
		main().player.global_position = keys[0].global_position + Vector2(0, 14)
		await _walk("move_up", func() -> bool: return Game.keys == 1, 2.0)
	_check(Game.keys == 1, "the key is collected")


func _shrine_and_victory() -> void:
	await _teleport(Vector2(384, 120))   # path below the shrine gate
	await _walk("move_up", func() -> bool: return Game.keys == 0, 3.0)
	_check(Game.keys == 0, "touching the gate spends the key")
	await _seconds(0.25)
	await _shot("08_gate_opening")
	await _walk("move_up", func() -> bool: return main().flow == Main.Flow.VICTORY, 4.0)
	_check(main().flow == Main.Flow.VICTORY, "taking the Sunstone wins the game")
	await _seconds(1.0)
	await _shot("09_sunstone")
	await _until(func() -> bool: return main().overlay.accepting_input, 6.0)
	_check(main().overlay.victory.visible, "victory screen shown")
	await _shot("10_victory")
	_tap("confirm")
	await _until(func() -> bool: return main() != null and main().name == "Main" and main().is_node_ready(), 5.0)
	await _frames(10)
	_check(main().flow == Main.Flow.TITLE, "play again returns to the title")
	_check(not Game.has_sword and Game.gems == 0, "a new game resets progress")


func _pause_game_over_and_retry() -> void:
	_tap("confirm")
	await _frames(5)
	_tap("pause")
	await _frames(3)
	_check(get_tree().paused and main().flow == Main.Flow.PAUSED, "pause freezes the game")
	await _shot("11_paused")
	_tap("pause")
	await _frames(3)
	_check(not get_tree().paused and main().flow == Main.Flow.PLAY, "pause again resumes")
	# Die on purpose: one heart left, then stand inside a slime.
	await _teleport(Vector2(120, 248))   # lake room
	Game.damage(Game.hp - 1)
	var slime: Enemy = _enemies()[0]
	main().player.global_position = slime.global_position
	await _until(func() -> bool: return main().flow == Main.Flow.GAME_OVER, 3.0)
	_check(main().flow == Main.Flow.GAME_OVER, "losing the last heart ends the game")
	await _until(func() -> bool: return main().overlay.accepting_input, 5.0)
	await _shot("12_game_over")
	_tap("confirm")
	await _until(func() -> bool: return main() != null and main().name == "Main" and main().is_node_ready(), 5.0)
	await _frames(10)
	_check(main().flow == Main.Flow.PLAY, "retry skips the title and starts playing")
	_check(Game.hp == Game.max_hp, "retry restores full health")


# ---------------------------------------------------------------- helpers

func _enemies() -> Array:
	return main().room_actors.get_children().filter(func(n: Node) -> bool:
		return n is Enemy and n.state != Enemy.State.DEAD)


func _teleport(world_pos: Vector2) -> void:
	var m := main()
	m._clear_room_actors()
	m.player.global_position = world_pos
	m._enter_room(m._room_at(world_pos))
	await _seconds(0.6)  # enemies finish their spawn puff


## Freeze ``enemy`` and swing at it from the side facing away from ``keep_clear``.
func _swing_at(enemy: Enemy, keep_clear := Vector2(-1e6, 0)) -> void:
	enemy.set_physics_process(false)  # hold still for the swing
	var side := 1.0 if enemy.global_position.x >= keep_clear.x else -1.0
	main().player.global_position = enemy.global_position + Vector2(13.0 * side, 0)
	main().player.facing = Vector2i(int(-side), 0)
	await _frames(2)
	_tap("attack")
	await _seconds(0.35)
	if is_instance_valid(enemy):
		enemy.set_physics_process(true)


func _clear_room(keep_clear := Vector2(-1e6, 0)) -> void:
	for attempt in 40:
		var alive := _enemies().filter(func(e: Enemy) -> bool: return e.is_dangerous())
		if alive.is_empty():
			break
		Game.heal(99)
		await _swing_at(alive[0], keep_clear)
		await _seconds(0.2)


func _fire_rock_at_hero(direction: Vector2) -> void:
	var rock: Projectile = PROJECTILE.instantiate()
	rock.direction = direction
	rock.position = main().player.position - direction * 40.0
	main().room_actors.add_child(rock)


func _walk(action: StringName, done: Callable, timeout: float) -> void:
	Input.action_press(action)
	await _until(done, timeout)
	Input.action_release(action)
	await _frames(1)


func _tap(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	await _frames(1)
	var release := InputEventAction.new()
	release.action = action
	Input.parse_input_event(release)


func _until(condition: Callable, timeout: float) -> bool:
	var waited := 0.0
	while not condition.call():
		if waited >= timeout:
			return false
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	return true


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _seconds(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, true).timeout


func _check(ok: bool, label: String) -> void:
	var stamp := "[%6.2fs]" % (Engine.get_physics_frames() / float(Engine.physics_ticks_per_second))
	if ok:
		_passed += 1
		print("  ok   %s %s" % [stamp, label])
	else:
		_failed.append(label)
		print("  FAIL %s %s" % [stamp, label])


func _shot(shot_name: String) -> void:
	if _shots_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.resize(image.get_width() * 3, image.get_height() * 3, Image.INTERPOLATE_NEAREST)
	image.save_png(_shots_dir.path_join(shot_name + ".png"))
