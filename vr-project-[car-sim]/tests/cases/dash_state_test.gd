extends TestCase
## The cluster's warning lights and small gauges ([DashState]), stepped by hand: dark with the key
## off, the bulb check while the engine turns over, the lights going out in turn once it runs, back
## on after a stall, the stability light flashing while the aid acts, the fuel draining with the
## engine's work, and the coolant warming to its running temperature and cooling when off.

const OFF := CarDynamics.EngineState.OFF
const CRANKING := CarDynamics.EngineState.CRANKING
const RUNNING := CarDynamics.EngineState.RUNNING


func run() -> void:
	_test_lights()
	_test_stability()
	_test_fuel_and_coolant()


func _steps(dash: DashState, seconds: float, engine: int, rpm := 900.0, throttle := 0.0,
		aid := false) -> void:
	for i in int(seconds / DT):
		dash.step(DT, engine, rpm, throttle, false, aid)


func _lit(dash: DashState) -> Array:
	return [dash.engine_light, dash.oil_light, dash.battery_light, dash.abs_light]


func _test_lights() -> void:
	var dash := DashState.new()
	_steps(dash, 1.0, OFF)
	expect(_lit(dash) == [false, false, false, false], "with the key off every light is dark")
	_steps(dash, 0.5, CRANKING)
	expect(_lit(dash) == [true, true, true, true], "turning over, the bulb check lights them all")
	_steps(dash, 0.2, RUNNING)
	expect(not dash.oil_light and not dash.battery_light and dash.engine_light and dash.abs_light,
		"running, oil and battery go out at once, engine and ABS still testing")
	_steps(dash, DashState.ENGINE_CHECK, RUNNING)
	expect(_lit(dash) == [false, false, false, false], "after their self-test, all are out")
	dash.step(DT, OFF, 0.0, 0.0, true, false)
	_steps(dash, 1.0, OFF)
	expect(_lit(dash) == [true, true, true, true] and dash.key_on(),
		"stalled with the key on, they light again")
	_steps(dash, 0.5, CRANKING)
	_steps(dash, 3.0, RUNNING)
	_steps(dash, 1.0, OFF)
	expect(_lit(dash) == [false, false, false, false] and not dash.key_on(),
		"switched off from running, the key is off and all is dark")


func _test_stability() -> void:
	var dash := DashState.new()
	_steps(dash, 3.0, RUNNING)
	var on := 0
	var off := 0
	for i in 120:
		dash.step(DT, RUNNING, 3000.0, 0.5, false, true)
		if dash.esc_light:
			on += 1
		else:
			off += 1
	expect(on > 30 and off > 30, "the stability light flashes while the aid acts: %d lit, %d dark"
		% [on, off])
	_steps(dash, 1.0, RUNNING)
	expect(not dash.esc_light, "and goes out once it has stopped")


func _test_fuel_and_coolant() -> void:
	var dash := DashState.new()
	var start := dash.fuel
	_steps(dash, 60.0, RUNNING, 2000.0, 0.3)
	var town := start - dash.fuel
	expect(town > 0.005 and town < 0.02, "a minute of town driving burns about 1%%: %.2f%%"
		% (town * 100.0))
	var before := dash.fuel
	_steps(dash, 60.0, RUNNING, 6000.0, 1.0)
	expect(before - dash.fuel > town * 4.0, "flat out burns far more: %.2f%%"
		% ((before - dash.fuel) * 100.0))
	expect(dash.coolant > 75.0 and dash.coolant <= DashState.RUNNING,
		"two minutes running warm the coolant toward 90 C: %.0f" % dash.coolant)
	_steps(dash, 300.0, RUNNING)
	expect(absf(dash.coolant - DashState.RUNNING) < 1.0, "and it settles there: %.1f"
		% dash.coolant)
	var warm := dash.coolant
	_steps(dash, 60.0, OFF)
	expect(dash.coolant < warm and dash.coolant > 70.0, "off, it cools slowly: %.0f"
		% dash.coolant)
	dash.fuel = DashState.FUEL_LOW + 0.001
	_steps(dash, 0.1, CRANKING)
	_steps(dash, 30.0, RUNNING, 6000.0, 1.0)
	expect(dash.fuel_light, "under %d%% the low-fuel light comes on" % roundi(
		DashState.FUEL_LOW * 100.0))
