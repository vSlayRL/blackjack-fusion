extends "res://scripts/multiplayer/toy_integration_test.gd"
## Fast catch/throw flows use real F/click events and real host contact signals.

var player_hits: Array[int] = []


func _run() -> void:
	await _pause(0.5)
	RoomNetwork._force_pose(1, Vector3(-4, 0.03, 3.5), 0, 0, -1)
	_check(ToyNetwork._proxies.size() == 2, "host creates a toy collider for every player")
	for index in [0, 1]:
		_place(index, Vector3(4, 2.5, 0))
		ToyNetwork.bodies[index].interact(Vector3.FORWARD)
		await _pause(0.15)
		_check(ToyNetwork.bodies[index].linear_velocity.length() > 2.3, "push retains strong free speed")
		_check(ToyNetwork.bodies[index].angular_velocity.length() > 10.0, "cube/token spin before hitting a wall")
		var orientation: Basis = ToyNetwork.bodies[index].global_basis
		await _pause(0.12)
		_check(not orientation.is_equal_approx(ToyNetwork.bodies[index].global_basis), "free toy orientation changes")
		ToyNetwork.bodies[index].interact(Vector3.FORWARD)
		await _pause(0.08)
		_check(ToyNetwork.bodies[index].linear_velocity.length() > 4.5, "repeated pushes build momentum")
		# Stop this toy away from the next case, without resetting interaction properties.
		_place(index, Vector3(-5, 3.5, -3 - index))
	_place(0, Vector3(4, 2.5, 0))
	ToyNetwork.bodies[0].linear_velocity = Vector3(4.5, 0, 0)
	ToyNetwork.bodies[0].held = true
	ToyNetwork.bodies[0].drop()
	await _pause(0.06)
	_check(ToyNetwork.bodies[0].linear_velocity.length() > 4.3, "drop preserves carrying momentum")
	_place(0, Vector3(-5, 3.5, -3))
	var orb := ToyNetwork.bodies[2]
	orb.max_contacts_reported = 12
	orb.contact_monitor = true
	orb.body_entered.connect(_hit_player)
	RoomNetwork._force_pose(1, Vector3(4.8, 0.03, 4.6), 0, -0.15, -1)
	RoomNetwork._force_pose(guest, Vector3(4.8, 0.03, 1.4), 0, 0, -1)
	_place(2, Vector3(4.8, 1.5, 3.5))
	await _aim(2)
	await _key(KEY_F)
	await _pause(0.4)
	await _click_throw()
	await _wait_hit(guest)
	_check(ToyNetwork.owners[2] == 0, "host throw collides with a remote player too")
	player_hits.clear()
	# A recent in-reach observation is accepted only within the small movement margin.
	RoomNetwork._force_pose(1, Vector3(4, 0.03, 4.5), 0, 0, -1)
	var seen := Vector3(4, 1.68, 1.8)
	_place(2, seen)
	var serial: int = ToyNetwork._serial
	ToyNetwork.bodies[2].global_position.z = 1.45
	ToyNetwork._accept(1, "grab", 2, ToyNetwork.revisions[2], 100, serial, seen)
	_check(ToyNetwork.owners[2] == 1, "recent nearby snapshot tolerates a fast toy crossing reach edge")
	ToyNetwork._release(2)
	ToyNetwork._sequences[1] = 100
	for sample in ToyNetwork._history:
		sample.time -= 1000
	ToyNetwork._accept(1, "grab", 2, ToyNetwork.revisions[2], 101, serial, seen)
	_check(ToyNetwork.owners[2] == 0, "old observations cannot extend grab range")
	_place(2, seen)
	serial = ToyNetwork._serial
	ToyNetwork.bodies[2].global_position.z = 0.5
	ToyNetwork._accept(1, "grab", 2, ToyNetwork.revisions[2], 102, serial, seen)
	_check(ToyNetwork.owners[2] == 0, "fast catch cannot grab across room")
	# Even a nearby body is not reachable through physical room geometry.
	RoomNetwork._force_pose(1, Vector3(6.3, 0.03, 3.5), -PI / 2.0, 0, -1)
	_place(2, Vector3(7.1, 1.6, 3.5))
	ToyNetwork._accept(1, "grab", 2, ToyNetwork.revisions[2], 103)
	_check(ToyNetwork.owners[2] == 0, "wall blocks a nearby grab")
	ToyNetwork._sequences[1] = ToyNetwork._request_sequence
	RoomNetwork._force_pose(1, Vector3(-4, 0.03, 3.5), 0, 0, -1)
	RoomNetwork._force_pose(guest, Vector3(4.8, 0.03, 4.6), 0, -0.15, -1)
	_place(2, Vector3(-4, 3.5, -3))
	await _step(guest, "clear_fast")
	# Let the guest wait for a fast crossing, then press F after the aim line has passed.
	replies.erase("fast_grab")
	_command.rpc_id(guest, "fast_grab")
	await _pause(0.2)
	_place(2, Vector3(3.2, 1.5, 3.5))
	ToyNetwork.bodies[2].linear_velocity = Vector3(6, 0, 0)
	while not replies.has("fast_grab"):
		await get_tree().process_frame
	_check(ToyNetwork.owners[2] == guest, "F reliably catches nearby fast-moving toy")
	print("TOY LATE JOIN READY")
	while RoomNetwork.players.size() < 3:
		await _pause(0.05)
	var late := 0
	for id in RoomNetwork.players:
		if id not in [1, guest]:
			late = id
	await _pause(0.4)
	await _step(late, "late_state")
	await _step(guest, "center_check")
	# A guest throws at the host, then at a seated host. Only the toy receives the impact.
	var toy := ToyNetwork.bodies[2]
	RoomNetwork._force_pose(1, Vector3(4.8, 0.03, 1.4), 0, 0, -1)
	await _pause(0.1)
	var host_position: Vector3 = room.local_avatar.position
	var host_rotation: Vector3 = room.local_avatar.camera.rotation
	await _step(guest, "throw_click")
	await _wait_hit(1)
	_check(ToyNetwork.owners[2] == 0 and not toy.held, "click releases thrown body")
	_check(room.local_avatar.position.distance_to(host_position) < 0.05 and room.local_avatar.camera.rotation.is_equal_approx(host_rotation), "impact never moves host camera or player")
	await _step(late, "free_motion")
	# Re-grab in front of the guest, then hit a seated player through the space above felt.
	_place(2, Vector3(4.8, 1.5, 3.5))
	await _step(guest, "grab_f")
	RoomNetwork._force_pose(1, RoomNetwork.SEATS[3], 0, 0, 3)
	RoomNetwork._force_pose(guest, Vector3(2.7, 0.03, 4.6), 0, -0.12, -1)
	# A station teleport deliberately releases, so pick it up at the new approach.
	_place(2, Vector3(2.7, 1.8, 3.5))
	await _step(guest, "grab_f")
	player_hits.clear()
	await _step(guest, "throw_click")
	await _wait_hit(1)
	_check(room.local_avatar.seat_index == 3, "seated player keeps seat after toy impact")
	await _shot("toy-player-collision.png")
	await _step(guest, "finish")
	await _step(late, "finish")
	await _pause(0.3)
	print("PASS: lively spin/momentum, reticle hold, fast catch, bounded history and walking/seated player throws")
	RoomNetwork.leave_room()
	get_tree().quit()


func _click_throw() -> void:
	var click := InputEventMouseButton.new()
	click.position = get_viewport().get_visible_rect().size / 2.0
	click.global_position = click.position
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await get_tree().process_frame
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	await _pause(0.1)


func _hit_player(body: Node) -> void:
	if body.has_meta("toy_player_id"):
		player_hits.append(int(body.get_meta("toy_player_id")))


func _wait_hit(id: int) -> void:
	var until := Time.get_ticks_msec() + 1500
	while not player_hits.has(id) and Time.get_ticks_msec() < until:
		await get_tree().physics_frame
	_check(player_hits.has(id), "throw produces a real contact with target player capsule")


@rpc("authority", "call_remote", "reliable", 0)
func _command(command: String) -> void:
	match command:
		"clear_fast":
			var until := Time.get_ticks_msec() + 1500
			while ToyNetwork.bodies[2].global_position.x > -3.0 and Time.get_ticks_msec() < until:
				await get_tree().process_frame
			_check(ToyNetwork.bodies[2].global_position.x < -3.0, "fast catch starts after prior throw state has cleared")
			ToyNetwork._selection.clear()
		"fast_grab":
			var camera: Camera3D = room.local_avatar.camera
			var offset := Vector3(4.8, 1.5, 3.5) - camera.global_position
			room.local_avatar.rotation.y = atan2(-offset.x, -offset.z)
			camera.rotation.x = atan2(offset.y, Vector2(offset.x, offset.z).length())
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			var center := get_viewport().get_visible_rect().size / 2.0
			Input.warp_mouse(center)
			var motion := InputEventMouseMotion.new()
			motion.position = center
			motion.global_position = center
			Input.parse_input_event(motion)
			var until := Time.get_ticks_msec() + 2500
			while room._aimed_toy() != 2 and Time.get_ticks_msec() < until:
				await get_tree().process_frame
			_check(room._aimed_toy() == 2 and "Grab" in room._toy_hint(), "fast crossing offers a grab prompt")
			await _pause(0.12)
			var picked: int = room._aimed_toy()
			_check(picked == 2, "brief timing tolerance keeps prompt actionable")
			await _key(KEY_F)
			await _pause(0.5)
			_check(ToyNetwork.held_by(multiplayer.get_unique_id()) == 2, "fast F is accepted by host")
		"center_check":
			await _pause(0.3)
			var projected: Vector2 = room.local_avatar.camera.unproject_position(ToyNetwork.bodies[2].global_position)
			_check(projected.distance_to(get_viewport().get_visible_rect().size / 2.0) < 8.0, "held object center aligns with reticle")
			await _shot("reticle-centered-hold.png")
		"throw_click":
			await _click_throw()
			_check(ToyNetwork.held_by(multiplayer.get_unique_id()) == -1, "click throws held object")
		"free_motion":
			_check(ToyNetwork.owners[2] == 0 and ToyNetwork.bodies[2].freeze, "observer sees released host-simulated toy")
		_:
			super._command(command)
			return
	_done.rpc_id(1, command)
