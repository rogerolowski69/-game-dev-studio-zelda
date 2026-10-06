extends Node
# Review harness: drives the real Main.tscn headless and prints measurements.

func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func _ready() -> void:
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main)
	await _frames(5)
	var player: CharacterBody3D = get_tree().get_first_node_in_group("player")
	var enemies: Array = [main.get_node("Enemy"), main.get_node("Enemy2")]
	for e in enemies:  # park enemies out of the way
		e.set_physics_process(false)
		e.global_position = Vector3(18, 0, -18)

	# --- TEST 1: hold W (move_forward) for 2 s with the scene exactly as authored
	print("TEST1 hold move_forward 2.0s (scene as authored)")
	var p0 := player.global_position
	Input.action_press("move_forward")
	for i in 8:
		await get_tree().create_timer(0.25).timeout
		print("  t=%.2fs yaw=%7.1f deg  pos=(%6.2f, %6.2f)  straight-line dist from start=%.2f m" % [
			(i + 1) * 0.25, rad_to_deg(wrapf(player.rotation.y, -PI, PI)),
			player.global_position.x, player.global_position.z, player.global_position.distance_to(p0)])
	Input.action_release("move_forward")
	await _frames(30)

	# --- TEST 1b: same input after detaching the camera rig from the body's rotation
	print("TEST1b same, with CameraPivot.top_level = true (candidate fix)")
	player.rotation = Vector3.ZERO
	player.global_position = Vector3(0, 0.05, 15)
	var pivot: Node3D = player.get_node("CameraPivot")
	pivot.top_level = true
	pivot.global_basis = Basis.IDENTITY
	await _frames(5)
	p0 = player.global_position
	Input.action_press("move_forward")
	for i in 4:
		await get_tree().create_timer(0.5).timeout
		print("  t=%.2fs yaw=%7.1f deg  pos=(%6.2f, %6.2f)  dist=%.2f m" % [
			(i + 1) * 0.5, rad_to_deg(wrapf(player.rotation.y, -PI, PI)),
			player.global_position.x, player.global_position.z, player.global_position.distance_to(p0)])
	Input.action_release("move_forward")
	await _frames(30)

	# --- TEST 2: walk at an enemy, swing; then put the enemy behind and swing
	var target: CharacterBody3D = enemies[0]
	player.rotation = Vector3.ZERO
	player.global_position = Vector3(0, 0.05, 12)
	target.global_position = Vector3(0, 0, 9)  # 3 m ahead, in the direction W walks (-Z)
	await _frames(5)
	Input.action_press("move_forward")
	while Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(0, 9)) > 1.5:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	await _frames(40)
	var to_enemy: Vector3 = (target.global_position - player.global_position) * Vector3(1, 0, 1)
	var sword_dir: Vector3 = (player.get_node("SwordHitbox").global_position - player.global_position) * Vector3(1, 0, 1)
	print("TEST2 player walked toward enemy: yaw=%.1f deg, dot(sword offset, to_enemy)=%.2f (negative = sword points away)" % [
		rad_to_deg(wrapf(player.rotation.y, -PI, PI)), sword_dir.normalized().dot(to_enemy.normalized())])
	var hp: int = target.health
	player._start_attack()
	await _frames(30)
	print("TEST2 enemy IN FRONT (where the player walked): health %d -> %d" % [hp, target.health])
	target.global_position = player.global_position * Vector3(1, 0, 1) - to_enemy.normalized() * 1.0
	await _frames(20)
	hp = target.health
	player._start_attack()
	await _frames(30)
	print("TEST2 enemy BEHIND the player: health %d -> %d" % [hp, target.health])

	# --- TEST 3: shared enemy material
	var m0: StandardMaterial3D = enemies[0].get_node("MeshInstance3D").material_override
	var m1: StandardMaterial3D = enemies[1].get_node("MeshInstance3D").material_override
	await _frames(20)
	enemies[0].take_damage(0)
	print("TEST3 enemies share one material instance: %s; Enemy2 albedo right after hitting only Enemy: %s" % [m0 == m1, m1.albedo_color])
	get_tree().quit()
