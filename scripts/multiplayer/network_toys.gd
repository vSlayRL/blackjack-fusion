extends Node
## Host-only toy physics. Guests send intentions, never object transforms or impulses.
## This service has a stable autoload path, independent of lounge scene loading order.

signal changed

const REACH: float = 2.8
const TOY_LAYER: int = 16
const PLAYER_LAYER: int = 32
const GRAB_RADIUS: float = 0.24
const PICK_MEMORY_MS: int = 180
const HISTORY_MS: int = 300
var _selection: Dictionary = {}
var _history: Array[Dictionary] = []
var _proxies: Dictionary = {}
var _proxy_epochs: Dictionary = {}
var _release_immunity: Dictionary = {}
var _proxy_root: Node3D
var bodies: Array[NetworkProp] = []
var owners: Array[int] = []
var revisions: Array[int] = []
var _epochs: Dictionary = {}
var _sequences: Dictionary = {}
var _targets: Array = []
var _homes: Array[Transform3D] = []
var _serial: int = 0
var _last_serial: int = -1
var _request_sequence: int = 0
var _pending_until: int = 0
var _elapsed: float = 0.0


func _ready() -> void:
	RoomNetwork.room_closed.connect(_clear)
	RoomNetwork.roster_changed.connect(_roster_changed)


func attach(container: Node3D) -> void:
	bodies.clear()
	_homes.clear()
	for child in container.get_children():
		var toy := child as NetworkProp
		if toy == null:
			continue
		bodies.append(toy)
		_homes.append(toy.global_transform)
		toy.collision_layer = TOY_LAYER
		toy.collision_mask = 1 | TOY_LAYER | PLAYER_LAYER
		toy.freeze = not multiplayer.is_server()
		toy.can_sleep = false
		toy.set_meta("network_toy", bodies.size() - 1)
	if multiplayer.is_server():
		owners.assign([0, 0, 0])
		revisions.assign([0, 0, 0])
		_proxy_root = Node3D.new()
		_proxy_root.name = "ToyPlayerCollisions"
		container.add_child(_proxy_root)
		_update_proxies(0.0)
		_publish(true)
	else:
		_apply_targets(true)
		_sync_request.rpc_id(1)


func detach() -> void:
	if is_instance_valid(_proxy_root):
		_proxy_root.queue_free()
	_proxy_root = null
	_proxies.clear()
	_proxy_epochs.clear()
	_release_immunity.clear()
	_selection.clear()
	_history.clear()
	bodies.clear()
	_homes.clear()


func _clear() -> void:
	detach()
	owners.clear()
	revisions.clear()
	_targets.clear()
	_epochs.clear()
	_sequences.clear()
	_serial = 0
	_last_serial = -1
	_request_sequence = 0
	_pending_until = 0
	_elapsed = 0.0


func held_by(id: int) -> int:
	return owners.find(id) if id > 0 else -1


## A small grab cone is forgiving for thin/spinning toys. The same result drives F and hints.
func pick(camera: Camera3D, screen: Vector2) -> int:
	if bodies.is_empty():
		return -1
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var best := -1
	var best_score := INF
	for index in range(bodies.size()):
		var point := bodies[index].global_position
		var offset := point - origin
		var along := offset.dot(direction)
		var across := (offset - direction * along).length()
		if along <= 0.0 or offset.length() > REACH or across > GRAB_RADIUS or not _visible(origin, point):
			continue
		# Prefer the object closest to the aim line, then nearer distance.
		var score := across + along * 0.015
		if score < best_score:
			best = index
			best_score = score
	if best >= 0:
		_selection = {"index": best, "point": bodies[best].global_position, "origin": origin, "direction": direction,
			"time": Time.get_ticks_msec(), "serial": _serial if multiplayer.is_server() else _last_serial}
		return best
	# Keep a just-shown prompt actionable briefly as a fast toy crosses aim.
	if not _selection.is_empty() and Time.get_ticks_msec() - int(_selection.time) <= PICK_MEMORY_MS:
		var index: int = _selection.index
		var point := bodies[index].global_position
		if direction.dot(_selection.direction) > 0.995 and origin.distance_to(point) <= REACH and _visible(origin, point):
			return index
	_selection.clear()
	return -1


func _visible(origin: Vector3, point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(origin, point, 1)
	return bodies[0].get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func hint(index: int) -> String:
	var mine := held_by(multiplayer.get_unique_id())
	if mine >= 0:
		return "Drop %s [F] · Throw [Click]" % _toy_name(mine)
	if index < 0 or index >= owners.size():
		return ""
	if owners[index] != 0:
		return "%s · held by %s" % [_toy_name(index), RoomNetwork.players.get(owners[index], {}).get("name", "another player")]
	return "Grab %s [F] · Push [Click]" % _toy_name(index)


func _toy_name(index: int) -> String:
	return ["Die", "Token", "Orb"][index]


## One outstanding intention at a time: holding F or repeated clicks cannot toggle twice.
func request(action: String, index: int) -> void:
	if not RoomNetwork.active or index < 0 or index >= revisions.size() or Time.get_ticks_msec() < _pending_until:
		return
	_request_sequence += 1
	var seen_serial := _serial if multiplayer.is_server() else _last_serial
	var seen_point := bodies[index].global_position
	if not _selection.is_empty() and _selection.index == index and Time.get_ticks_msec() - int(_selection.time) <= PICK_MEMORY_MS:
		seen_serial = _selection.serial
		seen_point = _selection.point
	if multiplayer.is_server():
		_accept(1, action, index, revisions[index], _request_sequence, seen_serial, seen_point)
	else:
		_pending_until = Time.get_ticks_msec() + 1500
		_submit.rpc_id(1, action, index, revisions[index], _request_sequence, seen_serial, seen_point)


@rpc("any_peer", "call_remote", "reliable", 0)
func _submit(action: String, index: int, revision: int, sequence: int, seen_serial: int, seen_point: Vector3) -> void:
	if RoomNetwork.active and multiplayer.is_server():
		var sender := multiplayer.get_remote_sender_id()
		_accept(sender, action, index, revision, sequence, seen_serial, seen_point)
		_ack.rpc_id(sender, sequence)


@rpc("authority", "call_remote", "reliable", 0)
func _ack(sequence: int) -> void:
	if sequence == _request_sequence:
		_pending_until = 0


## Ownership revisions reject late grab/drop packets. A rejected request changes no physics.
func _accept(id: int, action: String, index: int, revision: int, sequence: int, seen_serial: int = -1, seen_point: Vector3 = Vector3.INF) -> void:
	if not RoomNetwork.players.has(id) or sequence <= int(_sequences.get(id, 0)):
		return
	_sequences[id] = sequence
	if index < 0 or index >= bodies.size() or revisions[index] != revision:
		return
	var toy := bodies[index]
	if action in ["drop", "throw"]:
		if owners[index] == id:
			_release(index)
			if action == "throw":
				toy.toss(-_view_basis(id).z)
			_publish(true)
		return
	if action not in ["grab", "push"] or held_by(id) >= 0 or owners[index] != 0 or not _reachable(id, index, seen_serial, seen_point, action == "grab"):
		return
	if action == "grab":
		owners[index] = id
		revisions[index] += 1
		_epochs[id] = RoomNetwork.players[id].epoch
		_ignore_holder(index, id)
		toy.grab(_hold_target(id))
	else:
		toy.interact(-_view_basis(id).z)
	_publish(true)


func _eye(id: int) -> Vector3:
	return RoomNetwork.players[id].position + Vector3(0, 1.65, 0)


func _view_basis(id: int) -> Basis:
	var record: Dictionary = RoomNetwork.players[id]
	return Basis(Vector3.UP, record.yaw) * Basis(Vector3.RIGHT, record.pitch)


## A recent authoritative snapshot can validate a grab that was in range when F was pressed.
## Current reach stays tightly bounded; old packets, teleports, walls and ownership still win.
func _reachable(id: int, index: int, seen_serial: int, seen_point: Vector3, allow_history: bool) -> bool:
	var eye := _eye(id)
	var point := bodies[index].global_position
	if not _visible(eye, point):
		return false
	if eye.distance_to(point) <= REACH:
		return true
	if not allow_history or not seen_point.is_finite() or eye.distance_to(point) > REACH + 0.35 or eye.distance_to(seen_point) > REACH + 0.1 or not _visible(eye, seen_point):
		return false
	for sample in _history:
		if sample.serial != seen_serial or Time.get_ticks_msec() - int(sample.time) > HISTORY_MS or sample.epochs.get(id, -1) != RoomNetwork.players[id].epoch:
			continue
		var closest := Geometry3D.get_closest_point_to_segment(seen_point, sample.previous[index], sample.points[index])
		return seen_point.distance_to(closest) <= 0.24 and seen_point.distance_to(sample.eyes[id]) <= REACH + 0.1
	return false


## A swept sphere keeps the carrying point inside walls. The body still uses real contacts.
func _hold_target(id: int) -> Vector3:
	var eye := _eye(id)
	var view := _view_basis(id)
	var motion := -view.z * 0.9
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.20
	query.shape = sphere
	query.transform.origin = eye
	query.motion = motion
	query.collision_mask = 1
	var fraction := bodies[0].get_world_3d().direct_space_state.cast_motion(query)
	return eye + motion * fraction[0]


func _release(index: int) -> void:
	_release_immunity[index] = owners[index]
	_epochs.erase(owners[index])
	owners[index] = 0
	revisions[index] += 1
	bodies[index].drop()


## Departure, seating, standing and reset all release before the holder can teleport the toy.
func _roster_changed() -> void:
	if not RoomNetwork.active or not multiplayer.is_server() or bodies.is_empty():
		return
	for index in range(owners.size()):
		var id := owners[index]
		if id != 0 and (not RoomNetwork.players.has(id) or RoomNetwork.players[id].epoch != _epochs.get(id, -1)):
			_release(index)
	_update_proxies(0.0)
	_publish(true)


func _physics_process(delta: float) -> void:
	if not RoomNetwork.active or bodies.is_empty():
		return
	if not multiplayer.is_server():
		_apply_targets(false, delta)
		return
	_update_proxies(delta)
	_update_immunity()
	for index in range(bodies.size()):
		var toy := bodies[index]
		if owners[index] != 0:
			toy.hold_target = _hold_target(owners[index])
		# A recovery guard for edited room geometry, never a return-to-start spring.
		if not toy.global_position.is_finite() or absf(toy.position.x) > 7.5 or absf(toy.position.z) > 7.0 or toy.position.y < -0.5 or toy.position.y > 5.5:
			if owners[index] != 0:
				_release(index)
			toy.global_transform = _homes[index]
			toy.linear_velocity = Vector3.ZERO
	_elapsed += delta
	if _elapsed >= 1.0 / 30.0:
		_elapsed = 0.0
		_publish(false)


## Only the host creates toy-only player capsules. Their layer never blocks walking/cameras.
func _update_proxies(delta: float) -> void:
	if not is_instance_valid(_proxy_root):
		return
	for id in _proxies.keys():
		if not RoomNetwork.players.has(id):
			_proxies[id].queue_free()
			_proxies.erase(id)
			_proxy_epochs.erase(id)
	for id in RoomNetwork.players:
		var record: Dictionary = RoomNetwork.players[id]
		if not _proxies.has(id):
			var proxy := AnimatableBody3D.new()
			proxy.name = "ToyCollider_%d" % id
			proxy.set_meta("toy_player_id", id)
			proxy.collision_layer = PLAYER_LAYER
			proxy.collision_mask = TOY_LAYER
			proxy.sync_to_physics = false
			var shape := CollisionShape3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.radius = 0.32
			capsule.height = 1.75
			shape.shape = capsule
			proxy.add_child(shape)
			_proxy_root.add_child(proxy)
			_proxies[id] = proxy
		var body: AnimatableBody3D = _proxies[id]
		var target: Vector3 = record.position + Vector3(0, 0.875, 0)
		var teleported: bool = _proxy_epochs.get(id, -1) != record.epoch
		if teleported:
			# Avoid turning a reset/seat teleport into a high-speed physics hit.
			body.collision_layer = 0
			body.global_position = target
		else:
			body.collision_layer = PLAYER_LAYER
			body.global_position = target if delta == 0.0 else body.global_position.lerp(target, 1.0 - exp(-30.0 * delta))
		_proxy_epochs[id] = record.epoch


func _ignore_holder(index: int, id: int) -> void:
	if _release_immunity.has(index):
		var previous: int = _release_immunity[index]
		if _proxies.has(previous):
			bodies[index].remove_collision_exception_with(_proxies[previous])
		_release_immunity.erase(index)
	if _proxies.has(id):
		bodies[index].add_collision_exception_with(_proxies[id])


## A released toy can leave the thrower's hands before colliding with them again.
func _update_immunity() -> void:
	for index in _release_immunity.keys():
		var id: int = _release_immunity[index]
		if not _proxies.has(id):
			_release_immunity.erase(index)
			continue
		var center: Vector3 = _proxies[id].global_position
		var point := bodies[index].global_position
		var nearest := Vector3(center.x, clampf(point.y, center.y - 0.555, center.y + 0.555), center.z)
		if point.distance_to(nearest) > 0.55:
			bodies[index].remove_collision_exception_with(_proxies[id])
			_release_immunity.erase(index)


func _snapshot() -> Array:
	var result: Array = []
	for index in range(bodies.size()):
		var toy := bodies[index]
		result.append({"transform": toy.global_transform, "owner": owners[index], "revision": revisions[index], "warm": toy.warm_light, "interactions": toy.interaction_count})
	return result


func _publish(reliable: bool) -> void:
	_serial += 1
	_remember()
	var snapshot := _snapshot()
	for id in RoomNetwork.players:
		if id != 1:
			if reliable:
				_commit.rpc_id(id, _serial, snapshot)
			else:
				_motion.rpc_id(id, _serial, snapshot)
	changed.emit()


## Short host history covers input/network delay without trusting client timestamps or poses.
func _remember() -> void:
	var points: Array[Vector3] = []
	var eyes: Dictionary = {}
	var epochs: Dictionary = {}
	for toy in bodies:
		points.append(toy.global_position)
	for id in RoomNetwork.players:
		eyes[id] = _eye(id)
		epochs[id] = RoomNetwork.players[id].epoch
	var previous: Array = points if _history.is_empty() else _history.back().points
	_history.append({"serial": _serial, "time": Time.get_ticks_msec(), "points": points, "previous": previous, "eyes": eyes, "epochs": epochs})
	while not _history.is_empty() and Time.get_ticks_msec() - int(_history[0].time) > HISTORY_MS:
		_history.pop_front()


@rpc("any_peer", "call_remote", "reliable", 0)
func _sync_request() -> void:
	if RoomNetwork.active and multiplayer.is_server() and not bodies.is_empty() and RoomNetwork.players.has(multiplayer.get_remote_sender_id()):
		_serial += 1
		_remember()
		_commit.rpc_id(multiplayer.get_remote_sender_id(), _serial, _snapshot())


@rpc("authority", "call_remote", "reliable", 0)
func _commit(serial: int, snapshot: Array) -> void:
	_receive(serial, snapshot)


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _motion(serial: int, snapshot: Array) -> void:
	_receive(serial, snapshot)


func _receive(serial: int, snapshot: Array) -> void:
	if not RoomNetwork.active or serial <= _last_serial or snapshot.size() != 3:
		return
	var first := _targets.is_empty()
	_last_serial = serial
	_targets = snapshot
	owners.clear()
	revisions.clear()
	for record in snapshot:
		owners.append(record.owner)
		revisions.append(record.revision)
	_apply_targets(first)
	changed.emit()


## Guests interpolate host poses, including held objects. No competing local simulation.
func _apply_targets(immediate: bool, delta: float = 0.0) -> void:
	if _targets.size() != bodies.size():
		return
	for index in range(bodies.size()):
		var toy := bodies[index]
		var record: Dictionary = _targets[index]
		toy.global_transform = record.transform if immediate else toy.global_transform.interpolate_with(record.transform, 1.0 - exp(-50.0 * delta))
		toy.held = record.owner != 0
		toy.interaction_count = record.interactions
		if toy.warm_light != record.warm:
			toy.warm_light = record.warm
			toy._update_light()
