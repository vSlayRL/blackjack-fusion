extends "res://scripts/multiplayer/table_integration_test.gd"
## Reuse the full Classic integration flow with forced relays instead of direct ENet.


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
	RoomNetwork.room_ready.connect(_joined)
	RoomNetwork.connection_ended.connect(_closed)
	deadline = Time.get_ticks_msec() + 50000
	if role == "host":
		_check(RoomNetwork.host_online("Host", "127.0.0.1", control, registrar) == OK, "Online host starts asynchronously.")
	else:
		_check(RoomNetwork.join_online(role, code, "127.0.0.1", control, registrar) == OK, "Room code starts asynchronous relay join.")


func _joined() -> void:
	super._joined()
	_check(RoomNetwork.online_room and RoomNetwork.room_code.begins_with("BF-"), "Online mode retains the public room code.")
	if role == "host":
		print("ONLINE ROOM CODE " + RoomNetwork.room_code)
