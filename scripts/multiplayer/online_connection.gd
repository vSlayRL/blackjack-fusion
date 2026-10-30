class_name OnlineConnection
extends Node
## Noray relay transport for the existing ENet game. No gameplay state lives here.
## Protocol/handshake adapted from Fox's Sake netfox.noray (MIT); see third_party/noray.

signal host_ready(peer: ENetMultiplayerPeer, local_port: int, code: String)
signal guest_ready(peer: ENetMultiplayerPeer)
signal failed(message: String)
signal progress(message: String)

const DEFAULT_SERVICE: String = "foxssake.studio"
const DEFAULT_CONTROL_PORT: int = 8890
const DEFAULT_REGISTRAR_PORT: int = 8809
enum Stage { IDLE, RESOLVING, CONTROL, IDENTIFIERS, REGISTERING, HOSTING, FINDING, HANDSHAKE, JOINING }

var stage: Stage = Stage.IDLE
var _tcp: StreamPeerTCP
var _udp: PacketPeerUDP
var _net: ENetMultiplayerPeer
var _hosting: bool = false
var _service: String = ""
var _address: String = ""
var _control_port: int = DEFAULT_CONTROL_PORT
var _registrar_port: int = DEFAULT_REGISTRAR_PORT
var _query_id: int = -1
var _deadline: int = 0
var _next_send: int = 0
var _buffer: String = ""
var _oid: String = ""
var _pid: String = "" # Session credential: never logged, displayed or persisted.
var _target: String = ""
var _local_port: int = 0
var _relay_port: int = 0
var _handshake_read: bool = false
var _host_handshakes: Dictionary = {}


static func clean_code(value: String) -> String:
	var code := value.strip_edges()
	if code.begins_with("BF-"):
		code = code.substr(3)
	if code.is_empty() or code.length() > 96:
		return ""
	for character in code:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return ""
	return code


func begin(hosting: bool, code: String, service: String, control_port: int, registrar_port: int) -> Error:
	stop()
	_target = clean_code(code)
	if (not hosting and _target.is_empty()) or service.strip_edges().is_empty() or control_port < 1024 or control_port > 65535 or registrar_port < 1024 or registrar_port > 65535:
		return ERR_INVALID_PARAMETER
	_hosting = hosting
	_service = service.strip_edges()
	_control_port = control_port
	_registrar_port = registrar_port
	_deadline = Time.get_ticks_msec() + 20000
	stage = Stage.RESOLVING
	progress.emit("Connecting online…")
	_query_id = IP.resolve_hostname_queue_item(_service, IP.TYPE_IPV4)
	return OK


## Cancellation invalidates all work; no awaited callbacks can resurrect a cancelled room.
func stop() -> void:
	stage = Stage.IDLE
	if _query_id >= 0:
		IP.erase_resolve_item(_query_id)
		_query_id = -1
	if _tcp != null:
		_tcp.disconnect_from_host()
	if _udp != null:
		_udp.close()
	_tcp = null
	_udp = null
	_net = null # RoomNetwork owns and closes an ENet peer after it is handed off.
	_buffer = ""
	_pid = ""
	_oid = ""
	_target = ""
	_host_handshakes.clear()


func _fail(message: String) -> void:
	stop()
	failed.emit(message)


func _process(_delta: float) -> void:
	if stage == Stage.IDLE:
		return
	var now := Time.get_ticks_msec()
	if stage not in [Stage.HOSTING, Stage.JOINING] and now > _deadline:
		_fail("Online connection timed out. Check your internet connection and try again; the shared test service may be unavailable.")
		return
	if stage == Stage.RESOLVING:
		var resolve_status := IP.get_resolve_item_status(_query_id)
		if resolve_status == IP.RESOLVER_STATUS_ERROR:
			_fail("Could not find the online service. Check your internet connection or the service address in Advanced settings.")
		elif resolve_status == IP.RESOLVER_STATUS_DONE:
			_address = IP.get_resolve_item_address(_query_id)
			IP.erase_resolve_item(_query_id)
			_query_id = -1
			_tcp = StreamPeerTCP.new()
			stage = Stage.CONTROL
			if _tcp.connect_to_host(_address, _control_port) != OK:
				_fail("Could not reach the online service. Try again later or use LAN mode.")
		return
	_tcp.poll()
	var status := _tcp.get_status()
	if status in [StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE]:
		_fail("The online service disconnected. Try hosting or joining again.")
		return
	if status != StreamPeerTCP.STATUS_CONNECTED:
		return
	if stage == Stage.CONTROL:
		_tcp.set_no_delay(true)
		stage = Stage.IDENTIFIERS
		_send("register-host")
		progress.emit("Creating your connection…")
	if stage == Stage.IDLE:
		return
	var available := _tcp.get_available_bytes()
	if available > 0:
		var response := _tcp.get_partial_data(mini(available, 8192))
		if response[0] != OK:
			_fail("Could not read from the online service. Please try again.")
			return
		_ingest((response[1] as PackedByteArray).get_string_from_utf8())
	if stage == Stage.IDLE:
		return
	if stage == Stage.IDENTIFIERS and not _pid.is_empty() and not _oid.is_empty():
		_udp = PacketPeerUDP.new()
		if _udp.bind(0, "0.0.0.0") != OK or _udp.set_dest_address(_address, _registrar_port) != OK:
			_fail("Could not open an online connection. Check firewall access for the game.")
			return
		_local_port = _udp.get_local_port()
		stage = Stage.REGISTERING
		_next_send = 0
	if stage == Stage.REGISTERING:
		_register_remote(now)
	elif stage == Stage.HANDSHAKE:
		_handshake(now)
	if stage == Stage.HOSTING:
		for relay in _host_handshakes.keys():
			var entry: Dictionary = _host_handshakes[relay]
			if now > entry.until:
				_host_handshakes.erase(relay)
			elif now >= entry.next:
				if _net != null and _net.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
					_net.host.socket_send(_address, relay, "$rwx".to_ascii_buffer())
				entry.next = now + 100


func _send(command: String) -> void:
	if _tcp.put_data((command + "\n").to_utf8_buffer()) != OK:
		_fail("Could not send to the online service. Please try again.")


## The control channel is newline framed. Limit both individual lines and buffered data.
func _ingest(data: String) -> void:
	_buffer += data
	if _buffer.length() > 16384:
		_fail("The online service returned an invalid response.")
		return
	while _buffer.contains("\n") and stage != Stage.IDLE:
		var split := _buffer.find("\n")
		var line := _buffer.substr(0, split).strip_edges()
		_buffer = _buffer.substr(split + 1)
		if line.length() > 512:
			_fail("The online service returned an invalid response.")
			return
		var separator := line.find(" ")
		var command := line if separator < 0 else line.substr(0, separator)
		var value := "" if separator < 0 else line.substr(separator + 1)
		match command:
			"set-oid":
				if stage == Stage.IDENTIFIERS:
					_oid = clean_code(value)
			"set-pid":
				if stage == Stage.IDENTIFIERS and not value.is_empty() and value.length() <= 256:
					_pid = value
			"connect-relay": _relay_requested(value)
			"error", "err", "invalid-host", "host-not-found":
				_fail("That room could not be reached. Check the full room code and that its host is still online.")


func _register_remote(now: int) -> void:
	if now >= _next_send:
		_udp.put_packet(_pid.to_utf8_buffer())
		_next_send = now + 150
	while _udp != null and _udp.get_available_packet_count() > 0:
		var packet := _udp.get_packet().get_string_from_utf8()
		if _udp.get_packet_ip() != _address or _udp.get_packet_port() != _registrar_port:
			continue
		if packet != "OK":
			_fail("The online service could not register this connection. Please try again.")
			return
		_udp.close()
		_udp = null
		if _hosting:
			_net = ENetMultiplayerPeer.new()
			if _net.create_server(_local_port, RoomNetwork.MAX_PLAYERS - 1) != OK:
				_fail("Could not open the online room. Please try again.")
				return
			stage = Stage.HOSTING
			progress.emit("Online room ready.")
			host_ready.emit(_net, _local_port, "BF-" + _oid)
		else:
			stage = Stage.FINDING
			progress.emit("Finding room…")
			_send("connect-relay " + _target)
		return


func _relay_requested(value: String) -> void:
	if not value.is_valid_int():
		_fail("The online service returned an invalid relay address.")
		return
	var relay := int(value)
	if relay < 1024 or relay > 65535:
		_fail("The online service returned an invalid relay address.")
		return
	if _hosting and stage == Stage.HOSTING:
		if _host_handshakes.size() < 8:
			_host_handshakes[relay] = {"until": Time.get_ticks_msec() + 8000, "next": 0}
	elif not _hosting and stage == Stage.FINDING:
		_udp = PacketPeerUDP.new()
		if _udp.bind(_local_port, "0.0.0.0") != OK or _udp.set_dest_address(_address, relay) != OK:
			_fail("Could not join the online room. Check firewall access and try again.")
			return
		_relay_port = relay
		_handshake_read = false
		stage = Stage.HANDSHAKE
		_next_send = 0
		progress.emit("Joining room…")


func _handshake(now: int) -> void:
	while _udp.get_available_packet_count() > 0:
		var data := _udp.get_packet().get_string_from_ascii()
		if _udp.get_packet_ip() != _address or _udp.get_packet_port() != _relay_port or not data.begins_with("$"):
			continue
		_handshake_read = true
		if "r" in data and "x" in data:
			_udp.put_packet("$rwx".to_ascii_buffer())
			_udp.close()
			_udp = null
			_net = ENetMultiplayerPeer.new()
			if _net.create_client(_address, _relay_port, 0, 0, 0, _local_port) != OK:
				_fail("Could not start the online game connection. Please try again.")
				return
			stage = Stage.JOINING
			guest_ready.emit(_net)
			return
	if now >= _next_send:
		_udp.put_packet(("$rw-" if _handshake_read else "$-w-").to_ascii_buffer())
		_next_send = now + 100
