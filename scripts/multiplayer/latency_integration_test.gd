extends "res://scripts/multiplayer/toy_integration_test.gd"
## Two actual peers through a delayed relay: previews must precede authoritative replies.


func _ready() -> void:
	var control := 8890
	var registrar := 8809
	var code := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--control="):
			control = int(argument.trim_prefix("--control="))
		elif argument.begins_with("--registrar="):
			registrar = int(argument.trim_prefix("--registrar="))
		elif argument.begins_with("--code="):
			code = argument.trim_prefix("--code=")
		elif argument.begins_with("--screenshots="):
			screenshots = argument.trim_prefix("--screenshots=")
	deadline = Time.get_ticks_msec() + 60000
	RoomNetwork.room_ready.connect(func():
		room = preload("res://scenes/multiplayer/network_lounge.tscn").instantiate()
		add_child(room)
		if role == "host":
			print("ONLINE ROOM CODE " + RoomNetwork.room_code))
	if role == "host":
		_check(RoomNetwork.host_online("Latency Host", "127.0.0.1", control, registrar) == OK, "online host starts")
	else:
		_check(RoomNetwork.join_online("Latency Guest", code, "127.0.0.1", control, registrar) == OK, "online guest starts")


func _run() -> void:
	await _pause(2.5)
	_check(RoomNetwork.ping_ms(guest) >= 200, "host measures delayed relay RTT")
	_check("Guests:" in room._latency.text, "host sees guest latency")
	RoomNetwork._force_pose(1, Vector3(-4, 0.03, 4), 0, 0, -1)
	RoomNetwork._force_pose(guest, Vector3(4.8, 0.03, 4.6), 0, -0.15, -1)
	_place(2, Vector3(4.8, 1.5, 3.2))
	await _step(guest, "predicted_grab")
	_check(ToyNetwork.owners[2] == guest, "preview becomes exclusive host ownership")
	await _step(guest, "local_carry")
	await _step(guest, "predicted_drop")
	_check(ToyNetwork.owners[2] == 0, "drop settles free on host")
	_place(2, Vector3(4.8, 1.5, 3.2))
	await _step(guest, "predicted_push")
	_check(ToyNetwork.bodies[2].interaction_count == 1 and ToyNetwork.bodies[2].warm_light, "push/glow confirmed exactly once")
	_place(2, Vector3(4.8, 1.5, 3.2))
	await _step(guest, "predicted_grab")
	await _step(guest, "predicted_throw")
	_check(ToyNetwork.owners[2] == 0, "throw releases host ownership")
	_place(2, Vector3(4.8, 1.5, 3.2))
	await _step(guest, "rejected_grab")
	_check(ToyNetwork.owners[2] == 0, "invalid revision cannot obtain host ownership")
	# An old client can see a free toy just before someone else acquires it.
	await _pause(0.4)
	replies.erase("competing_grab")
	_command.rpc_id(guest, "competing_grab")
	ToyNetwork.owners[2] = 1
	ToyNetwork.revisions[2] += 1
	ToyNetwork._epochs[1] = RoomNetwork.players[1].epoch
	ToyNetwork._ignore_holder(2, 1)
	ToyNetwork.bodies[2].grab(ToyNetwork._hold_target(1))
	ToyNetwork._publish(true)
	while not replies.has("competing_grab"):
		await get_tree().process_frame
	_check(ToyNetwork.owners[2] == 1, "competing grab cannot steal ownership")
	ToyNetwork._release(2)
	_place(2, Vector3(4.8, 1.5, 3.2))
	await _step(guest, "predicted_grab")
	RoomNetwork._reset_player(guest)
	await _step(guest, "reset_clears")
	await _step(guest, "timeout_recovery")
	_check(TableNetwork.start_session(1, 100.0, TableNetwork.state.session.id).is_empty(), "host starts delayed-feedback game")
	RoomNetwork._force_pose(guest, RoomNetwork.SEATS[3], RoomNetwork.SEAT_YAWS[3], -0.55, 3)
	await _step(guest, "ready_feedback")
	_check(TableNetwork.state.round == 1, "host deals requested round")
	await _step(guest, "finish_latency")
	await _pause(0.4)
	_check(ToyNetwork.owners[2] == 0, "departure/reset leaves no phantom owner")
	print("PASS: delayed relay RTT, immediate previews, exclusive ownership, rejection, timeout and reset cleanup")
	RoomNetwork.leave_room()
	_check(RoomNetwork.ping_ms(guest) == -1 and ToyNetwork._prediction.is_empty(), "room exit clears latency and prediction")
	get_tree().quit()


func _settled() -> void:
	var until := Time.get_ticks_msec() + 2500
	while ToyNetwork._pending_until != 0 and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	_check(ToyNetwork._pending_until == 0 and ToyNetwork._prediction.is_empty(), "host acknowledgement settles preview")


func _start_preview(action: String) -> Vector3:
	var before: Vector3 = ToyNetwork.bodies[2].global_position
	var current_owner: int = ToyNetwork.owners[2]
	ToyNetwork.request(action, 2)
	_check(not ToyNetwork._prediction.is_empty(), "input immediately starts local " + action)
	_check(ToyNetwork.owners[2] == current_owner, "preview never writes authoritative ownership")
	return before


@rpc("authority", "call_remote", "reliable", 0)
func _command(command: String) -> void:
	match command:
		"predicted_grab":
			await _aim(2)
			var before := _start_preview("grab")
			await _pause(0.06)
			_check(not ToyNetwork._prediction.is_empty() and ToyNetwork.owners[2] == 0, "grab moves before host round trip")
			_check(ToyNetwork.bodies[2].global_position.distance_to(before) > 0.08, "grab preview visibly approaches hand")
			await _settled()
			_check(ToyNetwork.owners[2] == multiplayer.get_unique_id(), "grab ultimately confirmed")
		"local_carry":
			await _pause(0.3)
			room.local_avatar.rotation.y += 0.35
			await _pause(0.1)
			var target: Vector3 = ToyNetwork._local_hold_target()
			_check(ToyNetwork.bodies[2].global_position.distance_to(target) < 0.13, "held toy follows current camera before round trip")
			_check(ToyNetwork.bodies[2].freeze, "guest never runs competing rigid-body physics")
			await _shot("latency-local-carry.png")
			room.local_avatar.rotation.y = 0
			await _pause(0.4)
		"predicted_drop", "predicted_throw":
			var action := "drop" if command == "predicted_drop" else "throw"
			var before := _start_preview(action)
			_check(ToyNetwork.held_by(multiplayer.get_unique_id()) == -1, "release hint updates immediately")
			await _pause(0.06)
			_check(ToyNetwork.owners[2] == multiplayer.get_unique_id() and not ToyNetwork.bodies[2].held, "release visual precedes host reply")
			if action == "throw":
				_check(ToyNetwork.bodies[2].global_position.distance_to(before) > 0.15, "throw starts visibly before confirmation")
			await _settled()
			_check(ToyNetwork.owners[2] == 0, "release confirmed")
		"predicted_push":
			await _aim(2)
			var before := _start_preview("push")
			await _pause(0.06)
			_check(ToyNetwork.bodies[2].warm_light and ToyNetwork.bodies[2].global_position.distance_to(before) > 0.07, "push/glow shown before relay reply")
			await _settled()
			_check(ToyNetwork.bodies[2].interaction_count == 1, "confirmed push not applied twice")
		"rejected_grab":
			ToyNetwork.revisions[2] += 100
			_start_preview("grab")
			await _settled()
			await _pause(0.2)
			_check(ToyNetwork.owners[2] == 0 and not ToyNetwork.bodies[2].held, "rejected preview returns to host state")
		"competing_grab":
			_start_preview("grab")
			await _settled()
			_check(ToyNetwork.owners[2] == 1 and ToyNetwork.held_by(multiplayer.get_unique_id()) == -1, "another owner overrides local preview")
		"reset_clears":
			_check(ToyNetwork._prediction.is_empty() and ToyNetwork.held_by(multiplayer.get_unique_id()) == -1, "reset clears local hold and preview")
		"timeout_recovery":
			# Simulate loss of a pending reply without sending an extra network mutation.
			ToyNetwork._preview("push", 2)
			ToyNetwork._pending_until = Time.get_ticks_msec() - 1
			await get_tree().physics_frame
			await get_tree().process_frame
			_check(ToyNetwork._prediction.is_empty() and ToyNetwork._pending_until == 0, "lost reply cannot leave preview locked")
		"finish_latency":
			_check(RoomNetwork.ping_ms() >= 200 and "Ping:" in room._latency.text, "guest measures and displays relay RTT")
			room.session_dialog.hide()
			for size in [Vector2i(640, 560), Vector2i(1920, 1080)]:
				get_window().size = size
				await _pause(0.1)
				_check(room._latency.get_global_rect().end.x <= float(size.x) - 12.0, "ping remains inside resized window")
				await _shot("latency-hud-%d.png" % size.x)
			_done.rpc_id(1, command)
			await _pause(0.3)
			RoomNetwork.leave_room()
			_check(ToyNetwork._prediction.is_empty() and RoomNetwork.ping_ms() == -1, "guest exit clears transient state")
			print("PASS: guest interaction previews under 240ms relay delay, ping and responsive HUD")
			get_tree().quit()
			return
		"ready_feedback":
			var round_before: int = TableNetwork.state.round
			TableNetwork.request("ready", 10.0)
			_check(TableNetwork.pending and "Waiting for host" in room.table_hud.status_label.text, "card action immediately shows pending feedback")
			await _pause(0.06)
			_check(TableNetwork.state.round == round_before, "client never invents a deal before confirmation")
			var until := Time.get_ticks_msec() + 2500
			while TableNetwork.pending and Time.get_ticks_msec() < until:
				await get_tree().process_frame
			_check(not TableNetwork.pending and TableNetwork.pending_action.is_empty() and TableNetwork.state.round == round_before + 1, "card feedback clears on confirmed deal")
	_done.rpc_id(1, command)
