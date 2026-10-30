extends RoomExplorer
## One locally controlled camera; remote egg players smoothly follow host snapshots.

signal interact_requested
signal seat_requested
signal reset_requested

var peer_id: int = 0
var local_player: bool = false
var seat_index: int = -1
var target_position: Vector3
var target_yaw: float = 0.0
var egg: Node3D


func _ready() -> void:
	super._ready()
	collision_layer = 8 if local_player else 0
	collision_mask = 1 if local_player else 0
	camera.current = local_player
	if local_player:
		camera.make_current()
	controls_enabled = local_player
	egg = preload("res://scenes/multiplayer/egg_avatar.tscn").instantiate()
	add_child(egg)
	egg.visible = not local_player
	_apply_pose_style()
	if local_player:
		get_viewport().size_changed.connect(_update_fov)


## Use the same sprint/jump/collision controller as Solo; seated players can still look around.
func _physics_process(delta: float) -> void:
	if not local_player:
		position = position.lerp(target_position, 1.0 - exp(-15.0 * delta))
		rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-15.0 * delta))
		return
	if seat_index >= 0:
		velocity = Vector3.ZERO
		_jump_requested = false
		return
	super._physics_process(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not local_player or not controls_enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var screen: Vector2 = get_viewport().get_visible_rect().size / 2.0 if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else event.position
		if ToyNetwork.held_by(peer_id) >= 0 or ToyNetwork.pick(camera, screen) >= 0:
			return
	if seat_index >= 0 and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
		# The seated cursor stays available for action buttons after a left click.
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit:
			return
		if event.physical_keycode == KEY_G:
			seat_requested.emit()
			get_viewport().set_input_as_handled()
			return
		# These seated keys belong to table actions, not walking/reset or Escape handling.
		if seat_index >= 0 and event.physical_keycode in [KEY_E, KEY_R, KEY_ESCAPE]:
			return
		if event.physical_keycode == KEY_E:
			interact_requested.emit()
			get_viewport().set_input_as_handled()
			return
		if event.physical_keycode == KEY_R:
			reset_requested.emit()
			get_viewport().set_input_as_handled()
			return
	super._unhandled_input(event)


## Entry recovery also goes to the host so other players never see an unexplained teleport.
func reset_view() -> void:
	if local_player:
		reset_requested.emit()


func update_record(record: Dictionary) -> void:
	var changed := seat_index != int(record.seat)
	seat_index = record.seat
	target_position = record.position
	target_yaw = record.yaw
	if changed:
		_apply_pose_style()
	var label := egg.get_node("NameLabel") as Label3D
	label.text = record.name + (" · HOST" if peer_id == 1 else "")
	label.modulate = record.color
	label.font_size = 32
	label.pixel_size = 0.004
	for node_name in ["AccentBelt", "ChestBadge", "BackpackLight"]:
		var mesh := egg.get_node(node_name) as MeshInstance3D
		if not mesh.has_meta("local_material"):
			mesh.material_override = mesh.material_override.duplicate()
			mesh.set_meta("local_material", true)
		var material := mesh.material_override as StandardMaterial3D
		material.albedo_color = record.color
		material.emission = record.color


func teleport_to(location: Vector3, yaw: float, pitch: float, seat: int) -> void:
	seat_index = seat
	position = location
	rotation.y = yaw
	camera.rotation.x = pitch
	velocity = Vector3.ZERO
	_jump_requested = false
	target_position = location
	target_yaw = yaw
	_apply_pose_style()
	if local_player and seat >= 0:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _apply_pose_style() -> void:
	if egg == null:
		return
	egg.scale = Vector3.ONE if seat_index >= 0 else Vector3(1.1, 1.35, 1.1)
	camera.position.y = 1.65
	_update_fov()


## Keep all four table lanes in view when the window becomes narrow.
func _update_fov() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var widening := maxf(1.0, 1.65 / aspect) if seat_index >= 0 else 1.0
	camera.fov = minf(94.0, rad_to_deg(2.0 * atan(tan(deg_to_rad(70.0) / 2.0) * widening)))


func _exit_tree() -> void:
	if local_player:
		super._exit_tree()
