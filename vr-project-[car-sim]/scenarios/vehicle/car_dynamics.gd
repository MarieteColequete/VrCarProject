class_name CarDynamics
extends RefCounted
## A four-wheeled car's drive, brakes and tyres, a step at a time: the [Gearbox] holds the gear
## the driver's lever (or the automatic) picked; the engine is off, turned over by its starter, or
## running, and stalls when a gear is forced on it; running, it turns on its own inertia, coupled to
## the driven wheels through a clutch or torque converter that is open, slipping or locked; its
## torque goes through a limited slip differential to the driven wheels; the brakes, the handbrake
## and the park pawl hold the wheels back, eased where the control units ask ([CarSystems]); each
## wheel's spin follows its torques and its tyre's grip, carrying the engine's inertia while locked
## to it; and each tyre ([TyreModel]) pushes on the road. It knows nothing of nodes: whoever
## drives it measures each wheel's load and how its contact patch moves, and applies the forces it
## gives back ([member force]) at the contact patches. The player's car does so on a rigid body;
## the tests on flat ground.
##
## Wheels are in the order front left, front right, rear left, rear right. A wheel's frame has
## along forward and across to the left.

## How the engine meets the driven wheels: apart (park, neutral, a gear change), slipping (pulling
## away, or below idle in gear), or locked to them.
enum Coupling { OPEN, SLIPPING, LOCKED }
## The share of the converter's slipping revolutions below which a locked automatic slips again;
## it locks at 0.97 of them, so it does not flutter between the two.
const CONVERTER_LET_GO := 0.85
## How far the engine may run ahead of the wheel side for the drive to lock, as a share.
const LOCK_SLIP := 1.03
## The engine: off, turned over by the starter, or running.
enum EngineState { OFF, CRANKING, RUNNING }

const FL := 0
const FR := 1
const RL := 2
const RR := 3
## The park pawl's hold on each driven wheel, Nm.
const PAWL_TORQUE := 30000.0
## The speed, m/s, above which the park pawl ratchets past its notches instead of holding.
const PAWL_SPEED := 0.4
## The idle governor's most torque, Nm, given in full 150 rpm below idle.
const GOVERNOR_TORQUE := 90.0
## Seconds the engine takes to run up to the converter's or clutch's slipping revolutions.
const SLIP_SETTLE := 0.15
## The speed, m/s, above which a gear engaged against the car's motion stalls the engine: a
## walking pace. Below it the converter or the clutch takes it up.
const WRONG_WAY := 1.5
## The throttle below which the manual's clutch is let out: in gear, the engine is dragged down
## with the wheels until it stalls.
const CATCH := 0.05

## The car's [method CarSpec.packed] spec and its [Assists] preset.
var spec: PackedFloat64Array
var aids: PackedFloat64Array
var gearbox: Gearbox
## Whether the driver changes gear by hand instead of the automatic.
var manual: bool:
	get:
		return gearbox.manual
	set(value):
		if value != gearbox.manual:
			gearbox.set_manual(value)
## The engaged gear: 1 and up, -1 reverse, 0 neutral or park.
var gear: int:
	get:
		return gearbox.gear
## Seconds left of a gear change.
var shifting: float:
	get:
		return gearbox.shifting
## The four wheels and their tyres ([WheelSet]): their spin, their treads' deflection, and the
## tyres' slip and force, read through the properties below.
var wheels: WheelSet
## Each wheel's spin, rad/s, forward positive.
var spin: PackedFloat64Array:
	get:
		return wheels.spin
	set(value):
		wheels.spin = value
## Each tyre's tread deflection: see [member WheelSet.deflect].
var deflect: PackedVector2Array:
	get:
		return wheels.deflect
	set(value):
		wheels.deflect = value
## Each wheel's slip ratio and slip angle in the last step.
var ratio: PackedFloat64Array:
	get:
		return wheels.ratio
var angle: PackedFloat64Array:
	get:
		return wheels.angle
## Each tyre's force in the last step, newtons, (along, across) in the wheel's frame.
var force: PackedVector2Array:
	get:
		return wheels.force
## The engine's spin, rad/s, and its revolutions per minute.
var engine_spin := 0.0
var rpm := 850.0
var coupling := Coupling.OPEN
var engine := EngineState.RUNNING
## Seconds the starter has turned the engine over.
var cranked := 0.0
## Whether the engine stalled in the last step, and whether the starter was refused (the drive not
## open: a gear engaged).
var stalled := false
var start_refused := false
## The throttle the engine got after the aids, 0 to 1.
var throttle := 0.0
## Whether the last change asked for moved the lever or the gear ([member shift_refused] when the
## lever was already at its end).
var shifted := false
var shift_refused := false
## The key held through a switch-off or a start, ignored until it is let go.
var _key_latched := false
var _key_was := false


func _init(p_spec: PackedFloat64Array, p_aids := Assists.preset("exam"), p_manual := false) -> void:
	spec = p_spec
	aids = p_aids
	gearbox = Gearbox.new(spec, p_manual)
	wheels = WheelSet.new(spec)
	engine_spin = spec[CarSpec.IDLE_RPM] * CarSpec.RPM
	rpm = spec[CarSpec.IDLE_RPM]


## Whether wheel [param i] is driven.
func driven(i: int) -> bool:
	return CarSpec.driven(spec, i)


## The driven wheels' tread speed, m/s, forward positive: what the gearbox goes by.
func wheel_speed() -> float:
	var total := 0.0
	var count := 0
	for i in 4:
		if driven(i):
			total += spin[i]
			count += 1
	return total / maxi(count, 1) * spec[CarSpec.WHEEL_RADIUS]


## One step of [param dt] seconds. [param controls]: [code]throttle[/code] and [code]brake[/code]
## 0 to 1, [code]handbrake[/code] 0 to 1, [code]angles[/code] each wheel's road angle in radians
## (left positive, [member Steering.angles]), [code]shift[/code] +1 or -1 to move the lever or
## change gear, [code]park[/code] the park button pressed, and, for tests and spawns, [code]select[/code] a [enum Gearbox.Selector] to put the lever at, and
## [code]starter[/code] whether the key is held to start the engine (a fresh press of it switches a
## running engine off). Each wheel's
## [param loads] newtons, its contact patch's speed [param along] and [param across] its own frame
## (m/s), and the surface's friction [param mu]: the plant, as the body under it gives it. The
## aids are not here: the car's control units decide from its sensors ([CarSystems]) and their
## [param units] ask this step's brakes, engine and gear hold ([member CarSignals.brake_scale],
## [member CarSignals.brake_extra], [member CarSignals.throttle_scale],
## [member CarSignals.gear_hold]); without them the car drives with no aids.
func step(dt: float, controls: Dictionary, loads: PackedFloat64Array, along: PackedFloat64Array,
		across: PackedFloat64Array, mu: PackedFloat64Array, units: CarSignals = null) -> void:
	var pedal := clampf(float(controls.get("throttle", 0.0)), 0.0, 1.0)
	var brake := clampf(float(controls.get("brake", 0.0)), 0.0, 1.0)
	var handbrake := clampf(float(controls.get("handbrake", 0.0)), 0.0, 1.0)
	var at := wheel_speed()
	var before := gearbox.gear
	if controls.has("select") and int(controls.select) != gearbox.selector:
		gearbox.select(int(controls.select), at)
	var shift := int(controls.get("shift", 0))
	shifted = shift != 0 and gearbox.request(shift, at)
	shift_refused = shift != 0 and not shifted
	if bool(controls.get("park", false)):
		shifted = gearbox.park(at) or shifted
	gearbox.step(dt, pedal, at, units == null or not units.gear_hold)
	stalled = false
	if gearbox.gear != before:
		_engaged(at)
	_ignition(dt, bool(controls.get("starter", false)))
	throttle = pedal * (units.throttle_scale if units else 1.0)

	var carried := _couple(dt)
	var drives := _split(carried.x)

	var footbrake := brake * spec[CarSpec.BRAKE_TORQUE]
	var brakes := PackedFloat64Array([
		footbrake * spec[CarSpec.BRAKE_BIAS] * 0.5, footbrake * spec[CarSpec.BRAKE_BIAS] * 0.5,
		footbrake * (1.0 - spec[CarSpec.BRAKE_BIAS]) * 0.5,
		footbrake * (1.0 - spec[CarSpec.BRAKE_BIAS]) * 0.5])
	if units:
		for i in 4:
			brakes[i] = brakes[i] * units.brake_scale[i] + units.brake_extra[i]
	brakes[RL] += handbrake * spec[CarSpec.HANDBRAKE_TORQUE]
	brakes[RR] += handbrake * spec[CarSpec.HANDBRAKE_TORQUE]
	# The pawl ratchets past its notches while the car rolls, and drops in once it is slow.
	var parked := not gearbox.manual and gearbox.selector == Gearbox.Selector.PARK \
		and absf(at) < PAWL_SPEED
	for i in 4:
		if parked and driven(i):
			brakes[i] += PAWL_TORQUE

	if controls.has("angles"):
		wheels.turn(controls.angles)

	var base := spec[CarSpec.WHEEL_INERTIA]
	for i in 4:
		var inertia := base + (carried.y if driven(i) else 0.0)
		wheels.solve(i, dt, drives[i], brakes[i], loads[i], along[i], across[i], mu[i], inertia)
	if coupling == Coupling.LOCKED:
		# The engine turns with the wheels it is locked to, never below what it idles down to; a
		# manual's let out clutch drags it down until it stalls.
		var side := wheel_speed() / spec[CarSpec.WHEEL_RADIUS] * Powertrain.ratio(spec, gearbox.gear)
		if _lugging():
			engine_spin = side
			if side < _stall_spin():
				_stall()
		else:
			engine_spin = maxf(side, _idle_spin() * 0.95)
	rpm = engine_spin / CarSpec.RPM


## Puts the car as it starts: the engine [param running] or off, the lever at [param selector],
## and every wheel rolling at [param speed] m/s, the engine locked to the driven ones in gear.
func place(running: bool, selector: Gearbox.Selector, speed := 0.0) -> void:
	gearbox.select(selector, speed)
	for i in 4:
		wheels.spin[i] = speed / spec[CarSpec.WHEEL_RADIUS]
		wheels.deflect[i] = Vector2.ZERO
	engine = EngineState.RUNNING if running else EngineState.OFF
	cranked = 0.0
	coupling = Coupling.OPEN
	engine_spin = _idle_spin() if running else 0.0
	if running and gearbox.gear != 0:
		var side := wheel_speed() / spec[CarSpec.WHEEL_RADIUS] * Powertrain.ratio(spec, gearbox.gear)
		if side >= _idle_spin():
			engine_spin = side
			coupling = Coupling.LOCKED
	rpm = engine_spin / CarSpec.RPM


## The key for a step, held or not: held with the engine off and the drive open (P or N, the
## manual in N) the starter turns it over, and it catches after [constant CarSpec.CRANK_TIME]; let
## go first, it does not. A fresh press switches a running engine off. A key held through a start
## or a switch-off does nothing more until it is let go.
func _ignition(dt: float, key: bool) -> void:
	var pressed := key and not _key_was
	_key_was = key
	start_refused = false
	if not key:
		_key_latched = false
		if engine == EngineState.CRANKING:
			engine = EngineState.OFF
		return
	if _key_latched:
		return
	match engine:
		EngineState.RUNNING:
			if pressed:
				engine = EngineState.OFF
				_key_latched = true
		EngineState.OFF:
			if gearbox.gear == 0:
				engine = EngineState.CRANKING
				cranked = 0.0
			elif pressed:
				start_refused = true
		EngineState.CRANKING:
			if gearbox.gear != 0:
				engine = EngineState.OFF
				return
			cranked += dt
			if cranked >= spec[CarSpec.CRANK_TIME]:
				engine = EngineState.RUNNING
				_key_latched = true


## A gear just engaged with the driven wheels at [param at] m/s: against the car's motion above a
## walking pace, or past the redline, it stalls a running engine with a jolt.
func _engaged(at: float) -> void:
	if engine != EngineState.RUNNING or gearbox.gear == 0:
		return
	var gearing := Powertrain.ratio(spec, gearbox.gear)
	if signf(gearing) * at < -WRONG_WAY:
		_jolt(gearing)
		_stall()
	elif gearbox.gear > 0 and gearbox.rpm_in(gearbox.gear, at) > spec[CarSpec.REDLINE_RPM] * 1.02:
		# The wheels drag the engine over its limit: they meet, then it dies.
		_lock(gearing, _driven_count())
		_stall()


## The stopped engine's momentum taken off the driven wheels through [param gearing]: they jerk
## toward standing still, never past it, and the tyres skid with it.
func _jolt(gearing: float) -> void:
	var count := _driven_count()
	var change := spec[CarSpec.ENGINE_INERTIA] * engine_spin * absf(gearing) \
		/ (count * spec[CarSpec.WHEEL_INERTIA])
	for i in 4:
		if driven(i):
			wheels.spin[i] = signf(wheels.spin[i]) * maxf(absf(wheels.spin[i]) - change, 0.0)


func _stall() -> void:
	engine = EngineState.OFF
	stalled = true
	coupling = Coupling.OPEN


## Whether the manual's clutch is let out in gear with the throttle shut, so the wheels drag the
## engine down with them.
func _lugging() -> bool:
	return gearbox.manual and throttle < CATCH


func _driven_count() -> int:
	return CarSpec.driven_count(spec)


## The engine's coupling for this step: its spin, and what it sends to the driven wheels, as
## [code](torque at the wheels altogether in Nm, engine inertia each driven wheel carries)[/code].
func _couple(dt: float) -> Vector2:
	var gearing := Powertrain.ratio(spec, gearbox.gear)
	var wheel_side := wheel_speed() / spec[CarSpec.WHEEL_RADIUS] * gearing
	var idle := _idle_spin()
	var stall := lerpf(spec[CarSpec.IDLE_RPM], spec[CarSpec.LAUNCH_RPM], throttle) * CarSpec.RPM
	if engine != EngineState.RUNNING:
		coupling = Coupling.OPEN
		_wind_down(dt)
		return Vector2.ZERO
	if gearbox.gear == 0 or gearbox.shifting > 0.0:
		coupling = Coupling.OPEN
		# Mid-change the automatic cuts the torque, as a gearbox's controller does.
		_rev_freely(dt, throttle if gearbox.gear == 0 else 0.0)
		return Vector2.ZERO
	# It locks once the wheel side catches up with the slipping revolutions. A clutch then lets go
	# only below idle, so a locked engine stays locked as the throttle opens; an automatic's
	# converter is a fluid coupling and slips again whenever the throttle asks for well more
	# revolutions than the wheels turn it at, as a pedal opening from idle does.
	var count := _driven_count()
	if coupling == Coupling.LOCKED and not gearbox.manual and wheel_side < stall * CONVERTER_LET_GO:
		coupling = Coupling.SLIPPING
	if coupling == Coupling.LOCKED:
		if _lugging():
			if wheel_side < _stall_spin():
				_stall()
				_wind_down(dt)
				return Vector2.ZERO
			engine_spin = wheel_side
		elif wheel_side < idle * 0.95:
			coupling = Coupling.SLIPPING
		else:
			engine_spin = wheel_side
	elif wheel_side >= stall * 0.97 and engine_spin <= wheel_side * LOCK_SLIP:
		# The lock-up clutch (or the clutch let out) closes once the two sides nearly agree, so
		# it closes with no jolt.
		coupling = Coupling.LOCKED
		_lock(gearing, count)
	else:
		coupling = Coupling.SLIPPING
	if coupling == Coupling.LOCKED:
		if not _lugging():
			engine_spin = maxf(engine_spin, idle * 0.95)
		var through := Powertrain.through(spec, _engine_torque(throttle), gearing)
		var reflected := spec[CarSpec.ENGINE_INERTIA] * gearing * gearing / maxi(count, 1)
		return Vector2(through, reflected)
	# Slipping: the engine runs up toward the slipping revolutions, and the converter (or the
	# clutch, biting with the throttle) passes its torque on; an automatic's converter adds to it
	# while the wheel side lags, and creeps with the throttle shut.
	engine_spin = lerpf(engine_spin, stall, clampf(dt / SLIP_SETTLE, 0.0, 1.0))
	var available := Powertrain.curve(spec, engine_spin / CarSpec.RPM) * throttle
	var lag := clampf(1.0 - wheel_side / maxf(engine_spin, 1.0), 0.0, 1.0)
	var passed := available
	if not gearbox.manual:
		passed = available * (1.0 + lag) + spec[CarSpec.CREEP_TORQUE] * lag
	return Vector2(passed * gearing * spec[CarSpec.EFFICIENCY], 0.0)


## Locks the engine to the driven wheels through [param gearing], keeping their momentum: the two
## meet at a spin between theirs, weighted by their inertias. Off the ground the light wheels
## take the engine's spin; on the road the tyres then pull the wheels, and the engine with them, to
## the road's speed.
func _lock(gearing: float, count: int) -> void:
	var mean := 0.0
	for i in 4:
		if driven(i):
			mean += spin[i] / count
	var wheel_side := count * spec[CarSpec.WHEEL_INERTIA] / (gearing * gearing)
	var inertia := spec[CarSpec.ENGINE_INERTIA]
	var shared := (inertia * engine_spin + wheel_side * mean * gearing) / (inertia + wheel_side)
	var change := shared / gearing - mean
	for i in 4:
		if driven(i):
			wheels.spin[i] += change
	engine_spin = shared


## The engine on its own for a step with [param open] throttle: the throttle revs it, its drag and
## the idle governor bring it back to idle, and the limiter holds it at the redline.
func _rev_freely(dt: float, open: float) -> void:
	# Just caught, it runs up to idle under the governor rather than jumping there.
	var idle_floor := minf(engine_spin, _idle_spin() * 0.85)
	engine_spin += _engine_torque(open) / spec[CarSpec.ENGINE_INERTIA] * dt
	engine_spin = clampf(engine_spin, idle_floor, spec[CarSpec.REDLINE_RPM] * CarSpec.RPM)


## The engine not running for a step: the starter turns it at its revolutions, or else its
## friction stops it.
func _wind_down(dt: float) -> void:
	if engine == EngineState.CRANKING:
		var starter := spec[CarSpec.STARTER_RPM] * CarSpec.RPM
		engine_spin = lerpf(engine_spin, starter, clampf(dt / SLIP_SETTLE, 0.0, 1.0))
		return
	var drag := Powertrain.FRICTION + spec[CarSpec.ENGINE_BRAKING] * engine_spin / CarSpec.RPM \
		/ spec[CarSpec.REDLINE_RPM]
	engine_spin = maxf(engine_spin - drag / spec[CarSpec.ENGINE_INERTIA] * dt, 0.0)


## The engine's torque at its spin with [param open] throttle, the idle governor's included.
func _engine_torque(open: float) -> float:
	var at := engine_spin / CarSpec.RPM
	var governor := clampf((spec[CarSpec.IDLE_RPM] - at) / 150.0, 0.0, 1.0) * GOVERNOR_TORQUE
	return Powertrain.engine_torque(spec, at, open) + governor


func _idle_spin() -> float:
	return spec[CarSpec.IDLE_RPM] * CarSpec.RPM


func _stall_spin() -> float:
	return spec[CarSpec.STALL_RPM] * CarSpec.RPM


## The engine's [param torque] at the wheels shared between them: half to each driven axle of an
## all-wheel car, and across each axle through the limited slip differential, which sends torque
## from the faster wheel to the slower.
func _split(torque: float) -> PackedFloat64Array:
	var out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var layout := int(spec[CarSpec.DRIVE])
	var lock := spec[CarSpec.DIFF_LOCK]
	var share := torque * (0.5 if layout == CarSpec.Drive.ALL else 1.0)
	for left in [FL, RL]:
		if not driven(left):
			continue
		var limit := lock * (absf(share) * 0.5 + 150.0)
		var bias := clampf(lock * 40.0 * (spin[left] - spin[left + 1]), -limit, limit)
		out[left] = share * 0.5 - bias
		out[left + 1] = share * 0.5 + bias
	return out
