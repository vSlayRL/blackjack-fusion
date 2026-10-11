class_name RoomExplorer
extends CharacterBody3D
## First-person room controls, suspended while using the table or rule console.

@export var walk_speed: float = 3.2
@export var sprint_speed: float = 5.2
@export var jump_speed: float = 4.6
@export var rise_gravity: float = 9.0
@export var glide_gravity: float = 3.0
@export var fall_gravity: float = 12.0
@export var mouse_sensitivity: float = 0.0025

signal view_reset

@onready var camera: Camera3D = $Camera3D

var _home_position: Vector3
var _home_yaw: float
var _home_pitch: float
var controls_enabled: bool = true
var _jump_requested: bool = false


## Remember the initial view; leave the cursor free until the player clicks.
func _ready() -> void:
	_home_position = position
	_home_yaw = rotation.y
	_home_pitch = camera.rotation.x


## Capture on click, release on Escape, and clamp vertical mouse look.
func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * mouse_sensitivity, deg_to_rad(-75.0), deg_to_rad(75.0))
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R:
		reset_view()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_jump_requested = true
		get_viewport().set_input_as_handled()


## Move on the floor with collision; only accept walking input while looking around.
func _physics_process(delta: float) -> void:
	var moving := controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _jump_requested and moving and is_on_floor():
		velocity.y = jump_speed
	_jump_requested = false
	if not is_on_floor():
		# A brief gentle apex gives a spacey glide; the stronger descent keeps it room-sized.
		var gravity := glide_gravity if absf(velocity.y) < 0.65 else (rise_gravity if velocity.y > 0.0 else fall_gravity)
		velocity.y -= gravity * delta
	var direction := Vector3.ZERO
	if moving:
		var sideways := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		var forward := float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
		direction = (basis * Vector3(sideways, 0.0, forward)).normalized()
	var speed := sprint_speed if moving and Input.is_physical_key_pressed(KEY_SHIFT) else walk_speed
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	move_and_slide()
	# Walking into a toy transfers a gentle push without affecting gameplay state.
	if controls_enabled:
		for index in range(get_slide_collision_count()):
			var collision := get_slide_collision(index)
			var toy := collision.get_collider() as LoungeProp
			if toy != null:
				toy.sleeping = false
				toy.apply_central_force(-collision.get_normal() * 3.0)
	# This is a recovery guard for future geometry edits, not an alternate movement mode.
	if position.y < -5.0:
		reset_view()


## Return to the entry viewpoint without retaining momentum from walking.
func reset_view() -> void:
	view_reset.emit()
	_jump_requested = false
	position = _home_position
	rotation.y = _home_yaw
	camera.rotation.x = _home_pitch
	velocity = Vector3.ZERO


## Suspend walking/look while UI is open, releasing the cursor for buttons and cards.
func set_controls_enabled(enabled: bool) -> void:
	controls_enabled = enabled
	_jump_requested = false
	velocity.x = 0.0
	velocity.z = 0.0
	if not enabled:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Release the mouse when the window loses focus so it cannot trap the cursor.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Restore ordinary mouse input when this preview scene is closed.
func _exit_tree() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
