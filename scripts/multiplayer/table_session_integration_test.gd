extends "res://scripts/multiplayer/special_table_integration_test.gd"
## Two finite sessions over four real peers, including reconnect spectating and native dialog input.

var departed_id: int = 0


func _ready() -> void:
	super._ready()
	deadline = Time.get_ticks_msec() + 60000


func _modal_press(button: Button) -> void:
	_check(not button.disabled and button.is_visible_in_tree(), "Dialog control is available: " + button.text)
	if not render_qa:
		button.pressed.emit()
		await _pause()
		return
	var viewport := button.get_viewport()
	var point := button.get_global_rect().get_center()
	if viewport is Window and viewport != get_viewport():
		point += Vector2(viewport.position)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(point)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	Input.parse_input_event(motion)
	await _pause(0.05)
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.position = point
		click.global_position = point
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = pressed
		Input.parse_input_event(click)
		await _pause(0.05)
	await _pause()


func _dialog_shot(label: String) -> void:
	if render_qa:
		await get_tree().process_frame
		RenderingServer.force_draw()
		DirAccess.make_dir_recursive_absolute(screenshot_folder)
		var dialog: Window = room.rule_console if room.rule_console.visible else room.session_dialog
		dialog.get_texture().get_image().save_png(screenshot_folder.path_join(label + ".png"))


func _check_session_ui() -> void:
	var dialog: NetworkSessionDialog = room.session_dialog
	_check(dialog.visible and not room.local_avatar.controls_enabled, "Session dialog suspends local controls.")
	_check(dialog.size.x <= get_window().size.x and dialog.size.y <= get_window().size.y, "Session dialog fits the current window.")
	if dialog.results_view:
		_check(dialog.board.get_child_count() == 25, "Standings render all four entrants and headings.")
		_check(dialog.winner_label.text.contains("Host") and dialog.winner_label.text.contains("A"), "Winner label includes tied leaders.")
		_check(not room.table_hud.betting_row.visible and room.table_hud.ready_button.disabled, "Final results disable more bets.")


func _check_console_ui() -> void:
	var console: NetworkRuleConsole = room.rule_console
	_check(console.visible and not room.local_avatar.controls_enabled, "Unified console suspends local controls.")
	_check(console.size.x <= get_window().size.x and console.size.y <= get_window().size.y, "Unified console fits small windows.")
	for child in room._title.get_parent().get_children():
		if child is Button:
			_check(child.text != "Session", "Header has no separate Session button.")


func _board_shot(label: String) -> void:
	if not render_qa:
		return
	var results_visible: bool = room.session_dialog.visible
	room.session_dialog.hide()
	var camera := room.local_avatar.camera as Camera3D
	var old_pose := camera.global_transform
	var old_fov := camera.fov
	var hud_visible: bool = room._hud.visible
	if hud_visible:
		room.toggle_hud()
	camera.global_position = Vector3(-2.7, 3.0, -1.4)
	camera.look_at(room.leaderboard.global_position, Vector3.UP)
	camera.fov = 70
	await _pause()
	await _shot(label)
	camera.global_transform = old_pose
	camera.fov = old_fov
	if hud_visible:
		room.toggle_hud()
	if results_visible:
		room.open_results()


func _run() -> void:
	for person in RoomNetwork.players.values():
		ids[person.name] = person.id
	for index in range(4):
		var id: int = [1, ids.A, ids.B, ids.C][index]
		RoomNetwork._force_pose(id, RoomNetwork.SEATS[index] + Vector3(0, -0.57, 1), 0, -0.14, -1)
		RoomNetwork._reserve_seat(id, index)
	await _pause()
	_check(TableNetwork.state.session.status == "setup" and room.table_hud.ready_button.disabled, "Room waits for the host's session setup.")
	for name_key in ["A", "B", "C"]:
		await _tell(ids[name_key], "inspect_setup")
	room.open_rules()
	_check_console_ui()
	room.rule_console.rounds_spin.value = 2
	room.rule_console.money_spin.value = 150
	await _dialog_shot("setup-normal")
	if render_qa:
		room.session_dialog.hide()
		get_window().size = Vector2i(640, 560)
		await _pause()
		room.open_rules()
		room.rule_console.rounds_spin.value = 2
		room.rule_console.money_spin.value = 150
		await _pause()
		_check_console_ui()
		await _dialog_shot("setup-small")
	await _shot("setup-room")
	await _modal_press(room.rule_console.get_ok_button())
	_check(TableNetwork.state.session.status == "active" and TableNetwork.state.session.round_limit == 2 and TableNetwork.local_record().balance == 150, "Host's visible Start commits money and length.")
	_seed([10, 10, 10, 10, 10, 10, 10, 8, 7, 8])
	await _ready_everyone()
	_check(room.leaderboard.rows[0].balance == 150 and TableNetwork.local_record().balance == 140, "Wall leaderboard preserves settled balances while stakes are on the table.")
	await _board_shot("leaderboard-starting")
	_check(TableNetwork.state.session.current_round == 1 and room.table_hud.status_label.text.contains("1 of 2"), "Shared Round 1 of 2 appears on the HUD.")
	room.open_rules()
	_check(not room.rule_console.money_spin.editable and not room.rule_console.rounds_spin.editable, "Active session settings are read-only.")
	await _modal_press(room.rule_console.get_ok_button())
	_check(not TableNetwork.start_session(1, 999, 1).is_empty(), "Host cannot reset an active session's money.")
	_settings(RuleManager.RuleMode.ALL_SELECTED, [&"mystery_card"], 1)
	_check(TableNetwork.state.active_rules.is_empty(), "Rule changes stay on the next deal.")
	await _key(KEY_E)
	for name_key in ["A", "B", "C"]:
		await _tell(ids[name_key], "stand")
	_check(TableNetwork.state.session.completed == 1 and TableNetwork.state.session.status == "active", "First shared settlement counts once and session continues.")
	departed_id = ids.C
	await _tell(ids.C, "rejoin")
	for person in RoomNetwork.players.values():
		if person.name == "C":
			ids.C = person.id
	_check(ids.C != departed_id and not TableNetwork.record_for(ids.C).enrolled, "Rejoined player is a new spectator, preserving the original score.")
	RoomNetwork._force_pose(ids.C, RoomNetwork.SEATS[3] + Vector3(0, -0.57, 1), 0, -0.14, -1)
	RoomNetwork._reserve_seat(ids.C, 3)
	await _pause()
	await _tell(ids.C, "late_spectator")
	_seed([10, 10, 10, 10, 10, 10, 8, 8])
	await _ready_everyone(false)
	_check(room.leaderboard.rows[0].balance == 160 and room.leaderboard.rows[0].starting_balance == 150, "Leaderboard updates after settlement and keeps starting balances.")
	_check(TableNetwork.state.session.current_round == 2 and TableNetwork.state.active_rules == [&"mystery_card"], "Second deal uses staged Mystery Card and ignores spectator readiness.")
	await _key(KEY_K)
	await _tell(ids.A, "keep")
	await _tell(ids.B, "keep")
	await _key(KEY_E)
	await _tell(ids.A, "stand")
	_check(TableNetwork.state.session.completed == 1 and not room.session_dialog.visible, "Final standings wait for every active hand.")
	await _tell(ids.B, "stand")
	_check(TableNetwork.state.session.status == "finished" and TableNetwork.state.session.completed == 2, "Final dealer settlement ends the session.")
	var standings: Array = TableNetwork.state.session.standings
	_check(standings.size() == 4 and standings[0].place == 1 and standings[1].place == 1 and standings[2].place == 3 and standings[3].place == 4, "All peers receive shared places 1,1,3,4.")
	_check(standings[0].balance == 170 and standings[1].balance == 170 and standings[2].balance == 150 and standings[3].id == departed_id and standings[3].balance == 140, "Final money includes all payouts and retains departed entrant.")
	await _pause()
	_check_session_ui()
	_check(room.session_dialog.board.get_child(0).get_line_count() == 1, "Place header stays on one line in a small window.")
	for row_index in range(4):
		for column in [2, 3, 4]:
			_check(room.session_dialog.board.get_child(5 + row_index * 5 + column).get_line_count() == 1, "Result amounts stay readable on a single line.")
	_check(room.session_dialog.board.get_child(2).text == "Starting\nBalance" and room.session_dialog.board.get_child(3).text == "Ending\nBalance", "Results include separate starting and ending balance columns.")
	_check(room.leaderboard.columns[3] == "Ending\nBalance" and room.leaderboard.rows[0].balance == 170, "Final wall leaderboard matches session results.")
	await _board_shot("leaderboard-final")
	await _dialog_shot("results-small")
	await _shot("room-results-small")
	for name_key in ["A", "B", "C"]:
		await _tell(ids[name_key], "results")
	await _modal_press(room.session_dialog.get_ok_button())
	_check(not room.session_dialog.visible and room.local_avatar.controls_enabled, "Back to Room restores exploration.")
	room.open_results()
	_check_session_ui()
	if render_qa: print("QA RESULTS VERIFIED; OPENING NEW SESSION")
	await _modal_press(room.session_dialog.new_button)
	_check(room.rule_console.visible and not room.session_dialog.visible and room.rule_console.rounds_spin.value == 2 and room.rule_console.money_spin.value == 150, "New Session opens reviewable settings with prior defaults.")
	room.rule_console.rounds_spin.value = 1
	room.rule_console.money_spin.value = 40
	await _modal_press(room.rule_console.get_ok_button())
	_check(TableNetwork.state.session.id == 2 and TableNetwork.state.session.completed == 0 and TableNetwork.local_record().balance == 40 and TableNetwork.state.dealer.is_empty(), "New session resets bankrolls, hands, results and progress.")
	_check(not TableNetwork.state.lifted.size(), "New session clears old card inspection state.")
	_settings(RuleManager.RuleMode.OFF, [], 1)
	await _tell(ids.C, "stale_session")
	_seed([10, 10, 10, 10, 10, 7, 7, 7, 7, 7])
	if render_qa: print("QA NEW SESSION STARTED; READYING")
	await _ready_everyone()
	if render_qa: print("QA NEW DEAL READY; PLAYING")
	await _key(KEY_E)
	for name_key in ["A", "B", "C"]:
		await _tell(ids[name_key], "stand")
	_check(TableNetwork.state.session.status == "finished" and TableNetwork.state.session.standings.size() == 4, "Second finite session finishes with all current connections.")
	for entry in TableNetwork.state.session.standings:
		_check(entry.place == 1 and entry.balance == 40 and entry.id != departed_id, "All current players tie after four pushes, without departed entry.")
	for name_key in ["A", "B", "C"]:
		await _tell(ids[name_key], "finish")
	closing = true
	RoomNetwork.leave_room()
	await _pause()
	print("PASS: Four real peers completed finite sessions through setup/results UI, locked settings, staged rules, tied winners, reconnect spectating, retained scores, stale-session rejection and fresh bankrolls.")
	get_tree().quit(1 if failed else 0)


func _ready_everyone(include_c: bool = true) -> void:
	await _key(KEY_B)
	for name_key in (["A", "B", "C"] if include_c else ["A", "B"]):
		await _tell(ids[name_key], "ready")


@rpc("authority", "call_remote", "reliable", 0)
func _command(action: String) -> void:
	match action:
		"inspect_setup":
			room.open_rules()
			_check_console_ui()
			_check(not room.rule_console.money_spin.editable and not room.rule_console.rounds_spin.editable, "Guest cannot edit setup.")
			_check(not TableNetwork.start_session(2, 999, 0).is_empty(), "Guest has no session-start mutation path.")
			room.rule_console.confirmed.emit()
		"ready":
			if room.session_dialog.visible:
				room.session_dialog.hide()
			await _key(KEY_B)
		"stand":
			var seat: int = room.local_avatar.seat_index
			await _key(KEY_E)
			_check(room.local_avatar.seat_index == seat, "Stand action keeps the player's seat.")
		"keep": await _key(KEY_K)
		"rejoin":
			RoomNetwork.leave_room()
			room.queue_free()
			await _pause(0.35)
			_check(RoomNetwork.join_room("C", "127.0.0.1", port) == OK, "Departed guest reconnects.")
			while not RoomNetwork.active or TableNetwork.state.is_empty():
				await _pause(0.03)
			await _pause()
		"late_spectator":
			_check(not TableNetwork.local_record().enrolled and TableNetwork.local_record().balance == 0 and not TableNetwork.local_record().can_bet, "Rejoined spectator receives no new competitive bankroll.")
			TableNetwork.request("ready", 10)
			await _pause()
			_check(not TableNetwork.pending and not TableNetwork.local_record().ready, "Host rejects spectator bets and acknowledges the request.")
		"results":
			_check_session_ui()
			_check(not room.session_dialog.new_button.visible and TableNetwork.state.session.standings.size() == 4, "Guest results include original entrants without a New Session control.")
			var revision: int = TableNetwork.state.revision
			TableNetwork.request("ready", 10)
			await _pause()
			_check(TableNetwork.state.revision == revision and not TableNetwork.pending, "Finished session rejects further bets.")
			room.session_dialog.confirmed.emit()
		"stale_session":
			_check(TableNetwork.local_record().enrolled and TableNetwork.local_record().balance == 40, "Next session enrolls the rejoined connection with equal starting money.")
			TableNetwork._sequence += 1
			TableNetwork.pending = true
			TableNetwork._request.rpc_id(1, "ready", 10.0, TableNetwork.state.round, TableNetwork.state.revision, TableNetwork._sequence, -1, TableNetwork.state.settings_revision, 1)
			await _pause()
			_check(not TableNetwork.pending and not TableNetwork.local_record().ready and TableNetwork.local_record().balance == 40, "Old session epoch cannot ready or charge the new bankroll.")
		"finish": closing = true
	await _pause()
	_done.rpc_id(1)


func _closed(_message: String) -> void:
	if role != "host":
		_check(closing, "Room closes after both sessions finish.")
		print("PASS: Session guest %s verified setup authority, progress, results and next-session reset." % role)
		get_tree().quit(1 if failed else 0)
