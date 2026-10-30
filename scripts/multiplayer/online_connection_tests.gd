extends Node
## Launcher handlers and cancellation/failure cleanup against a real local protocol service.

var launcher: Control
var control: int = 8890
var registrar: int = 8809
var deadline: int


func _ready() -> void:
	get_window().size = Vector2i(640, 560)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--control="):
			control = int(argument.trim_prefix("--control="))
		elif argument.begins_with("--registrar="):
			registrar = int(argument.trim_prefix("--registrar="))
	deadline = Time.get_ticks_msec() + 20000
	launcher = preload("res://scenes/multiplayer/launcher.tscn").instantiate()
	add_child(launcher)
	# Keep the test scene alive; exercise production Host/Join handlers without scene replacement.
	RoomNetwork.room_ready.disconnect(launcher._enter_room)
	_run()


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		_check(false, "online UI flow timed out")


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("ONLINE CONNECTION TEST: " + message)
		get_tree().quit(1)


func _pause(seconds: float = 0.1) -> void:
	await get_tree().create_timer(seconds).timeout


func _wait_idle() -> void:
	var until := Time.get_ticks_msec() + 3500
	while RoomNetwork.connecting and Time.get_ticks_msec() < until:
		await _pause(0.05)
	_check(not RoomNetwork.connecting, "connection finishes or fails without trapping input")


func _run() -> void:
	await _pause()
	_check(launcher.mode_select.selected == 0 and launcher.code_edit.get_parent().visible and not launcher.address_edit.get_parent().visible, "Online defaults to a room-code form")
	_check(RoomNetwork.join_online("P", "bad\nregister-host") == ERR_INVALID_PARAMETER and not RoomNetwork.connecting, "invalid codes are rejected before opening any socket")
	_check(OnlineConnection.clean_code("  BF-test_room-1  ") == "test_room-1", "copied codes trim surrounding whitespace")
	launcher.service_edit.text = "127.0.0.1"
	launcher.control_spin.value = control
	launcher.registrar_spin.value = registrar
	launcher._host()
	launcher._cancel()
	await _pause(0.3)
	_check(not RoomNetwork.active and not RoomNetwork.connecting and RoomNetwork._online.stage == OnlineConnection.Stage.IDLE and RoomNetwork.room_code.is_empty(), "cancelled DNS/registration cannot later create a room")
	launcher._host()
	await _wait_idle()
	_check(RoomNetwork.active and RoomNetwork.online_room and RoomNetwork.room_code.begins_with("BF-"), "Host button registers an online room")
	var code := RoomNetwork.room_code
	_check(not RoomNetwork._online._pid.is_empty() and not _contains_text(launcher, RoomNetwork._online._pid), "private service identifier never appears in launcher controls")
	RoomNetwork.leave_room()
	_check(RoomNetwork._online.stage == OnlineConnection.Stage.IDLE and TableNetwork.state.is_empty(), "leave clears online transport and game state")
	launcher._host()
	await _wait_idle()
	_check(RoomNetwork.active and RoomNetwork.room_code != code, "hosting again creates a fresh room code")
	# Loss of the control connection closes a service-dependent room cleanly.
	RoomNetwork._online._tcp.disconnect_from_host()
	await _pause()
	_check(not RoomNetwork.active and not RoomNetwork.connecting and RoomNetwork.room_code.is_empty(), "online service loss cleans up the room")
	launcher.code_edit.text = "BF-nonexistent-room"
	launcher._join()
	await _wait_idle()
	_check(not RoomNetwork.active and "code" in RoomNetwork.last_message, "invalid room receives an actionable error")
	launcher._host()
	# Exercise the real deadline path without waiting twenty seconds per test run.
	RoomNetwork._online._deadline = Time.get_ticks_msec() - 1
	await _pause()
	launcher._process(0.0)
	_check(not RoomNetwork.connecting and not launcher.host_button.disabled and not launcher.join_button.disabled and "timed out" in launcher.status.text, "timeout restores usable launcher controls")
	launcher.mode_select.select(1)
	launcher._mode_changed(1)
	_check(not launcher.code_edit.get_parent().visible and launcher.address_edit.get_parent().visible and launcher.port_row.visible, "LAN mode retains direct IP and port")
	_check(RoomNetwork.host_room("LAN", control) == OK and not RoomNetwork.online_room, "LAN hosting still works after online cancellation/errors")
	RoomNetwork.leave_room()
	print("PASS: online launcher, code validation, cancellation, rehost, private ID, service loss, invalid room, timeout and LAN fallback")
	get_tree().quit()


func _contains_text(node: Node, value: String) -> bool:
	if (node is Label or node is LineEdit or node is Button) and value in node.text:
		return true
	for child in node.get_children():
		if _contains_text(child, value):
			return true
	return false
