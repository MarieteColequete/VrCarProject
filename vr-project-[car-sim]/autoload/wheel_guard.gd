extends Node
## Autoload "WheelGuard".
##
## Keeps a steering wheel's axes out of the input actions. The actions bind joypad axes for every
## device, as a gamepad's sticks and triggers; a wheel the platform does not map as a gamepad puts
## its pedals on those same axis numbers, resting fully one way (a Logitech G29's brake and clutch
## rest at 1 on axes 2 and 3, the right stick's right and down), so with no headset the driver's
## view would turn to the bottom right and stay there, and the menus would drift. The wheel's rim
## and pedals are read through [WheelInput] instead, so while a wheel is connected every joypad
## axis an action binds is rebound to each other connected joypad, and put back as it was when the
## wheel goes. The wheel's buttons keep their actions.

## The joypad axis events each action had, by action, before any were rebound.
var _axes := {}


func _ready() -> void:
	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void: apply())
	apply()


## Rebinds the actions' joypad axes for the joypads connected now.
func apply() -> void:
	var wheel := DriverInput.wheel.joypad()
	if wheel < 0 and _axes.is_empty():
		return
	if _axes.is_empty():
		for action in InputMap.get_actions():
			var axes: Array[InputEvent] = []
			for event in InputMap.action_get_events(action):
				if event is InputEventJoypadMotion:
					axes.append(event)
			if not axes.is_empty():
				_axes[action] = axes
	var others := Input.get_connected_joypads().filter(func(id: int) -> bool: return id != wheel)
	for action: StringName in _axes:
		if not InputMap.has_action(action):
			continue
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadMotion:
				InputMap.action_erase_event(action, event)
		for event: InputEventJoypadMotion in _axes[action]:
			for device in devices(event.device, wheel, others):
				var copy := event.duplicate() as InputEventJoypadMotion
				copy.device = device
				InputMap.action_add_event(action, copy)


## The devices an axis bound for [param device] (-1 for all) is bound to while joypad
## [param wheel] is the wheel (-1 for none) and the joypads [param others] are connected.
static func devices(device: int, wheel: int, others: Array) -> Array:
	if wheel < 0:
		return [device]
	if device >= 0:
		return [] if device == wheel else [device]
	return others.duplicate()
