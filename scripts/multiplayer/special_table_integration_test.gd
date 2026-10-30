extends Node
## Four real ENet peers use the visible rule console, choices, card selector and recovery buttons.

class FixedDeck extends Deck:
	var draws: Array[Card] = []
	func reset() -> void:
		cards.assign(draws)
		cards.reverse()

var role: String = "host"
var port: int = 24685
var room: Node3D
var ids: Dictionary = {}
var started: bool = false
var failed: bool = false
var closing: bool = false
var reply: bool = false
var render_qa: bool = false
var screenshot_folder: String = "user://multiplayer-rule-checks"
var deadline: int


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
		elif argument == "--renderqa":
			render_qa = true
		elif argument.begins_with("--screenshots="):
			screenshot_folder = argument.trim_prefix("--screenshots=")
	get_window().size = Vector2i(960, 640)
	RoomNetwork.room_ready.connect(_joined)
	RoomNetwork.connection_ended.connect(_closed)
	deadline = Time.get_ticks_msec() + 35000
	if role == "host":
		_check(RoomNetwork.host_room("Host", port) == OK, "Room starts.")
		if render_qa:
			print("QA HOST READY")
	else:
		_check(RoomNetwork.join_room(role, "127.0.0.1", port) == OK, "Guest joins.")


func _joined() -> void:
	room = preload("res://scenes/multiplayer/network_lounge.tscn").instantiate()
	add_child(room)


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		_check(false, "Timed out.")
	if role == "host" and not started and RoomNetwork.players.size() == 4:
		started = true
		_run.call_deferred()


func _check(condition: bool, text: String) -> void:
	if not condition:
		failed = true
		push_error("SPECIAL RPC [%s]: %s" % [role, text])
		get_tree().quit(1)


func _pause(seconds: float = 0.2) -> void:
	await get_tree().create_timer(seconds).timeout


func _seed(ranks: Array) -> void:
	var fixed := FixedDeck.new()
	for index in range(ranks.size()):
		fixed.draws.append(Card.new((index % 4) as Card.Suit, int(ranks[index]) as Card.Rank))
	TableNetwork.table.deck = fixed


func _settings(mode: int, selected: Array[StringName], count: int) -> void:
	room.open_rules()
	var console: NetworkRuleConsole = room.rule_console
	_check(console.visible and not room.local_avatar.controls_enabled, "Console suspends local movement.")
	console.mode_select.select(console.mode_select.get_item_index(mode))
	console.count_spin.value = count
	for id in console.checks:
		console.checks[id].button_pressed = selected.has(id)
	console.confirmed.emit()
	_check(not console.visible and room.local_avatar.controls_enabled, "Apply closes console and restores controls.")


func _tell(id: int, action: String) -> void:
	reply = false
	if render_qa: print("QA COMMAND ", action, " -> ", id)
	_command.rpc_id(id, action)
	while not reply and not failed:
		await _pause(0.03)
	await _pause(0.05)


func _shot(label: String) -> void:
	if render_qa:
		await get_tree().process_frame
		RenderingServer.force_draw()
		DirAccess.make_dir_recursive_absolute(screenshot_folder)
		get_viewport().get_texture().get_image().save_png(screenshot_folder.path_join(label + ".png"))


## Rendered checks dispatch real pointer input; headless peers exercise the same handlers.
func _press(button: Button) -> void:
	_check(not button.disabled and button.is_visible_in_tree(), "Requested control is available: " + button.text)
	if not render_qa:
		button.pressed.emit()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _pause(0.05)
	var point := button.get_global_rect().get_center()
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


func _key(code: int, echo: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code as Key
		event.keycode = code as Key
		event.pressed = pressed
		event.echo = echo and pressed
		Input.parse_input_event(event)
		await _pause(0.06)


func _check_layout() -> void:
	var hud: PanelContainer = room.table_hud
	var viewport := get_viewport().get_visible_rect()
	_check(viewport.encloses(hud.get_global_rect()), "HUD stays within the current window.")
	var tools: Array[Control] = [hud.balance_label, hud.net_label, hud.dealer_button, hud.lift_button, hud.info_button, hud.seat_button]
	for control in tools:
		if control.is_visible_in_tree() and control.size.x > 1:
			_check(hud.get_global_rect().encloses(control.get_global_rect()), "Top controls fit their panel: " + str(control))
	for a in range(tools.size()):
		for b in range(a + 1, tools.size()):
			if tools[a].is_visible_in_tree() and tools[b].is_visible_in_tree():
				_check(not tools[a].get_global_rect().intersects(tools[b].get_global_rect()), "Money and utility controls never overlap.")
	_check(not room._hint_panel.visible, "No permanent instruction bar while seated.")


func _reroll(index: int, pick_world: bool = false) -> void:
	var hud: PanelContainer = room.table_hud
	var revision: int = TableNetwork.state.revision
	var cards: Array = TableNetwork.local_record().hands[hud.active_reroll_hand()].cards.duplicate()
	await _press(hud.reroll_button)
	await _pause()
	_check(hud.is_selecting_reroll() and hud.replace_selected_button.disabled and hud.reroll_selector.selected == 0, "Reroll starts selection with no default card or replacement.")
	_check(TableNetwork.state.revision == revision and not TableNetwork.local_record().reroll_used, "Selection spends no action or allowance.")
	for key in room.table_view._poses:
		var pose: Dictionary = room.table_view._poses[key]
		var view: TableCard3D = room.table_view._cards[key]
		var own: bool = pose.id == multiplayer.get_unique_id() and pose.hand == hud.active_reroll_hand() and not pose.hidden
		_check(view.selectable == own and view.outline.visible == own, "Only eligible own cards get a gold outline.")
	_check(not hud.choose_reroll_card(99, 0) and not hud.choose_reroll_card(hud.active_reroll_hand(), -1), "Wrong hand and missing card cannot replace.")
	if role == "host":
		await _tell(ids.A, "selection_is_local")
		var camera := room.local_avatar.camera as Camera3D
		var dealer: TableCard3D = room.table_view._cards["dealer:0"]
		_check(room.table_view.pick_card(camera.unproject_position(dealer.global_position)) == null, "Dealer cards cannot be selected for Reroll.")
		await _key(KEY_Q)
		_check(TableNetwork.state.revision == revision, "Gameplay shortcuts cannot act while choosing a card.")
		await _key(KEY_ESCAPE)
		_check(not hud.is_selecting_reroll() and not TableNetwork.local_record().reroll_used, "Escape cancels without spending Reroll.")
		await _key(KEY_R)
		_check(hud.is_selecting_reroll(), "Seated R enters selection without resetting the chair.")
		for size_value in [Vector2i(1920, 1080), Vector2i(960, 640), Vector2i(640, 560)]:
			get_window().size = size_value
			await _pause()
			_check_layout()
			await _shot("reroll-" + str(size_value.x))
	if pick_world:
		# Test the same physical meshes on the felt first, then pick a readable lifted card.
		TableNetwork.request_lift(false)
		await _pause(0.4)
		var view: TableCard3D = room.table_view._cards["%d:%d:%d" % [multiplayer.get_unique_id(), hud.active_reroll_hand(), index]]
		var camera := room.local_avatar.camera as Camera3D
		var point := camera.unproject_position(view.global_transform * Vector3(-0.1, 0.02, -0.25))
		_check(room.table_view.pick_card(point) == view, "Flat own card is ray-selectable.")
		TableNetwork.request_lift(true)
		await _pause(0.4)
		point = camera.unproject_position(view.global_transform * Vector3(-0.1, 0.02, -0.25))
		_check(room.table_view.pick_card(point) == view, "Lifted own card remains ray-selectable.")
		_check(point.y < hud.get_global_rect().position.y and point.y > room.header_panel.get_global_rect().end.y, "Lifted selection stays between HUD panels.")
		await _shot("highlighted-lifted")
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		Input.parse_input_event(motion)
		await _pause(0.05)
		for pressed in [true, false]:
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = pressed
			click.position = point
			click.global_position = point
			Input.parse_input_event(click)
			await _pause(0.08)
	else:
		hud.reroll_selector.select(index + 1)
		hud.reroll_selector.item_selected.emit(index + 1)
		_check(not hud.replace_selected_button.disabled, "Explicit dropdown selection enables confirmation.")
		await _press(hud.replace_selected_button)
	await _pause()
	_check(TableNetwork.local_record().reroll_used and not hud.is_selecting_reroll(), "Only committed choice spends Reroll and clears selection.")
	var after: Array = TableNetwork.local_record().hands[0].cards
	for other in range(cards.size()):
		if other != index:
			_check(after[other] == cards[other], "Reroll leaves every unchosen card unchanged.")


func _lucky_badge(peer: int) -> Label3D:
	for plate in room.table_view._labels.get_children():
		if not plate.is_queued_for_deletion() and plate.has_meta("peer_id") and plate.get_meta("peer_id") == peer:
			return plate.get_node_or_null("LuckyNineBadge") as Label3D
	return null


func _run() -> void:
	for person in RoomNetwork.players.values():
		ids[person.name] = person.id
	for index in range(4):
		var id: int = [1, ids.A, ids.B, ids.C][index]
		RoomNetwork._force_pose(id, RoomNetwork.SEATS[index] + Vector3(0, -0.57, 1), 0, -0.14, -1)
		RoomNetwork._reserve_seat(id, index)
	await _pause()
	_check(TableNetwork.start_session(100, 100, 0).is_empty(), "Host starts the shared test session.")
	var all_rules: Array[StringName] = [&"reroll", &"second_chance", &"lucky_nine", &"double_target", &"mystery_card"]
	_settings(RuleManager.RuleMode.ALL_SELECTED, all_rules, 2)
	await _pause()
	room.open_rules()
	await _pause()
	await _shot("console-normal")
	if render_qa:
		room.rule_console.hide()
		get_window().size = Vector2i(640, 560)
		await _pause()
		room.open_rules()
		await _pause()
		await _shot("console-small")
	room.rule_console.hide()
	for name_key in ["A", "B", "C"]:
		await _tell(ids[name_key], "settings")
	_seed([5, 10, 10, 10, 10, 4, 8, 8, 7, 7, 5, 10, 7, 10, 10, 7, 2, 10])
	# Choose a deterministic RNG seed whose first legitimate round target is 25.
	var probe := RandomNumberGenerator.new()
	for value in range(100):
		probe.seed = value
		if probe.randi_range(22, 30) == 25:
			(TableNetwork.table.rules.get_rule(&"double_target") as DoubleTargetRule)._rng.seed = value
			break
	await _tell(ids.A, "stale_ready")
	var revision_before_typing: int = TableNetwork.state.revision
	var seat_before_typing: int = room.local_avatar.seat_index
	room.table_hud.bet_spin.get_line_edit().grab_focus()
	await _key(KEY_G)
	await _key(KEY_R)
	_check(room.local_avatar.seat_index == seat_before_typing and TableNetwork.state.revision == revision_before_typing, "Text entry never triggers seating or table shortcuts.")
	room.table_hud.bet_spin.get_line_edit().release_focus()
	TableNetwork.request("ready", 10)
	for name_key in ["A", "B", "C"]:
		await _tell(ids[name_key], "ready")
	_check(TableNetwork.state.turn == 1 and TableNetwork.state.target == 25 and TableNetwork.state.active_rules.size() == 5, "Shared all-rule deal and target.")
	room._focus_cards()
	await _pause()
	await _shot("mystery-small")
	_check(not TableNetwork.local_record().hands[0].lucky_nine_qualified and _lucky_badge(1) == null, "Hidden opening never reveals Lucky 9 qualification.")
	await _press(room.table_hud.keep_button)
	await _pause()
	_check(TableNetwork.local_record().hands[0].lucky_nine_qualified and _lucky_badge(1) != null and room.table_hud.rules_label.text.contains("qualified"), "Lucky 9 badge and own rule text appear immediately after opening reveal.")
	await _shot("lucky-nine-opening")
	await _tell(ids.A, "replace")
	await _tell(ids.B, "keep")
	await _tell(ids.C, "keep")
	_check(TableNetwork.state.turn == 1 and TableNetwork.state.dealer[1] == null, "All choices finish before ordinary turns; dealer remains hidden.")
	var revision: int = TableNetwork.state.revision
	_settings(RuleManager.RuleMode.RANDOM_SELECTED, [&"reroll", &"second_chance"], 2)
	_check(TableNetwork.state.active_rules.size() == 5 and TableNetwork.state.revision == revision, "Next-round settings never change active rules or turn revision.")
	await _pause()
	_check_layout()
	await _shot("all-rules-small")
	await _reroll(0, true)
	_check(_lucky_badge(1) != null and TableNetwork.local_record().hands[0].lucky_nine_bonus == 5, "Reroll preserves the opening Lucky 9 marker and original bonus.")
	var after_reroll_revision: int = TableNetwork.state.revision
	await _key(KEY_Z, true)
	_check(TableNetwork.state.revision == after_reroll_revision, "Repeated held-key events cannot submit extra actions.")
	await _key(KEY_Z)
	_check(TableNetwork.state.turn == ids.A, "Host Reroll and Double advance to next player.")
	await _tell(ids.A, "recover")
	await _tell(ids.B, "target")
	await _tell(ids.C, "other_recover")
	_check(TableNetwork.state.phase == "settled", "Four-player all-rule round completes.")
	for pair in [[1, 125], [ids.A, 110], [ids.B, 102.5], [ids.C, 90]]:
		_check(is_equal_approx(TableNetwork.record_for(pair[0]).balance, pair[1]), "Independent rule payouts and bankrolls match.")
	await _pause()
	_check_layout()
	await _shot("settled-small")
	_seed([10, 10, 10, 10, 10, 7, 8, 8, 7, 7])
	TableNetwork.request("ready", 10)
	for name_key in ["A", "B", "C"]:
		await _tell(ids[name_key], "ready")
	_check(TableNetwork.state.active_rules.size() == 2 and TableNetwork.state.active_rules.has(&"reroll") and TableNetwork.state.active_rules.has(&"second_chance") and TableNetwork.state.target == 0, "Next deal selects exactly two eligible rules and resets target.")
	_check(not TableNetwork.local_record().reroll_used and not TableNetwork.local_record().has_result, "New round restores allowances and clears old net.")
	await _press(room.table_hud.actions.stand)
	for name_key in ["A", "B", "C"]:
		await _tell(ids[name_key], "stand")
	_check(TableNetwork.state.phase == "settled", "Random rules round completes.")
	var seat: int = room.local_avatar.seat_index
	await _key(KEY_G)
	_check(room.local_avatar.seat_index == -1, "G leaves the chair.")
	RoomNetwork._force_pose(1, RoomNetwork.SEATS[seat] + Vector3(0, -0.57, 1), 0, -0.14, -1)
	await _pause()
	await _key(KEY_G)
	_check(room.local_avatar.seat_index == seat, "G sits in the nearby chair.")
	for name_key in ["A", "B", "C"]:
		await _tell(ids[name_key], "finish")
	closing = true
	RoomNetwork.leave_room()
	await _pause()
	print("PASS: Four real peers, host/read-only console, stale Ready rejection, Mystery secrecy, independent Reroll/recovery, target choice, Lucky 9 payouts and next-round Random selection.")
	get_tree().quit(1 if failed else 0)


@rpc("authority", "call_remote", "reliable", 0)
func _command(action: String) -> void:
	var hud: PanelContainer = room.table_hud
	match action:
		"selection_is_local":
			_check(_lucky_badge(1) != null and not TableNetwork.local_record().hands[0].lucky_nine_qualified, "Remote qualifying hand is marked without claiming this player's hand qualifies.")
			var revision: int = TableNetwork.state.revision
			for view in room.table_view._cards.values():
				_check(not view.selectable and not view.outline.visible, "Another player's Reroll mode never highlights this client's cards.")
			await _key(KEY_Q)
			await _key(KEY_E)
			await _key(KEY_R)
			_check(TableNetwork.state.revision == revision, "Out-of-turn shortcuts never act or spend a rule.")
		"settings":
			room.open_rules()
			var console: NetworkRuleConsole = room.rule_console
			_check(console.mode_select.disabled and console.checks[&"reroll"].disabled and not room.local_avatar.controls_enabled, "Guest console is read-only and suspends controls.")
			_check(not TableNetwork.configure_rules(0, [], 1, TableNetwork.state.settings_revision).is_empty(), "Guest cannot configure host table.")
			console.confirmed.emit()
			_check(not console.visible and room.local_avatar.controls_enabled, "Guest Close restores controls.")
		"stale_ready":
			TableNetwork._sequence += 1
			TableNetwork.pending = true
			TableNetwork._request.rpc_id(1, "ready", 10.0, TableNetwork.state.round, TableNetwork.state.revision, TableNetwork._sequence, -1, TableNetwork.state.settings_revision - 1, TableNetwork.state.session.id)
			await _pause()
			_check(not TableNetwork.pending and not TableNetwork.local_record().ready, "Stale rules Ready rejected and pending cleared.")
		"ready": await _key(KEY_B)
		"replace", "keep":
			var me := TableNetwork.local_record()
			_check(me.can_keep_mystery and me.hands[0].cards[1] == null and me.hands[0].total == -1 and TableNetwork.state.dealer[1] == null, "Only current player's mystery controls enabled; identities hidden.")
			var hole: TableCard3D = room.table_view._cards["dealer:1"]
			var mystery: TableCard3D = room.table_view._cards["%d:0:1" % multiplayer.get_unique_id()]
			_check(hole.concealed and mystery.concealed and mystery.rank_label.text.is_empty(), "Mystery/dealer meshes contain no face text.")
			TableNetwork.request_lift(true)
			await _pause()
			_check(mystery.concealed and mystery.rank_label.text.is_empty(), "Lifting never reveals mystery card.")
			if action == "replace":
				hud.replace_button.pressed.emit()
			else:
				hud.keep_button.pressed.emit()
		"recover":
			await _key(KEY_Q)
			await _pause()
			_check(not hud.second_chance_button.disabled and hud.actions.hit.disabled and hud.actions.stand.text == "Take Target Win [E]", "Exact target offers recovery or payout, with Hit blocked.")
			await _key(KEY_T)
			await _pause()
			_check(TableNetwork.local_record().second_chance_used and TableNetwork.local_record().hands[0].total == 15, "Own recovery removes bust card.")
			await _reroll(1)
			await _key(KEY_E)
		"target":
			await _key(KEY_Q)
			await _pause()
			_check(TableNetwork.local_record().target_match and not hud.second_chance_button.disabled, "Second player independently gets target/recovery choice.")
			await _key(KEY_E)
		"other_recover":
			await _reroll(1)
			await _key(KEY_Q)
			await _pause()
			_check(hud.actions.stand.text == "Accept Bust [E]" and not hud.second_chance_button.disabled, "Non-target bust offers ordinary accept or recovery.")
			await _key(KEY_T)
			await _pause()
			await _key(KEY_E)
		"stand":
			var seat: int = room.local_avatar.seat_index
			await _key(KEY_E)
			_check(room.local_avatar.seat_index == seat, "E stands the hand without leaving the chair.")
		"finish":
			_check(TableNetwork.state.phase == "settled" and TableNetwork.state.dealer[1] != null, "Settlement reveals dealer to every peer.")
			closing = true
	await _pause()
	_done.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable", 0)
func _done() -> void:
	if role == "host":
		reply = true


func _closed(_message: String) -> void:
	if role != "host":
		_check(closing, "Host closed after all flows completed.")
		print("PASS: Guest %s verified shared special-rule controls, secrecy, personal uses and settlement." % role)
		get_tree().quit(1 if failed else 0)
