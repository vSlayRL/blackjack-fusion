class_name NetworkProp
extends LoungeProp
## Multiplayer tuning is separate so Solo keeps its existing toy feel and controls.

const MAX_SPEED: float = 8.0
const MAX_SPIN: float = 28.0


func _ready() -> void:
	super._ready()
	linear_damp = 0.012
	angular_damp = 0.015
	can_sleep = false


## Use solver state directly; repeatedly writing cached Node velocities can erase impulses.
func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if held:
		state.linear_velocity = ((hold_target - state.transform.origin) * 18.0).limit_length(MAX_SPEED)
		state.angular_velocity *= exp(-5.0 * state.step)
	else:
		state.linear_velocity = state.linear_velocity.limit_length(MAX_SPEED)
	state.angular_velocity = state.angular_velocity.limit_length(MAX_SPIN)


func interact(direction: Vector3 = Vector3.FORWARD) -> void:
	if held:
		return
	interaction_count += 1
	if kind == Kind.LIGHT:
		warm_light = not warm_light
		_update_light()
	sleeping = false
	apply_central_impulse(direction.normalized() * 0.5)
	_spin()


## Dropping keeps carrying/flick momentum. Clicking adds a deliberate forward throw.
func drop() -> void:
	held = false
	can_sleep = false
	sleeping = false


func toss(direction: Vector3) -> void:
	drop()
	linear_velocity = (linear_velocity + direction.normalized() * 6.0).limit_length(MAX_SPEED)
	_spin()


func _spin() -> void:
	var twist := Vector3(0.018, 0.026, 0.014) if kind == Kind.DIE else Vector3(0.008, 0.035, 0.01)
	apply_torque_impulse(twist)
