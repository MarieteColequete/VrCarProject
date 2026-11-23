class_name DashState
extends RefCounted
## What the instrument cluster shows beyond the car's motion: its warning lights, the fuel and the
## coolant's temperature. All of it is for show; nothing here takes part in the simulation.
##
## The warning lights behave as a real car's. With the key on and the engine not running (turned
## over by the starter, or stalled) the engine, oil, battery and ABS lights are lit, the bulb check;
## once it runs the oil and battery lights go out at once, the ABS light after
## [constant ABS_CHECK] seconds and the engine light after [constant ENGINE_CHECK]. Switched off,
## the key is off and every light is dark. The stability light flashes while stability or traction
## control acts. The fuel drains with the engine's work, and the coolant warms toward its running
## temperature over a few minutes and cools when the engine is off.

## Seconds the ABS and engine lights stay lit after the engine starts, their self-test.
const ABS_CHECK := 1.5
const ENGINE_CHECK := 2.0
## Seconds the stability light keeps flashing after the aid last acted, and its flashes a second.
const ESC_HOLD := 0.5
const ESC_FLASH_HZ := 2.0
## The fuel's share at the start, and below which the low-fuel light comes on.
const FUEL_START := 0.7
const FUEL_LOW := 0.12
## The tank's share burnt each second at full throttle at [constant FUEL_RPM]: about 1% a minute in
## town (2000 rpm, a light throttle), 7% flat out.
const FUEL_RATE := 0.00123
const FUEL_RPM := 6000.0
## How much of the burn the engine takes with the throttle shut.
const FUEL_IDLE := 0.15
## The coolant's temperatures, degrees Celsius: the air's, and the engine's running one; and the
## seconds it takes to come most of the way up (three of them to warm) and back down.
const AMBIENT := 20.0
const RUNNING := 90.0
const WARM_UP := 60.0
const COOL_DOWN := 600.0

var engine_light := false
var oil_light := false
var battery_light := false
var abs_light := false
var esc_light := false
var fuel_light := false
## The fuel's share of the tank, 0 to 1.
var fuel := FUEL_START
## The coolant's temperature, degrees Celsius.
var coolant := AMBIENT

var _key_on := false
var _running_for := 0.0
var _esc_left := 0.0
var _clock := 0.0


## Steps the dash by [param delta] seconds with the engine in [param engine]
## ([enum CarDynamics.EngineState]) at [param rpm] with [param throttle] (0 to 1); [param stalled]
## when it stalled this step, and [param aid_acting] while stability or traction control acts.
func step(delta: float, engine: int, rpm: float, throttle: float, stalled: bool,
		aid_acting: bool) -> void:
	_clock = fmod(_clock + delta, 1.0)
	var running := engine == CarDynamics.EngineState.RUNNING
	if engine == CarDynamics.EngineState.CRANKING or running or stalled:
		_key_on = true
	elif engine == CarDynamics.EngineState.OFF and not stalled and _running_for > 0.0:
		# Switched off from running, the key turned back: everything dark.
		_key_on = false
	_running_for = _running_for + delta if running else 0.0
	engine_light = _key_on and (not running or _running_for < ENGINE_CHECK)
	abs_light = _key_on and (not running or _running_for < ABS_CHECK)
	oil_light = _key_on and not running
	battery_light = _key_on and not running
	_esc_left = ESC_HOLD if aid_acting else maxf(_esc_left - delta, 0.0)
	esc_light = _key_on and _esc_left > 0.0 and fmod(_clock * ESC_FLASH_HZ, 1.0) < 0.5
	if running:
		var work := FUEL_IDLE + (1.0 - FUEL_IDLE) * clampf(throttle, 0.0, 1.0)
		fuel = maxf(fuel - FUEL_RATE * work * rpm / FUEL_RPM * delta, 0.0)
		coolant = lerpf(coolant, RUNNING, 1.0 - exp(-delta / WARM_UP))
	else:
		coolant = lerpf(coolant, AMBIENT, 1.0 - exp(-delta / COOL_DOWN))
	fuel_light = _key_on and fuel < FUEL_LOW


## Whether the key is on: the engine running, turned over, or stalled and not yet switched off.
func key_on() -> bool:
	return _key_on
