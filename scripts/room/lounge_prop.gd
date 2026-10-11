class_name LoungeProp
extends RigidBody3D
## Small zero-gravity desk toys; interactions affect room physics only, never Blackjack state.

enum Kind { DIE, TOKEN, LIGHT }

@export var kind: Kind = Kind.DIE
var interaction_count: int = 0
var warm_light: bool = false
var held: bool = false
var hold_target: Vector3
var _material: StandardMaterial3D
var _light: OmniLight3D


## Build native primitive geometry and a generous picking shape for each editable toy.
func _ready() -> void:
	collision_layer = 4
	collision_mask = 5
	gravity_scale = 0.0
	mass = 0.2
	linear_damp = 0.03
	angular_damp = 0.05
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	continuous_cd = true
	var material := PhysicsMaterial.new()
	material.bounce = 0.85
	material.friction = 0.05
	physics_material_override = material
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color("e8c36e") if kind == Kind.TOKEN else Color("afdfef")
	_material.metallic = 0.65 if kind == Kind.TOKEN else 0.15
	_material.roughness = 0.35
	var visual := MeshInstance3D.new()
	var shape := CollisionShape3D.new()
	if kind == Kind.DIE:
		var cube := BoxMesh.new()
		cube.size = Vector3.ONE * 0.22
		visual.mesh = cube
		var box := BoxShape3D.new()
		box.size = cube.size
		shape.shape = box
		_add_die_numbers()
	elif kind == Kind.TOKEN:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.12
		cylinder.bottom_radius = 0.12
		cylinder.height = 0.035
		visual.mesh = cylinder
		var cylinder_shape := CylinderShape3D.new()
		cylinder_shape.radius = 0.12
		cylinder_shape.height = 0.04
		shape.shape = cylinder_shape
		_add_token_mark()
	else:
		var orb := SphereMesh.new()
		orb.radius = 0.12
		orb.height = 0.24
		visual.mesh = orb
		var sphere := SphereShape3D.new()
		sphere.radius = 0.15
		shape.shape = sphere
		_light = OmniLight3D.new()
		_light.omni_range = 1.8
		_light.light_energy = 0.6
		add_child(_light)
		_update_light()
	visual.material_override = _material
	add_child(visual)
	add_child(shape)


## Give every die face a readable number attached to its moving physical body.
func _add_die_numbers() -> void:
	var faces: Array[Vector3] = [Vector3(0, 0, 0.112), Vector3(0.112, 0, 0), Vector3(0, 0.112, 0), Vector3(0, -0.112, 0), Vector3(-0.112, 0, 0), Vector3(0, 0, -0.112)]
	var angles: Array[Vector3] = [Vector3.ZERO, Vector3(0, 90, 0), Vector3(-90, 0, 0), Vector3(90, 0, 0), Vector3(0, -90, 0), Vector3(0, 180, 0)]
	for index in range(6):
		var number := Label3D.new()
		number.text = str(index + 1)
		number.font_size = 48
		number.pixel_size = 0.002
		number.modulate = Color("102831")
		number.outline_size = 0
		number.position = faces[index]
		number.rotation_degrees = angles[index]
		add_child(number)


## Describe the hovered action without exposing implementation details in the room UI.
func interaction_hint() -> String:
	match kind:
		Kind.DIE: return "push the floating die"
		Kind.TOKEN: return "push / spin the token"
	return "push the orb / change its glow"


## An engraved mark makes the token's physical spin visible from either side.
func _add_token_mark() -> void:
	for side in [1.0, -1.0]:
		var mark := Label3D.new()
		mark.text = "BF"
		mark.font_size = 30
		mark.pixel_size = 0.0035
		mark.modulate = Color("102831")
		mark.outline_size = 0
		mark.position.y = 0.019 * side
		mark.rotation_degrees.x = -90.0 * side
		add_child(mark)


## Push away from the player's view and keep drifting; the orb also cycles its glow.
func interact(direction: Vector3 = Vector3.FORWARD) -> void:
	if held:
		return
	interaction_count += 1
	if kind == Kind.LIGHT:
		warm_light = not warm_light
		_update_light()
	sleeping = false
	apply_central_impulse(direction.normalized() * 0.2)
	apply_torque_impulse(Vector3(0.018, 0.024, 0.012) if kind == Kind.DIE else Vector3(0.004, 0.04, 0.004))


## Guide a held body through the physics solver so it still collides with the room.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if held:
		state.linear_velocity = ((hold_target - state.transform.origin) * 12.0).limit_length(6.0)
		state.angular_velocity *= exp(-12.0 * state.step)


## Stop drifting on pickup without changing glow or spending an interaction/rule use.
func grab(target: Vector3) -> void:
	hold_target = target
	held = true
	can_sleep = false
	sleeping = false


## Release with modest remaining momentum, then resume ordinary zero-gravity physics.
func drop() -> void:
	held = false
	can_sleep = true
	linear_velocity = linear_velocity.limit_length(2.0)
	sleeping = false


## Keep the orb surface and nearby illumination in the same selectable color.
func _update_light() -> void:
	var color := Color("ffc876") if warm_light else Color("53e0e8")
	_material.albedo_color = color
	_material.emission_enabled = true
	_material.emission = color
	_material.emission_energy_multiplier = 1.5
	_light.light_color = color
