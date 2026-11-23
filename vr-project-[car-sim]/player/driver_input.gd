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
const HEADLIGHTS := &"toggle_headlights"
## The gear lever, a notch at a time: the automatic's D, N, R from top to bottom, the manual's
## gears. On a gamepad, shift_down held [constant PARK_HOLD] seconds is the park button: a gesture
## on whatever button shift_down is bound to, the one place a car reads a device
## ([method is_pad_shift_down]), as a pad has no button left for park of its own.
const SHIFT_UP := &"shift_up"
const SHIFT_DOWN := &"shift_down"
## The automatic's park button.
const PARK := &"park"
## Seconds a gamepad's shift_down is held to park, a tap still moving the lever.
const PARK_HOLD := 0.5
## The key: held to turn the engine over until it catches, pressed to switch it off.
const IGNITION := &"ignition"

## Every action a car reads, for checks that the bindings exist.
const CAR_ACTIONS: Array[StringName] = [
	THROTTLE, BRAKE, STEER_LEFT, STEER_RIGHT, HANDBRAKE, INDICATOR_LEFT, INDICATOR_RIGHT,
	HEADLIGHTS, SHIFT_UP, SHIFT_DOWN, PARK, IGNITION]


## Accelerator, 0 to 1.
static func throttle() -> float:
	return Input.get_action_strength(THROTTLE)


## Brake, 0 to 1.
static func brake() -> float:
	return Input.get_action_strength(BRAKE)


## Steering, -1 (full right) to 1 (full left), matching a positive rotation about Y.
static func steer() -> float:
	return Input.get_axis(STEER_RIGHT, STEER_LEFT)


static func handbrake() -> bool:
	return Input.is_action_pressed(HANDBRAKE)


## Whether the key is held in the start position.
static func ignition() -> bool:
	return Input.is_action_pressed(IGNITION)


## Whether an input event switches the headlights on or off.
static func headlights_pressed(event: InputEvent) -> bool:
	return event.is_action_pressed(HEADLIGHTS)


## The indicator an input event switches, as a [enum VehicleProbe.Indicator]; OFF when it is not
## an indicator press.
static func indicator_pressed(event: InputEvent) -> VehicleProbe.Indicator:
	if event.is_action_pressed(INDICATOR_LEFT):
		return VehicleProbe.Indicator.LEFT
	if event.is_action_pressed(INDICATOR_RIGHT):
		return VehicleProbe.Indicator.RIGHT
	return VehicleProbe.Indicator.OFF


## Whether [param event] presses the park button.
static func park_pressed(event: InputEvent) -> bool:
	return event.is_action_pressed(PARK)


## Whether [param event] is the gamepad's shift_down, which parks when held
## ([constant PARK_HOLD]) and so moves the lever only when let go sooner.
static func is_pad_shift_down(event: InputEvent) -> bool:
	return event is InputEventJoypadButton and event.is_action(SHIFT_DOWN)


## The gear change [param event] asks for: +1 up, -1 down, 0 none.
static func shift_pressed(event: InputEvent) -> int:
	if event.is_action_pressed(SHIFT_UP):
		return 1
	if event.is_action_pressed(SHIFT_DOWN):
		return -1
	return 0
