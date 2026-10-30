extends Node
## Three independent ENet processes exercise the real table RPCs and visible buttons.

class FixedDeck extends Deck:
	var draws: Array[Card] = []
	func reset() -> void:
		cards.assign(draws)
		cards.reverse()

var role: String = ""
var port: int = 24681
var room: Node3D
var ids: Dictionary = {}
var started: bool = false
var failed: bool = false
var expecting_close: bool = false
var deadline: int


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
	if role.is_empty():
		print("Run with python tools/run_table_tests.py --godot <Godot executable>")
		get_tree().quit()
		return
	RoomNetwork.room_ready.connect(_joined)
	RoomNetwork.connection_ended.connect(_closed)
	deadline = Time.get_ticks_msec() + 35000
	if role == "host":
		_check(RoomNetwork.host_room("Host", port) == OK, "Host room starts.")
	else:
		_check(RoomNetwork.join_room(role, "127.0.0.1", port) == OK, "Guest connects.")


func _joined() -> void:
	room = preload("res://scenes/multiplayer/network_lounge.tscn").instantiate()
	add_child(room)


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		_check(false, "Timed out: " + role)
	if role == "host" and not started and RoomNetwork.players.size() == 3:
		started = true
		_begin.call_deferred()


func _begin() -> void:
	for record in RoomNetwork.players.values():
		ids[record.name] = record.id
	for index in range(3):
		var id: int = [1, ids.A, ids.B][index]
		RoomNetwork._force_pose(id, RoomNetwork.SEATS[index] + Vector3(0, -0.57, 1), 0, -0.14, -1)
		RoomNetwork._reserve_seat(id, index)
	_check(TableNetwork.start_session(100, 100, 0).is_empty(), "Host starts the shared test session.")
	_seed([8, 5, 10, 10, 8, 6, 7, 7, 3, 10, 10, 10])
	await _pause()
	_command.rpc_id(ids.B, "ready_cancel")


func _seed(ranks: Array) -> void:
	var fixed := FixedDeck.new()
	for index in range(ranks.size()):
		fixed.draws.append(Card.new((index % 4) as Card.Suit, int(ranks[index]) as Card.Rank))
	TableNetwork.table.deck = fixed


func _hud() -> PanelContainer:
	for child in room._hud.get_children():
		if child.get_script() == preload("res://scripts/multiplayer/network_table_hud.gd"):
			return child
	return null


func _pause(seconds: float = 0.25) -> void:
	await get_tree().create_timer(seconds).timeout


func _check(condition: bool, text: String) -> void:
	if not condition:
		failed = true
		push_error("TABLE RPC TEST [%s]: %s" % [role, text])
		get_tree().quit(1)


func _finish(text: String) -> void:
	if not failed:
		print("PASS: " + text)
	get_tree().quit(1 if failed else 0)


@rpc("authority", "call_remote", "reliable", 0)
func _command(action: String) -> void:
	match action:
		"ready_cancel":
			_hud().ready_button.pressed.emit()
			await _pause()
			_check(TableNetwork.local_record().ready and TableNetwork.local_record().balance == 100, "Ready reserves no money before the deal.")
			_hud().ready_button.pressed.emit()
			await _pause()
			_check(not TableNetwork.local_record().ready and not TableNetwork.pending, "Cancel ready is acknowledged and buttons unlock.")
			_done.rpc_id(1, "cancelled")
		"ready", "ready_last", "ready_next", "ready_next_last":
			_hud().ready_button.pressed.emit()
			await _pause()
			_done.rpc_id(1, action)
		"privacy":
			_check(TableNetwork.table == null and TableNetwork.state.dealer[1] == null and TableNetwork.state.dealer_total == -1, "Guest receives no host engine, dealer hole identity or dealer total.")
			_check(not TableNetwork.local_record().can_act and _hud().actions.hit.disabled, "Waiting player's buttons are disabled.")
			var revision: int = TableNetwork.state.revision
			TableNetwork.request("hit")
			await _pause()
			_check(TableNetwork.state.revision == revision and not TableNetwork.pending, "Host rejects out-of-turn RPC without changing the round or trapping input.")
			_done.rpc_id(1, "privacy")
		"double":
			_check(TableNetwork.local_record().can_double and not _hud().actions.double.disabled, "Guest double becomes available only on its turn.")
			_hud().actions.double.pressed.emit()
			await _pause()
			var revision: int = TableNetwork.state.revision
			# Replay the exact accepted sequence: it cannot draw or reserve a second stake.
			TableNetwork._request.rpc_id(1, "double", 0.0, TableNetwork.state.round, revision - 1, TableNetwork._sequence)
			await _pause()
			_check(TableNetwork.local_record().balance == 80 and TableNetwork.state.revision == revision, "Double replay cannot charge or draw twice.")
			_done.rpc_id(1, "doubled")
		"stand":
			_hud().actions.stand.pressed.emit()
			await _pause()
			_check(TableNetwork.state.phase == "settled" and TableNetwork.local_record().balance == 100, "Guest push returns its own bet.")
			_check(_hud().net_label.text == "$0.00" and not TableNetwork.pending, "Result and unlocked controls reach the guest.")
			_done.rpc_id(1, "settled")
		"leave_turn":
			_check(TableNetwork.local_record().can_act, "Disconnect test occurs during the guest's active turn.")
			RoomNetwork.leave_room()
			await _pause()
			_finish("Guest A readied, doubled through actual UI/RPCs, rejected replay, and disconnected during its next turn.")
		"bust":
			_check(TableNetwork.local_record().can_act and not TableNetwork.local_record().has_result and _hud().net_label.text.is_empty(), "Next deal clears prior net result and disconnect advances the turn.")
			_hud().actions.hit.pressed.emit()
			await _pause()
			_check(TableNetwork.state.phase == "settled" and TableNetwork.local_record().balance == 90 and TableNetwork.local_record().delta == -10, "Guest bust settles its loss after a mid-turn disconnect.")
			_check(_hud().net_label.text.contains("10.00"), "Loss is displayed on the guest HUD.")
			_check(_hud().net_label.get_theme_color("font_color") == Color("ff7a8e"), "Net loss is shown in red.")
			expecting_close = true
			_done.rpc_id(1, "busted")


@rpc("any_peer", "call_remote", "reliable", 0)
func _done(step: String) -> void:
	if role != "host":
		return
	match step:
		"cancelled":
			_hud().ready_button.pressed.emit()
			_command.rpc_id(ids.A, "ready")
		"ready":
			_check(TableNetwork.state.phase == "betting", "The round waits for the last seated player.")
			_command.rpc_id(ids.B, "ready_last")
		"ready_last":
			_check(TableNetwork.state.turn == 1 and TableNetwork.state.dealer[1] == null, "Third ready starts exactly one round with a hidden dealer card.")
			_command.rpc_id(ids.A, "privacy")
		"ready_next":
			_command.rpc_id(ids.B, "ready_next_last")
		"ready_next_last":
			_check(TableNetwork.state.round == 2, "Everyone ready starts the second shared deal.")
			_hud().actions.stand.pressed.emit()
			_command.rpc_id(ids.A, "leave_turn")
			await _pause(0.7)
			_check(TableNetwork.state.turn == ids.B and RoomNetwork.players.size() == 2, "Disconnected current player cannot stall the next player's turn.")
			_command.rpc_id(ids.B, "bust")
		"privacy":
			_hud().actions.split.pressed.emit()
			_hud().actions.double.pressed.emit()
			_check(TableNetwork.local_record().hands[1].active, "Host plays both split hands before passing the turn.")
			_hud().actions.stand.pressed.emit()
			_command.rpc_id(ids.A, "double")
		"doubled":
			_check(TableNetwork.state.turn == ids.B, "Guest action advances the shared turn on host.")
			_command.rpc_id(ids.B, "stand")
		"settled":
			_check(TableNetwork.local_record().balance == 130 and TableNetwork.record_for(ids.A).balance == 120 and TableNetwork.record_for(ids.B).balance == 100, "Every bankroll independently settles against the same dealer.")
			_check(_hud().net_label.get_theme_color("font_color") == Color("69eda4"), "Host net gain is shown in green.")
			_check(TableNetwork.state.dealer_total == 17 and TableNetwork.state.dealer[1] != null, "Dealer card and total reveal at settlement.")
			_seed([10, 10, 10, 10, 7, 7, 6, 7, 10])
			_hud().ready_button.pressed.emit()
			_command.rpc_id(ids.A, "ready_next")
		"busted":
			_check(TableNetwork.local_record().balance == 130 and TableNetwork.record_for(ids.A).balance == 120 and TableNetwork.record_for(ids.B).balance == 90, "Standing/disconnected hands settle without duplicate payouts or refunds.")
			RoomNetwork.leave_room()
			await _pause()
			_finish("Host and two guests played split/double/push and a second round with a mid-turn disconnect and bust; hidden cards, bankrolls and UI stayed synchronized.")


func _closed(message: String) -> void:
	_check(role == "B" and expecting_close and message.contains("host") and TableNetwork.state.is_empty(), "Host closure clears shared table state on the remaining guest.")
	_finish("Guest B cancelled/readied bets, watched turns, pushed, then busted after another guest disconnected; host closure cleared the table.")
