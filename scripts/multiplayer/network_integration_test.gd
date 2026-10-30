extends Node
## Run through tools/run_multiplayer_tests.py: real independent ENet peers, not mocked RPCs.

var role: String = ""
var test_port: int = 24680
var room: Node3D
var ids: Dictionary = {}
var origin_a: Vector3
var expect_host_close: bool = false
var finishing: bool = false
var _failed: bool = false
var _deadline: int = 0
var _wall_epoch: int = 0

# Open approaches to each physical wall, away from the table, console and doorway.
const WALL_STARTS: Array[Vector3] = [Vector3(5.7, 0.03, 0), Vector3(-5.7, 0.03, 0), Vector3(0, 0.03, -5.2), Vector3(2, 0.03, 5.1)]
const WALL_DIRECTIONS: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			test_port = int(argument.trim_prefix("--port="))
	if role.is_empty():
		print("Run this network test with: python tools/run_multiplayer_tests.py --godot <Godot executable>")
		get_tree().quit()
		return
	RoomNetwork.room_ready.connect(_joined)
	RoomNetwork.connection_ended.connect(_disconnected)
	_deadline = Time.get_ticks_msec() + 42000
	if role in ["host", "crash_host"]:
		_check(RoomNetwork.host_room("Host", test_port) == OK, "Host should bind its UDP port.")
	elif role == "failed":
		_check(RoomNetwork.join_room("Guest", "127.0.0.1", test_port) == OK, "Join should start without blocking.")
	else:
		_check(RoomNetwork.join_room("Guest " + role, "127.0.0.1", test_port) == OK, "Guest should start connecting.")


func _joined() -> void:
	if role == "failed":
		_check(false, "An unused port must not connect.")
		return
	room = preload("res://scenes/multiplayer/network_lounge.tscn").instantiate()
	add_child(room)
	if role == "crash":
		print("CRASH GUEST READY")


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > _deadline and not finishing:
		_check(false, "Network test timed out in role " + role)
	if role != "host" or not ids.is_empty() or RoomNetwork.players.size() != 3:
		return
	for record in RoomNetwork.players.values():
		ids[record.name] = record.id
	_check(ids.has("Guest A") and ids.has("Guest B") and ids.Host == 1, "Three real peers should retain distinct names/identities.")
	_check(room.avatars.size() == 3 and room.local_avatar.camera.current, "Each peer should have one avatar and only its own camera.")
	origin_a = RoomNetwork.players[ids["Guest A"]].position
	_command.rpc_id(ids["Guest A"], "move")


func _check(condition: bool, message: String) -> void:
	if not condition:
		finishing = true
		_failed = true
		push_error("NETWORK TEST FAILED [%s]: %s" % [role, message])
		get_tree().quit(1)


func _pause(seconds: float = 0.25) -> void:
	await get_tree().create_timer(seconds).timeout


@rpc("authority", "call_remote", "reliable", 0)
func _command(action: String) -> void:
	var me := multiplayer.get_unique_id()
	if action.begins_with("wall_"):
		await _exercise_wall(int(action.trim_prefix("wall_")))
		_step_done.rpc_id(1, action)
		return
	match action:
		"move":
			_check(room.avatars.size() == 3 and room.local_avatar.camera.current, "A joining client should see all three avatars without losing its camera.")
			for step in range(12):
				room.local_avatar.position.x -= 0.1
				room.local_avatar.rotation.y = 1.1
				room.local_avatar.camera.rotation.x = 0.25
				await _pause(0.06)
			await _pause()
			_step_done.rpc_id(1, "moved")
		"sit_a":
			RoomNetwork.request_seat(0)
			await _pause()
			_check(room.local_avatar.seat_index == 0 and room.local_avatar.position.is_equal_approx(RoomNetwork.SEATS[0]), "Accepted seat RPC must place the local avatar in its chair.")
			_step_done.rpc_id(1, "seated_a")
		"conflict":
			RoomNetwork.request_seat(0)
			await _pause()
			_check(RoomNetwork.players[me].seat == -1 and RoomNetwork.seat_owner(0) != me, "Another player must not steal an occupied chair.")
			RoomNetwork.send_pose(Vector3(200, 50, 200), 0, 0)
			await _pause()
			_check(room.local_avatar.position.x < 0, "Out-of-room movement should be corrected by the host.")
			RoomNetwork.send_pose(Vector3(NAN, 0, 0), 0, 0)
			await _pause()
			_check(RoomNetwork.players[me].position.is_finite(), "Non-finite movement must not corrupt replicated state.")
			_step_done.rpc_id(1, "conflict_checked")
		"reset_a":
			var old_epoch: int = RoomNetwork.players[me].epoch
			RoomNetwork.request_reset()
			await _pause()
			_check(room.local_avatar.seat_index == -1 and room.local_avatar.position.z > 4.0, "Reset must return the seated player to the entrance.")
			# A packet sent before the reset cannot move the player back into the chair.
			RoomNetwork._submit_pose.rpc_id(1, RoomNetwork.SEATS[0], 0, 0, 99999, old_epoch)
			await _pause()
			_step_done.rpc_id(1, "reset_a")
		"sit_b":
			RoomNetwork.request_seat(0)
			await _pause()
			_check(room.local_avatar.seat_index == 0, "A freed seat must become available to the other guest.")
			_step_done.rpc_id(1, "seated_b")
		"leave_b":
			RoomNetwork.leave_room()
			await _pause()
			_finish("Guest B joined, received movement, lost a seat race, rejected invalid poses, sat, and disconnected.")
		"reconnect_a":
			var old_id := me
			RoomNetwork.leave_room()
			room.queue_free()
			await _pause()
			RoomNetwork.join_room("Guest A", "127.0.0.1", test_port)
			for attempt in range(40):
				await _pause(0.05)
				if RoomNetwork.active:
					break
			_check(RoomNetwork.active and multiplayer.get_unique_id() != old_id and room.avatars.size() == 2, "Rejoining must get a fresh identity and no ghost avatar.")
			_step_done.rpc_id(1, "rejoined")
		"wait_close":
			expect_host_close = true
			_step_done.rpc_id(1, "ready_close")


@rpc("any_peer", "call_remote", "reliable", 0)
func _step_done(step: String) -> void:
	if role != "host":
		return
	var a: int = ids["Guest A"]
	var b: int = ids["Guest B"]
	if step.begins_with("wall_"):
		_check(multiplayer.get_remote_sender_id() == a, "Wall checks must come from Guest A.")
		_check(RoomNetwork.players[a].epoch == _wall_epoch, "Host must not correct legitimate guest wall contact.")
		_check(room.avatars[a].position.distance_to(RoomNetwork.players[a].position) < 0.2, "Wall movement should remain visible to the other players.")
		var next := int(step.trim_prefix("wall_")) + 1
		if next < WALL_STARTS.size():
			await _start_guest_wall(a, next)
		else:
			RoomNetwork._force_pose(a, Vector3(-1.5, 0.03, 2.9), 0, -0.14, -1)
			RoomNetwork._force_pose(b, Vector3(-2.6, 0.03, 2.8), 0, -0.14, -1)
			await _pause()
			_command.rpc_id(a, "sit_a")
		return
	match step:
		"moved":
			_check(multiplayer.get_remote_sender_id() == a, "Movement completion should come from Guest A.")
			_check(RoomNetwork.players[a].position.distance_to(origin_a) > 1.0, "Host should receive actual movement from Guest A.")
			_check(absf(RoomNetwork.players[a].yaw - 1.1) < 0.02, "Host should receive guest rotation.")
			_check(room.avatars[a].position.distance_to(RoomNetwork.players[a].position) < 0.2, "Remote avatar should follow the received position.")
			for index in range(WALL_STARTS.size()):
				RoomNetwork._force_pose(1, WALL_STARTS[index], 0, -0.14, -1)
				await _exercise_wall(index)
			await _start_guest_wall(a, 0)
		"seated_a":
			_check(RoomNetwork.seat_owner(0) == a, "Host must reserve the requested seat for A.")
			_command.rpc_id(b, "conflict")
		"conflict_checked":
			_check(RoomNetwork.seat_owner(0) == a and RoomNetwork.players[b].seat == -1, "Conflicting requests must preserve the original owner.")
			_command.rpc_id(a, "reset_a")
		"reset_a":
			_check(RoomNetwork.seat_owner(0) == 0 and RoomNetwork.players[a].position.z > 4, "Reset must release the seat and reject stale-generation movement.")
			_command.rpc_id(b, "sit_b")
		"seated_b":
			_check(RoomNetwork.seat_owner(0) == b, "B should acquire A's freed seat.")
			_command.rpc_id(b, "leave_b")
			await _pause(0.6)
			_check(RoomNetwork.players.size() == 2 and room.avatars.size() == 2 and RoomNetwork.seat_owner(0) == 0, "Disconnect must remove B and free the chair everywhere.")
			_command.rpc_id(a, "reconnect_a")
		"rejoined":
			var new_id := multiplayer.get_remote_sender_id()
			_check(not RoomNetwork.players.has(a) and RoomNetwork.players.size() == 2 and room.avatars.size() == 2, "Host must remove old identity after reconnect.")
			ids["Guest A"] = new_id
			_command.rpc_id(new_id, "wait_close")
		"ready_close":
			RoomNetwork.leave_room()
			await _pause(0.2)
			_finish("Host verified all four wall collisions for host/guest, camera freedom, movement replication, seats, resets, invalid packets, disconnects, and reconnect.")


func _start_guest_wall(id: int, index: int) -> void:
	RoomNetwork._force_pose(id, WALL_STARTS[index], 0, -0.14, -1)
	_wall_epoch = RoomNetwork.players[id].epoch
	await _pause()
	_command.rpc_id(id, "wall_%d" % index)


## Exercise real CharacterBody3D collisions and the regular network pose sender.
## Drive velocity directly so these checks also work without a focused desktop window.
func _exercise_wall(index: int) -> void:
	var avatar := room.local_avatar as CharacterBody3D
	var me := multiplayer.get_unique_id()
	var epoch: int = RoomNetwork.players[me].epoch
	var direction := WALL_DIRECTIONS[index]
	avatar.set_physics_process(false)
	var contact := Vector3.ZERO
	for frame in range(60):
		await get_tree().physics_frame
		avatar.velocity = direction * 5.2 + Vector3(0, -0.2, 0)
		avatar.move_and_slide()
		avatar.rotation.y = 0.4 + frame * 0.005
		avatar.camera.rotation.x = -0.1 + frame * 0.002
		if frame == 40:
			contact = avatar.position
		elif frame > 40:
			_check(avatar.position.distance_to(contact) < 0.01, "Wall %d must hold the player steadily without jitter." % index)
	print("Wall %d peer %d contact: %s, epoch %d -> %d" % [index, me, avatar.position, epoch, RoomNetwork.players[me].epoch])
	_check(absf(avatar.position.dot(direction) - WALL_STARTS[index].dot(direction)) > 0.8, "Player must reach the actual wall, beyond the former network boundary.")
	await _pause(0.2)
	_check(RoomNetwork.players[me].epoch == epoch, "Wall contact must not trigger a network teleport for peer %d." % me)
	_check(absf(avatar.rotation.y - 0.695) < 0.01 and absf(avatar.camera.rotation.x - 0.018) < 0.01, "Looking around at the wall must retain camera yaw and pitch.")
	for frame in range(20):
		await get_tree().physics_frame
		avatar.velocity = -direction * 5.2 + Vector3(0, -0.2, 0)
		avatar.move_and_slide()
	_check(avatar.position.distance_to(contact) > 1.0, "Player must be able to leave wall %d immediately." % index)
	avatar.velocity = Vector3.ZERO
	avatar.set_physics_process(true)
	await _pause()


func _disconnected(message: String) -> void:
	if role == "failed":
		_check(not RoomNetwork.active and not RoomNetwork.connecting and not message.is_empty(), "Failed join should return an actionable error and clear connection state.")
		_finish("Unreachable host times out cleanly without a stuck connection.")
	elif role == "A":
		_check(expect_host_close and message.contains("host"), "Host shutdown should notify the remaining guest.")
		_finish("Guest A moved, sat/reset, rejoined, and received host-disconnect notification.")
	elif role == "crash":
		_check(not RoomNetwork.active and message.contains("host"), "An abruptly terminated host should release its guest to the launcher.")
		_finish("Abrupt host shutdown is detected and clears the guest connection.")
	else:
		_check(false, "Unexpected disconnect in role " + role)


func _finish(message: String) -> void:
	finishing = true
	if not _failed:
		print("PASS: " + message)
	get_tree().quit(1 if _failed else 0)
