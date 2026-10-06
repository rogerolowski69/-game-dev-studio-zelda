extends Node
# Review harness for the wallet flows. Pass "title" or "gate" after "--".

func _ready() -> void:
	var which: String = OS.get_cmdline_user_args()[0]
	if which == "title":
		var title: Control = load("res://scenes/TitleScreen.tscn").instantiate()
		add_child(title)
		await get_tree().process_frame
		title._on_connect_pressed()
		await get_tree().create_timer(9.0).timeout
		print("TEST5 9s after Connect with /ownership failing: status='%s' error_visible=%s retry_visible=%s still_on_title=%s" % [
			title.status_label.text, title.error_label.visible, title.retry_button.visible, is_instance_valid(title)])
	else:
		var main: Node = load("res://scenes/Main.tscn").instantiate()
		add_child(main)
		await get_tree().physics_frame
		# Session state the TitleScreen would have established.
		WalletManager.status = "connected"
		WalletManager.address = "0:abc"
		WalletManager._ownership_fetched_for_session = true
		WalletManager._status_timer.start()
		var gate: Area3D = main.get_node("ZoneGate")
		gate._player_in_range = true
		gate._update_prompt()
		print("TEST6 step0 player at gate: prompt='%s' visible=%s barrier_disabled=%s" % [gate.prompt_label.text.replace("\n", " | "), gate.prompt_label.visible, gate.barrier_collision.disabled])
		var ev := InputEventAction.new()
		ev.action = "interact"
		ev.pressed = true
		gate._unhandled_input(ev)
		await get_tree().create_timer(6.0).timeout
		print("TEST6 step1 6s after paying (wallet signed, indexer not caught up): prompt='%s' visible=%s minting=%s barrier_disabled=%s has_access_pass=%s" % [
			gate.prompt_label.text.replace("\n", " | "), gate.prompt_label.visible, gate._minting, gate.barrier_collision.disabled, WalletManager.has_access_pass])
	get_tree().quit()
