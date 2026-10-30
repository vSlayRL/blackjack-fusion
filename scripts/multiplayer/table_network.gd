extends Node
## Automatic host authority for bets/actions. Requests never supply a player ID.

signal changed
signal notice_received(message: String)

var table: ClassicTable
var state: Dictionary = {}
var pending: bool = false
var pending_action: String = ""
var _sequence: int = 0
var _accepted: Dictionary = {}
var _lifted: Dictionary = {}
var _view_round: int = -1


func _ready() -> void:
	RoomNetwork.roster_changed.connect(_sync_members)
	RoomNetwork.room_closed.connect(_clear)


func _clear() -> void:
	table = null
	state = {}
	pending = false
	pending_action = ""
	_sequence = 0
	_accepted.clear()
	_lifted.clear()
	_view_round = -1
	changed.emit()


func _sync_members() -> void:
	if not RoomNetwork.active or not multiplayer.is_server():
		return
	if table == null:
		table = ClassicTable.new()
	table.sync_members(RoomNetwork.players)
	for id in _accepted.keys():
		if not RoomNetwork.players.has(id):
			_accepted.erase(id)
	_publish()


## Settings are staged for the next deal; only this room's host can submit them.
func configure_rules(mode: int, selected: Array[StringName], count: int, expected_settings: int) -> String:
	if table == null or not RoomNetwork.active or not multiplayer.is_server():
		return "Only the host can change table rules."
	var error := table.configure(1, mode, selected, count, expected_settings)
	if error.is_empty():
		_publish()
	return error


## Only the local host has this mutation path. Guests receive the resulting snapshot.
func start_session(rounds: int, money: float, expected_session: int) -> String:
	if table == null or not RoomNetwork.active or not multiplayer.is_server():
		return "Only the host can start a session."
	var error := table.start_session(1, rounds, money, expected_session)
	if error.is_empty():
		_lifted.clear()
		_publish()
	return error


func start_configured_session(rounds: int, money: float, mode: int, selected: Array[StringName], count: int, expected_session: int, expected_settings: int) -> String:
	if table == null or not RoomNetwork.active or not multiplayer.is_server():
		return "Only the host can start a session."
	var error := table.start_configured_session(1, rounds, money, mode, selected, count, expected_session, expected_settings)
	if error.is_empty():
		_lifted.clear()
		_publish()
	return error


func local_record() -> Dictionary:
	return record_for(multiplayer.get_unique_id())


func record_for(id: int) -> Dictionary:
	for record in state.get("players", []):
		if record.id == id:
			return record
	return {}


func request(action: String, amount: float = 0.0, card_index: int = -1) -> void:
	if not RoomNetwork.active or state.is_empty() or pending:
		return
	pending = true
	pending_action = action
	_sequence += 1
	if multiplayer.is_server():
		_handle(1, action, amount, state.round, state.revision, _sequence, card_index, state.settings_revision, state.session.id)
	else:
		_request.rpc_id(1, action, amount, state.round, state.revision, _sequence, card_index, state.settings_revision, state.session.id)
	changed.emit()


@rpc("any_peer", "call_remote", "reliable", 0)
func _request(action: String, amount: float, expected_round: int, expected_revision: int, sequence: int, card_index: int = -1, expected_settings: int = -1, expected_session: int = -1) -> void:
	if RoomNetwork.active and multiplayer.is_server():
		_handle(multiplayer.get_remote_sender_id(), action, amount, expected_round, expected_revision, sequence, card_index, expected_settings, expected_session)


func _handle(id: int, action: String, amount: float, expected_round: int, expected_revision: int, sequence: int, card_index: int = -1, expected_settings: int = -1, expected_session: int = -1) -> void:
	if table == null or not RoomNetwork.players.has(id) or sequence <= int(_accepted.get(id, 0)):
		return
	_accepted[id] = sequence
	var error := ""
	if expected_session != table.session.id:
		error = "The session changed. Wait for the current setup before acting."
	elif action in ["ready", "cancel"]:
		if action == "ready" and expected_settings != table.settings_revision:
			error = "Table rules changed. Review them before readying again."
		else:
			error = table.ready_bet(id, amount, action == "ready", expected_round, expected_settings)
	else:
		error = table.act(id, action, expected_revision, card_index)
		if error.is_empty() and _lifted.has(id) and table.turn_id == id:
			_lifted[id] = table.members[id].game.player.active_hand_index
	_publish()
	if id == 1:
		_ack(sequence, error)
	else:
		_ack.rpc_id(id, sequence, error)


func _publish() -> void:
	state = table.snapshot()
	if _view_round != state.round:
		_lifted.clear()
		_view_round = state.round
	for id in _lifted.keys():
		var record := record_for(id)
		if record.is_empty() or not record.connected or record.seat < 0 or int(_lifted[id]) >= record.hands.size():
			_lifted.erase(id)
	state.lifted = _lifted.duplicate()
	for id in RoomNetwork.players:
		if id != 1:
			_receive_state.rpc_id(id, state)
	changed.emit()


func viewed_hand(id: int) -> int:
	return int(state.get("lifted", {}).get(id, -1))


## Inspection changes presentation only; it never consumes an action or changes turn revision.
func request_lift(enabled: bool, hand_index: int = -1) -> void:
	var record := local_record()
	if not RoomNetwork.active or record.is_empty() or record.seat < 0 or record.hands.is_empty():
		return
	if hand_index < 0:
		hand_index = 0
		for index in range(record.hands.size()):
			if record.hands[index].active:
				hand_index = index
	if multiplayer.is_server():
		_set_lift(1, enabled, hand_index, state.round)
	else:
		_lift_request.rpc_id(1, enabled, hand_index, state.round)


func toggle_lift() -> void:
	request_lift(viewed_hand(multiplayer.get_unique_id()) < 0)


@rpc("any_peer", "call_remote", "reliable", 0)
func _lift_request(enabled: bool, hand_index: int, expected_round: int) -> void:
	if RoomNetwork.active and multiplayer.is_server():
		_set_lift(multiplayer.get_remote_sender_id(), enabled, hand_index, expected_round)


func _set_lift(id: int, enabled: bool, hand_index: int, expected_round: int) -> void:
	if table == null or not RoomNetwork.players.has(id) or expected_round != table.round_id:
		return
	var record := record_for(id)
	if record.is_empty() or record.seat < 0 or hand_index < 0 or hand_index >= record.hands.size():
		return
	if enabled:
		_lifted[id] = hand_index
	else:
		_lifted.erase(id)
	_publish()


@rpc("authority", "call_remote", "reliable", 0)
func _receive_state(snapshot: Dictionary) -> void:
	state = snapshot
	changed.emit()


@rpc("authority", "call_remote", "reliable", 0)
func _ack(sequence: int, message: String) -> void:
	if sequence == _sequence:
		pending = false
		pending_action = ""
	if not message.is_empty():
		notice_received.emit(message)
	changed.emit()
