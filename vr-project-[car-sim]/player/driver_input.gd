class_name DriverInput
extends RefCounted
## The car controls, read from the input actions in project.godot. Keyboard, gamepad, and later a
## wheel are events on the same actions, so a car script reads these helpers and never a device.
## Keys give full values; triggers and sticks give analog values past the action's deadzone.

const THROTTLE := &"throttle"
const BRAKE := &"brake"
const STEER_LEFT := &"steer_left"
const STEER_RIGHT := &"steer_right"
const HANDBRAKE := &"handbrake"
const INDICATOR_LEFT := &"indicator_left"
const INDICATOR_RIGHT := &"indicator_right"

## Every action a car reads, for checks that the bindings exist.
const CAR_ACTIONS: Array[StringName] = [
	THROTTLE, BRAKE, STEER_LEFT, STEER_RIGHT, HANDBRAKE, INDICATOR_LEFT, INDICATOR_RIGHT]


## Accelerator, 0 to 1.
static func throttle() -> float:
	return Input.get_action_strength(THROTTLE)


## Brake, 0 to 1; a car may use it as reverse once stopped.
static func brake() -> float:
	return Input.get_action_strength(BRAKE)


## Steering, -1 (full right) to 1 (full left), matching a positive rotation about Y.
static func steer() -> float:
	return Input.get_axis(STEER_RIGHT, STEER_LEFT)


static func handbrake() -> bool:
	return Input.is_action_pressed(HANDBRAKE)


## The indicator an input event switches, as a [enum VehicleProbe.Indicator]; OFF when it is not
## an indicator press.
static func indicator_pressed(event: InputEvent) -> VehicleProbe.Indicator:
	if event.is_action_pressed(INDICATOR_LEFT):
		return VehicleProbe.Indicator.LEFT
	if event.is_action_pressed(INDICATOR_RIGHT):
		return VehicleProbe.Indicator.RIGHT
	return VehicleProbe.Indicator.OFF
