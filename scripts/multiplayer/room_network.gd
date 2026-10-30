extends Node
## ENet room service. RPCs live at one stable autoload path on every computer.
## Clients control their own movement; the host owns membership and exclusive seats.

signal room_ready
signal roster_changed
signal poses_changed
signal notice_received(message: String)
signal connection_ended(message: String)
signal room_closed

const DEFAULT_PORT: int = 24567
const MAX_PLAYERS: int = 4
const PROTOCOL: int = 9
# Match the lounge's wall centers (x = ±7, z = ±6.5). The capsule stops
# inside these walls; a smaller network envelope rejects valid collision poses
# and repeatedly teleports the player, also resetting their camera direction.
const ROOM_HALF_WIDTH: float = 7.0
const ROOM_HALF_DEPTH: float = 6.5
const SEATS: Array[Vector3] = [Vector3(-2.7, 0.6, 1.4), Vector3(-0.95, 0.6, 2.25), Vector3(0.95, 0.6, 2.25), Vector3(2.7, 0.6, 1.4)]
const SEAT_YAWS: Array[float] = [-0.933, -0.322, 0.322, 0.933]
const COLORS: Array[Color] = [Color("53dfea"), Color("ffbf59"), Color("b9a0ff"), Color("8de996")]

var players: Dictionary = {}
var active: bool = false
var connecting: bool = false
var port: int = DEFAULT_PORT
var last_message: String = ""
var online_room: bool = false
var room_code: String = ""
var _online: OnlineConnection
var _peer: ENetMultiplayerPeer
var _requested_name: String = "Player"
var _connect_deadline: int = 0
var _snapshot_elapsed: float = 0.0
var _send_sequence: int = 0
var _pose_times: Dictionary = {}
var _sequences: Dictionary = {}
var _last_server_seen: int = 0


func _ready() -> void:
	_online = OnlineConnection.new()
	_online.name = "OnlineConnection"
	add_child(_online)
	_online.progress.connect(func(message: String): last_message = message)
	_online.failed.connect(_end_connection)
	_online.host_ready.connect(_online_host_ready)
	_online.guest_ready.connect(_online_guest_ready)
	multiplayer.connected_to_server.connect(_connected)
	multiplayer.connection_failed.connect(func(): _end_connection("Could not join the online room. It may be full or closed; check the room code and try again." if online_room else "Could not connect. Check the host address, port, and that the room is open."))
	multiplayer.server_disconnected.connect(func(): _end_connection("The host closed the room. You can host or join another room."))
	multiplayer.peer_disconnected.connect(_peer_left)


## Bind a real UDP server; the hosting player is peer 1 and occupies one of four slots.
func host_room(player_name: String, room_port: int = DEFAULT_PORT) -> Error:
	if room_port < 1024 or room_port > 65535:
		last_message = "Choose a port from 1024 to 65535."
		return ERR_INVALID_PARAMETER
	leave_room()
	_peer = ENetMultiplayerPeer.new()
	var result := _peer.create_server(room_port, MAX_PLAYERS - 1)
	if result != OK:
		last_message = "Could not host on port %d: %s. Try a different port if another room is open." % [room_port, error_string(result)]
		_peer = null
		return result
	port = room_port
	multiplayer.multiplayer_peer = _peer
	active = true
	players[1] = _new_player(1, _clean_name(player_name), 0)
	_pose_times[1] = Time.get_ticks_msec()
	last_message = "Room hosted."
	roster_changed.emit()
	room_ready.emit()
	return OK


## Both online roles register outbound connections; the service relays all ENet traffic.
func host_online(player_name: String, service: String = OnlineConnection.DEFAULT_SERVICE, control_port: int = OnlineConnection.DEFAULT_CONTROL_PORT, registrar_port: int = OnlineConnection.DEFAULT_REGISTRAR_PORT) -> Error:
	return _begin_online(player_name, "", true, service, control_port, registrar_port)


func join_online(player_name: String, code: String, service: String = OnlineConnection.DEFAULT_SERVICE, control_port: int = OnlineConnection.DEFAULT_CONTROL_PORT, registrar_port: int = OnlineConnection.DEFAULT_REGISTRAR_PORT) -> Error:
	if OnlineConnection.clean_code(code).is_empty():
		last_message = "Enter the full room code copied by the host."
		return ERR_INVALID_PARAMETER
	return _begin_online(player_name, code, false, service, control_port, registrar_port)


func _begin_online(player_name: String, code: String, hosting: bool, service: String, control_port: int, registrar_port: int) -> Error:
	leave_room()
	_requested_name = _clean_name(player_name)
	online_room = true
	room_code = "" if hosting else "BF-" + OnlineConnection.clean_code(code)
	connecting = true
	_connect_deadline = Time.get_ticks_msec() + 25000
	var result := _online.begin(hosting, code, service, control_port, registrar_port)
	if result != OK:
		leave_room()
		last_message = "Check the room code and online service settings."
	return result


func _online_host_ready(peer: ENetMultiplayerPeer, local_port: int, code: String) -> void:
	_peer = peer
	port = local_port
	room_code = code
	multiplayer.multiplayer_peer = _peer
	connecting = false
	active = true
	players[1] = _new_player(1, _requested_name, 0)
	_pose_times[1] = Time.get_ticks_msec()
	last_message = "Online room created. Share the room code with your friends."
	roster_changed.emit()
	room_ready.emit()


func _online_guest_ready(peer: ENetMultiplayerPeer) -> void:
	_peer = peer
	multiplayer.multiplayer_peer = _peer
	_connect_deadline = Time.get_ticks_msec() + 12000


## Joining remains cancellable; room_ready waits for the host's accepted roster.
func join_room(player_name: String, address: String, room_port: int = DEFAULT_PORT) -> Error:
	var host_address := address.strip_edges()
	if host_address.to_lower() == "localhost":
		host_address = "127.0.0.1"
	if not host_address.is_valid_ip_address() or room_port < 1024 or room_port > 65535:
		last_message = "Enter a valid host IP address and a port from 1024 to 65535."
		return ERR_INVALID_PARAMETER
	leave_room()
	_requested_name = _clean_name(player_name)
	_peer = ENetMultiplayerPeer.new()
	var result := _peer.create_client(host_address, room_port)
	if result != OK:
		_peer = null
		last_message = "Could not start the connection: " + error_string(result)
		return result
	port = room_port
	multiplayer.multiplayer_peer = _peer
	connecting = true
	_connect_deadline = Time.get_ticks_msec() + 8000
	last_message = "Connecting to %s:%d…" % [host_address, port]
	return OK


## Closing a room releases all state, including occupied seats and pending movement packets.
func leave_room() -> void:
	if _online != null:
		_online.stop()
	online_room = false
	room_code = ""
	active = false
	connecting = false
	if _peer != null:
		_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_peer = null
	players.clear()
	_pose_times.clear()
	_sequences.clear()
	_send_sequence = 0
	_snapshot_elapsed = 0.0
	room_closed.emit()


func _end_connection(message: String) -> void:
	leave_room()
	last_message = message
	connection_ended.emit(message)


func _connected() -> void:
	_register.rpc_id(1, _requested_name, PROTOCOL)


@rpc("any_peer", "call_remote", "reliable", 0)
func _register(player_name: String, protocol: int) -> void:
	if not active or not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or players.has(sender):
		return
	if protocol != PROTOCOL or players.size() >= MAX_PLAYERS:
		_rejected.rpc_id(sender, "This room is full or uses a different game version. Use the same project build.")
		return
	var used: Array[int] = []
	for record in players.values():
		used.append(record.slot)
	var slot := 0
	while used.has(slot):
		slot += 1
	players[sender] = _new_player(sender, _clean_name(player_name), slot)
	_pose_times[sender] = Time.get_ticks_msec()
	_broadcast_roster()


@rpc("authority", "call_remote", "reliable", 0)
func _rejected(message: String) -> void:
	_end_connection(message)


func _new_player(id: int, player_name: String, slot: int) -> Dictionary:
	return {"id": id, "name": player_name, "slot": slot, "color": COLORS[slot], "position": _spawn_position(slot), "yaw": 0.35, "pitch": -0.14, "seat": -1, "epoch": 0}


func _spawn_position(slot: int) -> Vector3:
	return Vector3(2.5 + slot, 0.03, 4.5)


func _clean_name(value: String) -> String:
	var clean := value.replace("\n", " ").replace("\r", " ").replace("\t", " ").strip_edges().left(20)
	return "Player" if clean.is_empty() else clean


func _peer_left(id: int) -> void:
	if not active or not multiplayer.is_server() or not players.has(id):
		return
	players.erase(id)
	_pose_times.erase(id)
	_sequences.erase(id)
	_broadcast_roster()


func _broadcast_roster() -> void:
	var records := players.values()
	for id in players:
		if id != 1:
			_receive_roster.rpc_id(id, records)
	roster_changed.emit()


@rpc("authority", "call_remote", "reliable", 0)
func _receive_roster(records: Array) -> void:
	_last_server_seen = Time.get_ticks_msec()
	players.clear()
	for record in records:
		players[record.id] = record
	var first_join := not active
	connecting = false
	active = true
	last_message = "Connected to the room."
	roster_changed.emit()
	if first_join:
		room_ready.emit()


func _process(delta: float) -> void:
	if connecting and Time.get_ticks_msec() >= _connect_deadline:
		_end_connection("Online room timed out. Check the full room code and that its host is online." if online_room else "Connection timed out. Check the host IP/port, room capacity, and firewall access.")
	if active and not multiplayer.is_server() and Time.get_ticks_msec() - _last_server_seen > 6000:
		_end_connection("Lost connection to the host. You can host or join another room.")
	if not active or not multiplayer.is_server():
		return
	_snapshot_elapsed += delta
	if _snapshot_elapsed >= 0.05:
		_snapshot_elapsed = 0.0
		var poses: Array = []
		for record in players.values():
			poses.append([record.id, record.position, record.yaw, record.pitch, record.seat, record.epoch])
		for id in players:
			if id != 1:
				_receive_poses.rpc_id(id, poses)
		poses_changed.emit()


## Movement uses ordered snapshots; card/seat decisions use reliable messages instead.
func send_pose(location: Vector3, yaw: float, pitch: float) -> void:
	if not active:
		return
	_send_sequence += 1
	if multiplayer.is_server():
		_accept_pose(1, location, yaw, pitch, _send_sequence, players[1].epoch)
	else:
		_submit_pose.rpc_id(1, location, yaw, pitch, _send_sequence, players[multiplayer.get_unique_id()].epoch)


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_pose(location: Vector3, yaw: float, pitch: float, sequence: int, epoch: int) -> void:
	if active and multiplayer.is_server():
		_accept_pose(multiplayer.get_remote_sender_id(), location, yaw, pitch, sequence, epoch)


## Bind movement to its sender, reject stale/non-finite/out-of-room positions, and limit speed.
func _accept_pose(id: int, location: Vector3, yaw: float, pitch: float, sequence: int, epoch: int) -> void:
	if not players.has(id) or epoch != players[id].epoch or sequence <= int(_sequences.get(id, 0)):
		return
	if not location.is_finite() or not is_finite(yaw) or not is_finite(pitch):
		return
	_sequences[id] = sequence
	var record: Dictionary = players[id]
	if record.seat < 0:
		var elapsed := clampf((Time.get_ticks_msec() - int(_pose_times.get(id, Time.get_ticks_msec()))) / 1000.0, 0.0, 1.0)
		if absf(location.x) > ROOM_HALF_WIDTH or absf(location.z) > ROOM_HALF_DEPTH or location.y < -0.5 or location.y > 3.1 or location.distance_to(record.position) > 9.0 * elapsed + 0.8:
			_force_pose(id, record.position, record.yaw, record.pitch, record.seat)
			return
		record.position = location
	record.yaw = wrapf(yaw, -PI, PI)
	record.pitch = clampf(pitch, deg_to_rad(-75.0), deg_to_rad(75.0))
	_pose_times[id] = Time.get_ticks_msec()


@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _receive_poses(poses: Array) -> void:
	_last_server_seen = Time.get_ticks_msec()
	for pose in poses:
		if players.has(pose[0]) and pose[5] == players[pose[0]].epoch:
			var record: Dictionary = players[pose[0]]
			record.position = pose[1]
			record.yaw = pose[2]
			record.pitch = pose[3]
			# Seats are committed on reliable roster/teleport messages, not old movement packets.
	poses_changed.emit()


func request_seat(index: int) -> void:
	if not active:
		return
	if multiplayer.is_server():
		_reserve_seat(1, index)
	else:
		_seat_request.rpc_id(1, index)


@rpc("any_peer", "call_remote", "reliable", 0)
func _seat_request(index: int) -> void:
	if active and multiplayer.is_server():
		_reserve_seat(multiplayer.get_remote_sender_id(), index)


func seat_owner(index: int) -> int:
	for record in players.values():
		if record.seat == index:
			return record.id
	return 0


## Seat ownership is atomic on the host. Every player can stand or reset at any time.
func _reserve_seat(id: int, index: int) -> void:
	if not players.has(id):
		return
	var record: Dictionary = players[id]
	if index == -1 and record.seat >= 0:
		var old: int = record.seat
		var exit_position := SEATS[old] + Vector3(0, 0, 1.05).rotated(Vector3.UP, SEAT_YAWS[old])
		exit_position.y = 0.03
		_force_pose(id, exit_position, SEAT_YAWS[old], -0.14, -1)
		return
	if index < 0 or index >= SEATS.size() or record.seat >= 0:
		return
	var offset: Vector3 = record.position - SEATS[index]
	if Vector2(offset.x, offset.z).length() > 2.3 or record.position.y > 0.8:
		_tell(id, "Move closer to the chair to sit.")
		return
	if seat_owner(index) != 0:
		_tell(id, "That seat is occupied. Choose another chair.")
		return
	_force_pose(id, SEATS[index], SEAT_YAWS[index], -0.55, index)


func request_reset() -> void:
	if not active:
		return
	if multiplayer.is_server():
		_reset_player(1)
	else:
		_reset_request.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable", 0)
func _reset_request() -> void:
	if active and multiplayer.is_server():
		_reset_player(multiplayer.get_remote_sender_id())


func _reset_player(id: int) -> void:
	if not players.has(id):
		return
	_force_pose(id, _spawn_position(players[id].slot), 0.35, -0.14, -1)


func _force_pose(id: int, location: Vector3, yaw: float, pitch: float, seat: int) -> void:
	var record: Dictionary = players[id]
	record.position = location
	record.yaw = yaw
	record.pitch = pitch
	record.seat = seat
	record.epoch += 1
	_pose_times[id] = Time.get_ticks_msec()
	if id == 1:
		teleported.emit(location, yaw, pitch, seat)
	else:
		_teleport.rpc_id(id, location, yaw, pitch, seat, record.epoch)
	_broadcast_roster()


signal teleported(location: Vector3, yaw: float, pitch: float, seat: int)


@rpc("authority", "call_remote", "reliable", 0)
func _teleport(location: Vector3, yaw: float, pitch: float, seat: int, epoch: int) -> void:
	var id := multiplayer.get_unique_id()
	if players.has(id):
		players[id].position = location
		players[id].yaw = yaw
		players[id].pitch = pitch
		players[id].seat = seat
		players[id].epoch = epoch
	teleported.emit(location, yaw, pitch, seat)


func _tell(id: int, message: String) -> void:
	if id == 1:
		notice_received.emit(message)
	else:
		_notice.rpc_id(id, message)


@rpc("authority", "call_remote", "reliable", 0)
func _notice(message: String) -> void:
	notice_received.emit(message)


## Show LAN candidates without requiring a separate address lookup or internet service.
func lan_addresses() -> PackedStringArray:
	var addresses := PackedStringArray()
	for address in IP.get_local_addresses():
		if not ":" in address and not address.begins_with("127.") and not address.begins_with("169.254.") and address != "0.0.0.0":
			addresses.append(address)
	return addresses
