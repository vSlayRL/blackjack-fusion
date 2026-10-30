extends Node
## Real ENet peers exercise ownership, rendering replicas, contacts and actual keyboard events.

var role: String = "host"
var port: int = 24890
var room: Node3D
var guest: int = 0
var running: bool = false
var replies: Dictionary = {}
var deadline: int
var screenshots: String = ""


func _ready() -> void:
	get_window().size = Vector2i(960, 640)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--screenshots="):
			screenshots = argument.trim_prefix("--screenshots=")
	deadline = Time.get_ticks_msec() + 60000
	RoomNetwork.room_ready.connect(func():
		room = preload("res://scenes/multiplayer/network_lounge.tscn").instantiate()
		add_child(room))
	if role == "host":
		_check(RoomNetwork.host_room("Toy Host", port) == OK, "host starts")
	else:
		_check(RoomNetwork.join_room("Toy " + role, "127.0.0.1", port) == OK, "guest starts")


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() > deadline:
		_check(false, "toy flow timed out")
	if role == "host" and not running and RoomNetwork.players.size() == 2:
		running = true
		for id in RoomNetwork.players:
			if id != 1:
				guest = id
		_run()


func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("TOY TEST [%s]: %s" % [role, message])
		get_tree().quit(1)


func _pause(seconds: float = 0.25) -> void:
	await get_tree().create_timer(seconds).timeout


func _step(peer: int, command: String) -> void:
	await _pause(0.35)
	replies.erase(command)
	_command.rpc_id(peer, command)
	while not replies.has(command):
		await get_tree().process_frame


func _place(index: int, point: Vector3) -> void:
	var toy: LoungeProp = ToyNetwork.bodies[index]
	toy.held = false
	toy.global_position = point
	toy.linear_velocity = Vector3.ZERO
	toy.angular_velocity = Vector3.ZERO
	toy.sleeping = false
	ToyNetwork._publish(true)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)


func _aim(index: int) -> void:
	var camera: Camera3D = room.local_avatar.camera
	var point: Vector3 = ToyNetwork.bodies[index].global_position
	var offset := point - camera.global_position
	room.local_avatar.rotation.y = atan2(-offset.x, -offset.z)
	camera.rotation.x = atan2(offset.y, Vector2(offset.x, offset.z).length())
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var screen := camera.unproject_position(point)
	Input.warp_mouse(screen)
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	await _pause(0.15)
	if room._aimed_toy() != index:
		print("PICK DEBUG ", screen, " mouse ", get_viewport().get_mouse_position(), " camera ", camera.global_position, " toy ", point, " direct ", ToyNetwork.pick(camera, screen))
	_check(room._aimed_toy() == index, "actual cursor ray selects toy")


func _shot(filename: String) -> void:
	if screenshots.is_empty() or DisplayServer.get_name() == "headless":
		return
	await get_tree().process_frame
	RenderingServer.force_draw()
	_check(get_viewport().get_texture().get_image().save_png(screenshots.path_join(filename)) == OK, "screenshot saves")


func _run() -> void:
	await _pause(0.5)
	_check(ToyNetwork.bodies.size() == 3 and not ToyNetwork.bodies[0].freeze, "host simulates three bodies")
	RoomNetwork._force_pose(guest, Vector3(4.8, 0.03, 4.6), 0, -0.15, -1)
	_place(2, Vector3(4.8, 1.5, 3.5))
	await _step(guest, "grab_f")
	_check(ToyNetwork.owners[2] == guest and ToyNetwork.bodies[2].held, "F on guest grants ownership")
	var revision: int = ToyNetwork.revisions[2]
	ToyNetwork.request("grab", 2)
	_check(ToyNetwork.owners[2] == guest, "another player cannot steal a held object")
	ToyNetwork._accept(guest, "drop", 2, revision - 1, 100)
	_check(ToyNetwork.owners[2] == guest, "stale ownership packet cannot drop")
	# Restore test sequence after deliberately injecting an old request.
	ToyNetwork._sequences[guest] = 1
	await _step(guest, "carry")
	_check(ToyNetwork.bodies[2].global_position.distance_to(ToyNetwork._hold_target(guest)) < 0.25, "held body follows accepted look")
	await _step(guest, "carry_wall")
	_check(ToyNetwork.bodies[2].position.x < 6.85 and ToyNetwork.owners[2] == guest, "held body stays inside wall while moving and looking out")
	print("TOY LATE JOIN READY")
	while RoomNetwork.players.size() < 3:
		await _pause(0.05)
	var late := 0
	for id in RoomNetwork.players:
		if id not in [1, guest]:
			late = id
	await _pause(0.5)
	await _step(late, "late_state")
	await _step(guest, "drop_f")
	_check(ToyNetwork.owners[2] == 0 and not ToyNetwork.bodies[2].held, "F releases body")
	# Actual left-click dispatch changes the orb on the host, then every observer.
	_place(2, Vector3(4.8, 1.5, 3.5))
	RoomNetwork._force_pose(guest, Vector3(4.8, 0.03, 4.6), 0, -0.15, -1)
	var before := str(TableNetwork.state)
	await _step(guest, "click_push")
	_check(ToyNetwork.bodies[2].interaction_count == 1 and ToyNetwork.bodies[2].warm_light, "push/glow runs exactly once on host")
	await _step(late, "glow_state")
	_check(str(TableNetwork.state) == before, "toys do not change cards, balances or session")
	_place(2, Vector3(4.8, 1.0, 3.5))
	await _step(guest, "walk_nudge")
	_check(ToyNetwork.bodies[2].linear_velocity.z < -0.1, "accepted walking movement nudges a free toy")
	# Free contact bounce, not a visual ping-pong animation.
	_place(0, Vector3(6.2, 2.0, 0))
	ToyNetwork.bodies[0].linear_velocity = Vector3(2, 0, 0)
	await _pause(0.65)
	_check(ToyNetwork.bodies[0].linear_velocity.x < -0.2 and ToyNetwork.bodies[0].position.x < 6.85, "die bounces off physical wall")
	_place(0, Vector3(4.0, 0.4, 0))
	ToyNetwork.bodies[0].linear_velocity = Vector3(0, -2, 0)
	await _pause(0.4)
	_check(ToyNetwork.bodies[0].linear_velocity.y > 0.2, "floor bounces")
	_place(0, Vector3(4.0, 4.4, 0))
	ToyNetwork.bodies[0].linear_velocity = Vector3(0, 2, 0)
	await _pause(0.5)
	_check(ToyNetwork.bodies[0].linear_velocity.y < -0.2, "ceiling bounces")
	_place(0, Vector3(4.0, 2.0, 2.0))
	_place(1, Vector3(4.6, 2.0, 2.0))
	ToyNetwork.bodies[0].linear_velocity = Vector3(2, 0, 0)
	await _pause(0.6)
	_check(ToyNetwork.bodies[1].linear_velocity.x > 0.2, "toy collision transfers momentum")
	var token_x: float = ToyNetwork.bodies[1].position.x
	await _pause(0.3)
	_check(ToyNetwork.bodies[1].position.x > token_x + 0.05, "released toys drift without returning home")
	RoomNetwork._force_pose(guest, Vector3(4.8, 0.03, 4.6), 0, -0.15, -1)
	_place(1, Vector3(4.8, 1.7, 3.5))
	await _step(guest, "grab_token")
	_check(ToyNetwork.owners[1] == guest, "token selectable")
	RoomNetwork._reset_player(guest)
	await _pause()
	_check(ToyNetwork.owners[1] == 0 and not ToyNetwork.bodies[1].held, "reset releases held object before teleport")
	RoomNetwork._force_pose(guest, Vector3(4.8, 0.03, 4.6), 0, -0.15, -1)
	_place(2, Vector3(4.8, 1.5, 3.5))
	await _step(guest, "grab_f")
	await _step(guest, "leave")
	await _pause(0.4)
	_check(not RoomNetwork.players.has(guest) and ToyNetwork.owners[2] == 0, "disconnect releases and preserves toy")
	# Confirm an edited bet with an actual Enter, then use B without clicking elsewhere.
	TableNetwork.start_session(2, 100.0, TableNetwork.state.session.id)
	RoomNetwork._force_pose(1, RoomNetwork.SEATS[2], RoomNetwork.SEAT_YAWS[2], -0.55, 2)
	await _pause()
	_place(2, ToyNetwork._eye(1) - ToyNetwork._view_basis(1).z * 0.9)
	await _aim(2)
	await _key(KEY_F)
	await _pause(0.4)
	_check(ToyNetwork.owners[2] == 1, "seated host can grab too")
	await _shot("seated-toy-held.png")
	await _key(KEY_F)
	await _pause()
	get_window().grab_focus()
	var edit: LineEdit = room.table_hud.bet_spin.get_line_edit()
	edit.grab_focus()
	edit.edit()
	await get_tree().process_frame
	edit.text = "12 + 5"
	await _key(KEY_ENTER)
	await _pause(0.1)
	_check(not edit.has_focus() and is_equal_approx(room.table_hud.bet_spin.value, 17.0), "Enter commits expression and releases bet focus")
	await _key(KEY_B)
	await _pause()
	_check(TableNetwork.state.round == 1 and is_equal_approx(TableNetwork.local_record().hands[0].wager, 17.0), "Ready shortcut works immediately after Enter")
	await _shot("toys-and-bet.png")
	await _step(late, "finish")
	await _pause(0.3)
	print("PASS: host shared toys, contacts, exclusive ownership, late join, departure and Enter focus")
	RoomNetwork.leave_room()
	get_tree().quit()


@rpc("authority", "call_remote", "reliable", 0)
func _command(command: String) -> void:
	match command:
		"grab_f", "grab_token":
			var index := 1 if command == "grab_token" else 2
			await _aim(index)
			await _key(KEY_F)
			await _pause(0.4)
			_check(ToyNetwork.held_by(multiplayer.get_unique_id()) == index and ToyNetwork.bodies[index].freeze, "guest F grabs replicated body")
		"carry":
			room.local_avatar.rotation.y += 0.5
			await _pause(0.8)
		"walk_nudge":
			for index in range(10):
				room.local_avatar.position.z -= 0.08
				await _pause(0.03)
			await _pause(0.2)
		"carry_wall":
			for index in range(25):
				room.local_avatar.position.x += 0.06
				await _pause(0.025)
			room.local_avatar.rotation.y = -PI / 2.0
			room.local_avatar.camera.rotation.x = 0
			await _pause(0.6)
		"late_state":
			_check(ToyNetwork.owners.size() == 3 and ToyNetwork.owners[2] > 1 and ToyNetwork.bodies[2].held, "late join restores current held ownership")
			var eye: Vector3 = RoomNetwork.players[ToyNetwork.owners[2]].position + Vector3(0, 1.65, 0)
			_check(ToyNetwork.bodies[2].global_position.distance_to(eye) < 1.4, "late join restores moved pose")
		"drop_f":
			await _key(KEY_F)
			await _pause()
			_check(ToyNetwork.held_by(multiplayer.get_unique_id()) == -1, "guest F drops")
		"click_push":
			await _aim(2)
			var click := InputEventMouseButton.new()
			click.position = get_viewport().get_mouse_position()
			click.global_position = click.position
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			Input.parse_input_event(click)
			await get_tree().process_frame
			click = click.duplicate()
			click.pressed = false
			Input.parse_input_event(click)
			await _pause(0.4)
		"glow_state":
			_check(ToyNetwork.bodies[2].warm_light and ToyNetwork.bodies[2].interaction_count == 1, "observers see same orb glow")
		"leave":
			_done.rpc_id(1, command)
			await _pause(0.1)
			RoomNetwork.leave_room()
			print("PASS: guest pickup, carry, drop, push, reset and leave")
			get_tree().quit()
			return
		"finish":
			_done.rpc_id(1, command)
			await _pause(0.1)
			print("PASS: late observer sees ownership, poses and glow")
			get_tree().quit()
			return
	_done.rpc_id(1, command)


@rpc("any_peer", "call_remote", "reliable", 0)
func _done(command: String) -> void:
	replies[command] = multiplayer.get_remote_sender_id()
