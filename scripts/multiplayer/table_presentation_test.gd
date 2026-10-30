extends Node
## Four real peers: fourth chair, shared payouts and lifting without gameplay side effects.

class FixedDeck extends Deck:
	var draws: Array[Card] = []
	func reset() -> void:
		cards.assign(draws)
		cards.reverse()

var role: String = ""
var port: int = 24682
var room: Node3D
var ids: Dictionary = {}
var started: bool = false
var failed: bool = false
var deadline: int = 0
var counts: Dictionary = {}
var next_round: bool = false
var closing: bool = false


func _ready() -> void:
	get_window().size = Vector2i(960, 640)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
	if role.is_empty():
		print("Use tools/run_table_tests.py for the four-peer presentation checks.")
		get_tree().quit()
		return
	RoomNetwork.room_ready.connect(func():
		room = preload("res://scenes/multiplayer/network_lounge.tscn").instantiate()
		add_child(room))
	RoomNetwork.connection_ended.connect(func(message: String):
		_check(role != "host" and closing and message.contains("host"), "Expected host shutdown.")
		_finish("Four-player guest %s verified lifted cards, turn flow and room cleanup." % role))
	deadline = Time.get_ticks_msec() + 30000
	if role == "host":
		_check(RoomNetwork.host_room("Host", port) == OK, "Four-player room starts.")
	else:
		_check(RoomNetwork.join_room(role, "127.0.0.1", port) == OK, "Guest joins.")


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		_check(false, "Four-peer test timed out.")
	if role == "host" and not started and RoomNetwork.players.size() == 4:
		started = true
		_begin.call_deferred()


func _begin() -> void:
	# Walk into the newly widened rim using the real collision controller.
	# A visually stretched table with the old collision would let us walk inside it.
	room.set_physics_process(false)
	room.local_avatar.set_physics_process(false)
	room.local_avatar.position = Vector3(4.5, 0.03, -0.6)
	for _frame in range(45):
		await get_tree().physics_frame
		room.local_avatar.velocity = Vector3(-5.2, -0.2, 0)
		room.local_avatar.move_and_slide()
	_check(room.local_avatar.position.x > 3.55 and room.local_avatar.position.x < 3.9, "The widened physical rim blocks walking at its visible outer edge.")
	room.local_avatar.velocity = Vector3.ZERO
	room.local_avatar.set_physics_process(true)
	room.set_physics_process(true)
	for record in RoomNetwork.players.values():
		ids[record.name] = record.id
	for index in range(4):
		var id: int = [1, ids.A, ids.B, ids.C][index]
		RoomNetwork._force_pose(id, RoomNetwork.SEATS[index] + Vector3(0, -0.57, 1), 0, -0.14, -1)
		RoomNetwork._reserve_seat(id, index)
	_check(RoomNetwork.seat_owner(3) == ids.C and room.avatars.size() == 4, "Fourth real peer occupies the fourth playable chair.")
	_check(TableNetwork.start_session(100, 100, 0).is_empty(), "Host starts the shared test session.")
	var fixed := FixedDeck.new()
	var ranks := [8, 5, 10, 9, 10, 8, 6, 7, 9, 7, 3, 10, 10, 10]
	for index in range(ranks.size()):
		fixed.draws.append(Card.new((index % 4) as Card.Suit, ranks[index] as Card.Rank))
	TableNetwork.table.deck = fixed
	TableNetwork.request("ready", 10)
	await _pause()
	_all("ready")


func _all(command: String) -> void:
	for id in [ids.A, ids.B, ids.C]:
		_command.rpc_id(id, command)


func _pause() -> void:
	await get_tree().create_timer(0.3).timeout


func _check(condition: bool, text: String) -> void:
	if not condition:
		failed = true
		push_error("FOUR-PEER TEST [%s]: %s" % [role, text])
		get_tree().quit(1)


func _finish(text: String) -> void:
	if not failed:
		print("PASS: " + text)
	get_tree().quit(1 if failed else 0)


@rpc("authority", "call_remote", "reliable", 0)
func _command(action: String) -> void:
	var me := multiplayer.get_unique_id()
	match action:
		"ready":
			if RoomNetwork.players[me].seat >= 0:
				TableNetwork.request("ready", 10)
			await _pause()
		"lift_seen":
			_check(TableNetwork.viewed_hand(1) == 0, "Host's lift reaches every guest.")
			_check(TableNetwork.state.dealer[1] == null and TableNetwork.state.dealer_total == -1, "Inspection never reveals the dealer hole card.")
			await _pause()
			var hole: TableCard3D = room.table_view._cards["dealer:1"]
			var face: TableCard3D = room.table_view._cards["dealer:0"]
			_check(hole.concealed and not hole.face.visible and hole.rank_label.text.is_empty() and hole.suit_label.text.is_empty(), "Floating hole card keeps its face and labels concealed.")
			_check(not room.table_view.dealer_raised and absf(face.position.y - 1.16) < 0.01 and face.basis.y.normalized().dot(Vector3.UP) > 0.99, "Host raising the dealer cards does not raise them for any guest.")
			var camera_pose: Transform3D = room.local_avatar.camera.global_transform
			var camera_fov: float = room.local_avatar.camera.fov
			room.table_hud.dealer_button.pressed.emit()
			await _pause()
			var toward_viewer: Vector3 = (room.local_avatar.camera.global_position - face.global_position).normalized()
			_check(room.table_view.dealer_raised and face.global_basis.y.normalized().dot(toward_viewer) > 0.97 and absf(face.scale.x - 0.64) < 0.002, "D raises smaller dealer cards toward this guest.")
			_check(room.local_avatar.camera.global_transform.is_equal_approx(camera_pose) and is_equal_approx(room.local_avatar.camera.fov, camera_fov), "Dealer toggle never moves or zooms the camera.")
			room.table_hud.dealer_button.pressed.emit()
			await _pause()
			_check(not room.table_view.dealer_raised and absf(face.position.y - 1.16) < 0.01, "D again lowers the dealer cards onto the felt.")
		"play_a", "play_b", "play_c":
			var revision: int = TableNetwork.state.revision
			var money: float = TableNetwork.local_record().balance
			TableNetwork.request_lift(true)
			await _pause()
			_check(TableNetwork.viewed_hand(me) == 0 and TableNetwork.state.revision == revision and TableNetwork.local_record().balance == money, "Lifting changes neither money nor turn revision.")
			TableNetwork._lift_request.rpc_id(1, true, 99, TableNetwork.state.round)
			TableNetwork._lift_request.rpc_id(1, false, 0, TableNetwork.state.round - 1)
			await _pause()
			_check(TableNetwork.viewed_hand(me) == 0, "Invalid hand and stale-round lift requests are ignored.")
			var key := "%d:0:0" % me
			_check(room.table_view._cards[key].global_position.distance_to(room.local_avatar.camera.global_position) < 1.6, "Original 3D card mesh moves near its owner for reading.")
			var original_fov: float = room.local_avatar.camera.fov
			room.table_hud.dealer_button.pressed.emit()
			await _pause()
			_check(room._dealer_raised and TableNetwork.viewed_hand(me) == 0 and TableNetwork.state.revision == revision and TableNetwork.local_record().balance == money, "Dealer raising stays local and does not lower the shared player hand.")
			room.table_hud.focus_requested.emit()
			_check(not room._dealer_raised and is_equal_approx(room.local_avatar.camera.fov, original_fov), "Table focus restores the normal camera.")
			TableNetwork.request_lift(true)
			await _pause()
			room.table_hud.actions["double" if action == "play_a" else "stand"].pressed.emit()
			await _pause()
			if action == "play_a":
				_check(TableNetwork.local_record().hands[0].cards.size() == 3 and TableNetwork.viewed_hand(me) == 0, "Double adds a readable third card to the held fan.")
		"stand_up":
			var hole: TableCard3D = room.table_view._cards["dealer:1"]
			_check(not hole.concealed and hole.face.visible and not hole.rank_label.text.is_empty(), "Floating dealer hole card reveals normally at settlement.")
			RoomNetwork.request_seat(-1)
			await _pause()
			_check(TableNetwork.viewed_hand(me) == -1, "Standing lowers the hand and clears its shared inspection state.")
		"lowered":
			_check(TableNetwork.state.lifted.is_empty() and TableNetwork.state.round == 2, "A new deal lowers every old hand.")
			closing = true
	_done.rpc_id(1, action)


@rpc("any_peer", "call_remote", "reliable", 0)
func _done(step: String) -> void:
	if role != "host":
		return
	counts[step] = int(counts.get(step, 0)) + 1
	match step:
		"ready":
			if counts[step] != (6 if next_round else 3):
				return
			if next_round:
				_all("lowered")
			else:
				_check(TableNetwork.state.turn == 1 and TableNetwork.state.players.size() == 4, "All four ready players join one shared round.")
				var revision: int = TableNetwork.state.revision
				room._cycle_info()
				_check(room.table_view.info_mode == 1 and room.table_hud.info_button.text.contains("Hidden"), "Table info button hides circled displays.")
				room._cycle_info()
				room._cycle_info()
				room.toggle_hud()
				_check(not room._hud.visible and room._restore_hud.visible, "HUD can be hidden with an accessible restore button.")
				room._restore_hud.pressed.emit()
				_check(room._hud.visible and TableNetwork.state.revision == revision, "HUD restoration does not change the game.")
				room.table_hud.lift_button.pressed.emit()
				room.table_hud.dealer_button.pressed.emit()
				_check(room.table_view.dealer_raised, "Host may raise dealer cards locally.")
				_all("lift_seen")
		"lift_seen":
			if counts[step] != 3:
				return
			room.table_hud.actions.split.pressed.emit()
			room.table_hud.actions.double.pressed.emit()
			_check(TableNetwork.viewed_hand(1) == 1, "Held split cards follow the next active hand.")
			room.table_hud.hand_selector.item_selected.emit(0)
			_check(TableNetwork.viewed_hand(1) == 0, "Split hand selector can inspect another own hand.")
			room.table_hud.actions.stand.pressed.emit()
			_command.rpc_id(ids.A, "play_a")
		"play_a": _command.rpc_id(ids.B, "play_b")
		"play_b": _command.rpc_id(ids.C, "play_c")
		"play_c":
			_check(TableNetwork.state.phase == "settled", "Fourth seat completes the shared round.")
			for pair in [[1, 130], [ids.A, 120], [ids.B, 100], [ids.C, 110]]:
				_check(TableNetwork.record_for(pair[0]).balance == pair[1], "Four individual bankrolls settle correctly.")
			_command.rpc_id(ids.C, "stand_up")
		"stand_up":
			_check(RoomNetwork.seat_owner(3) == 0 and TableNetwork.viewed_hand(ids.C) == -1, "Fourth chair is released and its cards return to the table.")
			next_round = true
			TableNetwork.request("ready", 10)
			_all("ready")
		"lowered":
			if counts[step] == 3:
				RoomNetwork.leave_room()
				await _pause()
				_finish("Four real peers: fourth chair, shared deck/payouts, HUD/table-info controls, synchronized 3D lifting, split-hand inspection, invalid lift requests, standing and next-deal cleanup.")
