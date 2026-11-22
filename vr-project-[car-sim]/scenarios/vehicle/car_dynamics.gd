class_name CarDynamics
extends RefCounted
## A four-wheeled car's drive, brakes and tyres, a step at a time: the [Gearbox] holds the gear
## the driver's lever (or the automatic) picked; the engine is off, turned over by its starter, or
## running, and stalls when a gear is forced on it; running, it turns on its own inertia, coupled to
## the driven wheels through a clutch or torque converter that is open, slipping or locked; its
## torque goes through a limited slip differential to the driven wheels; the brakes, the handbrake
## and the park pawl hold the wheels back; the aids ([Assists]) step in; each wheel's spin follows
## its torques and its tyre's grip, carrying the engine's inertia while locked to it; and each tyre
## ([TyreModel]) pushes on the road. It knows nothing of nodes: whoever drives it measures each
## wheel's load and how its contact patch moves, and applies the forces it gives back
## ([member force]) at the contact patches. The player's car does so on a rigid body; the tests on
## flat ground.
##
## Wheels are in the order front left, front right, rear left, rear right. A wheel's frame has
## along forward and across to the left.

## How the engine meets the driven wheels: apart (park, neutral, a gear change), slipping (pulling
## away, or below idle in gear), or locked to them.
enum Coupling { OPEN, SLIPPING, LOCKED }
## The engine: off, turned over by the starter, or running.
enum EngineState { OFF, CRANKING, RUNNING }

const FL := 0
const FR := 1
const RL := 2
const RR := 3
## Iterations of the solve for each wheel's spin.
const SOLVE_STEPS := 18
## The park pawl's hold on each driven wheel, Nm.
const PAWL_TORQUE := 30000.0
## How fast a held wheel draws back what it has crept, per second.
const HOLD_PULL := 6.0
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
## How far each wheel's contact has crept since the wheel was held still, metres.
var held_drift := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## Each wheel's spin, rad/s, forward positive.
var spin := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## Each wheel's slip ratio and slip angle in the last step.
var ratio := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var angle := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## Each tyre's force in the last step, newtons, (along, across) in the wheel's frame.
var force := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
## Each tyre's work in the last step: 1 at its peak grip; see [method TyreModel.usage].
var usage := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
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
## Whether each aid stepped in during the last step.
var abs_active := false
var tcs_active := false
var esc_active := false
## The key held through a switch-off or a start, ignored until it is let go.
var _key_latched := false
var _key_was := false


func _init(p_spec: PackedFloat64Array, p_aids := Assists.preset("exam"), p_manual := false) -> void:
	spec = p_spec
	aids = p_aids
	gearbox = Gearbox.new(spec, p_manual)
	engine_spin = spec[CarSpec.IDLE_RPM] * TAU / 60.0
	rpm = spec[CarSpec.IDLE_RPM]


## Where wheel [param i]'s contact patch is from the centre of mass, in the car's frame
## (forward is -Z, left is -X), on the ground [param below] metres down.
func wheel_offset(i: int, below := 0.0) -> Vector3:
	var x := spec[CarSpec.TRACK] * 0.5 * (-1.0 if i % 2 == 0 else 1.0)
	var z := -CarSpec.to_front(spec) if i < 2 else CarSpec.to_rear(spec)
	return Vector3(x, -below, z)


## Whether wheel [param i] is driven.
func driven(i: int) -> bool:
	var layout := int(spec[CarSpec.DRIVE])
	return layout == CarSpec.Drive.ALL or (layout == CarSpec.Drive.REAR) == (i >= 2)


## The driven wheels' tread speed, m/s, forward positive: what the gearbox goes by.
func wheel_speed() -> float:
	var total := 0.0
	var count := 0
	for i in 4:
		if driven(i):
			total += spin[i]
			count += 1
	return total / maxi(count, 1) * spec[CarSpec.WHEEL_RADIUS]


## The load on a corner's spring and damper, newtons: compressed [param compression] metres,
## compressing at [param rate] m/s, with the anti-roll bar pulling it toward the other side of its
## axle, compressed [param other] metres. Never pulls the wheel down.
static func corner_load(p_spec: PackedFloat64Array, compression: float, rate: float,
		other: float) -> float:
	var load := p_spec[CarSpec.SPRING_RATE] * compression + p_spec[CarSpec.DAMPER_RATE] * rate \
		+ p_spec[CarSpec.ANTI_ROLL] * (compression - other)
	return maxf(load, 0.0)


## One step of [param dt] seconds. [param controls]: [code]throttle[/code] and [code]brake[/code]
## 0 to 1, [code]handbrake[/code] 0 to 1, [code]steer[/code] the front wheels' angle in radians
## (left positive), [code]shift[/code] +1 or -1 to move the lever or change gear, and, for tests
## and spawns, [code]select[/code] a [enum Gearbox.Selector] to put the lever at, and
## [code]starter[/code] whether the key is held to start the engine (a fresh press of it switches a
## running engine off). Each wheel's
## [param loads] newtons, its contact patch's speed [param along] and [param across] its own frame
## (m/s), and the surface's friction [param mu]; the car's [param speed] forward (m/s) and
## [param yaw_rate] (rad/s, left positive).
func step(dt: float, controls: Dictionary, loads: PackedFloat64Array, along: PackedFloat64Array,
		across: PackedFloat64Array, mu: PackedFloat64Array, speed: float, yaw_rate: float) -> void:
	var pedal := clampf(float(controls.get("throttle", 0.0)), 0.0, 1.0)
	var brake := clampf(float(controls.get("brake", 0.0)), 0.0, 1.0)
	var handbrake := clampf(float(controls.get("handbrake", 0.0)), 0.0, 1.0)
	var steer := float(controls.get("steer", 0.0))
	var at := wheel_speed()
	var before := gearbox.gear
	if controls.has("select") and int(controls.select) != gearbox.selector:
		gearbox.select(int(controls.select), at)
	var shift := int(controls.get("shift", 0))
	shifted = shift != 0 and gearbox.request(shift, at)
	shift_refused = shift != 0 and not shifted
	gearbox.step(dt, pedal, at)
	stalled = false
	if gearbox.gear != before:
		_engaged(at)
	_ignition(dt, bool(controls.get("starter", false)))
	var grip_mu := (mu[0] + mu[1] + mu[2] + mu[3]) * 0.25

	# Stability control: brakes one wheel to turn the car back to what the driver means, and
	# eases the throttle.
	var error := Assists.yaw_error(aids, spec, speed, steer, yaw_rate, grip_mu)
	esc_active = error != 0.0
	pedal *= clampf(1.0 - absf(error) * 2.0, 0.2, 1.0)

	# Traction control on the driven wheels' slip.
	var drive_slip := 0.0
	var count := 0
	for i in 4:
		if driven(i):
			drive_slip = maxf(drive_slip, ratio[i] * signf(spin[i] if spin[i] != 0.0 else 1.0))
			count += 1
	throttle = Assists.throttle(aids, spec, pedal, drive_slip)
	tcs_active = throttle < pedal - 0.001

	var carried := _couple(dt)
	var drives := _split(carried.x)

	var footbrake := brake * spec[CarSpec.BRAKE_TORQUE]
	var brakes := PackedFloat64Array([
		footbrake * spec[CarSpec.BRAKE_BIAS] * 0.5, footbrake * spec[CarSpec.BRAKE_BIAS] * 0.5,
		footbrake * (1.0 - spec[CarSpec.BRAKE_BIAS]) * 0.5,
		footbrake * (1.0 - spec[CarSpec.BRAKE_BIAS]) * 0.5])
	abs_active = false
	for i in 4:
		var eased := Assists.brake(aids, spec, brakes[i], ratio[i] * signf(along[i]))
		abs_active = abs_active or eased < brakes[i]
		brakes[i] = eased
	if error != 0.0:
		# Too far left: brake the right; the front if the rear slides, else the rear.
		var rear_slides := absf(angle[RL] + angle[RR]) > absf(angle[FL] + angle[FR])
		var right := error > 0.0
		var wheel := (FR if right else FL) if rear_slides else (RR if right else RL)
		brakes[wheel] += minf(absf(error) * 5000.0, 1800.0)
	brakes[RL] += handbrake * spec[CarSpec.HANDBRAKE_TORQUE]
	brakes[RR] += handbrake * spec[CarSpec.HANDBRAKE_TORQUE]
	# The pawl ratchets past its notches while the car rolls, and drops in once it is slow.
	var parked := not gearbox.manual and gearbox.selector == Gearbox.Selector.PARK \
		and absf(at) < PAWL_SPEED
	for i in 4:
		if parked and driven(i):
			brakes[i] += PAWL_TORQUE

	var base := spec[CarSpec.WHEEL_INERTIA]
	for i in 4:
		var inertia := base + (carried.y if driven(i) else 0.0)
		_solve_wheel(i, dt, drives[i], brakes[i], loads[i], along[i], across[i], mu[i], inertia)
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
	rpm = engine_spin * 60.0 / TAU


## Puts the car as it starts: the engine [param running] or off, the lever at [param selector],
## and every wheel rolling at [param speed] m/s, the engine locked to the driven ones in gear.
func place(running: bool, selector: Gearbox.Selector, speed := 0.0) -> void:
	gearbox.select(selector, speed)
	for i in 4:
		spin[i] = speed / spec[CarSpec.WHEEL_RADIUS]
	engine = EngineState.RUNNING if running else EngineState.OFF
	cranked = 0.0
	coupling = Coupling.OPEN
	engine_spin = _idle_spin() if running else 0.0
	if running and gearbox.gear != 0:
		var side := wheel_speed() / spec[CarSpec.WHEEL_RADIUS] * Powertrain.ratio(spec, gearbox.gear)
		if side >= _idle_spin():
			engine_spin = side
			coupling = Coupling.LOCKED
	rpm = engine_spin * 60.0 / TAU


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
			spin[i] = signf(spin[i]) * maxf(absf(spin[i]) - change, 0.0)


func _stall() -> void:
	engine = EngineState.OFF
	stalled = true
	coupling = Coupling.OPEN


## Whether the manual's clutch is let out in gear with the throttle shut, so the wheels drag the
## engine down with them.
func _lugging() -> bool:
	return gearbox.manual and throttle < CATCH


func _driven_count() -> int:
	var count := 0
	for i in 4:
		count += 1 if driven(i) else 0
	return count


## The engine's coupling for this step: its spin, and what it sends to the driven wheels, as
## [code](torque at the wheels altogether in Nm, engine inertia each driven wheel carries)[/code].
func _couple(dt: float) -> Vector2:
	var gearing := Powertrain.ratio(spec, gearbox.gear)
	var wheel_side := wheel_speed() / spec[CarSpec.WHEEL_RADIUS] * gearing
	var idle := _idle_spin()
	var stall := lerpf(spec[CarSpec.IDLE_RPM], spec[CarSpec.LAUNCH_RPM], throttle) * TAU / 60.0
	if engine != EngineState.RUNNING:
		coupling = Coupling.OPEN
		_wind_down(dt)
		return Vector2.ZERO
	if gearbox.gear == 0 or gearbox.shifting > 0.0:
		coupling = Coupling.OPEN
		# Mid-change the automatic cuts the torque, as a gearbox's controller does.
		_rev_freely(dt, throttle if gearbox.gear == 0 else 0.0)
		return Vector2.ZERO
	# It locks once the wheel side catches up with the slipping revolutions, and lets go only
	# below idle, so a locked engine stays locked as the throttle opens.
	var count := _driven_count()
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
	elif wheel_side >= stall * 0.97:
		coupling = Coupling.LOCKED
		_lock(gearing, count)
	else:
		coupling = Coupling.SLIPPING
	if coupling == Coupling.LOCKED:
		if not _lugging():
			engine_spin = maxf(engine_spin, idle * 0.95)
		var torque := _engine_torque(throttle)
		var through := torque * gearing
		through = through * spec[CarSpec.EFFICIENCY] if torque > 0.0 \
			else through / spec[CarSpec.EFFICIENCY]
		var reflected := spec[CarSpec.ENGINE_INERTIA] * gearing * gearing / maxi(count, 1)
		return Vector2(through, reflected)
	# Slipping: the engine runs up toward the slipping revolutions, and the converter (or the
	# clutch, biting with the throttle) passes its torque on; an automatic's converter adds to it
	# while the wheel side lags, and creeps with the throttle shut.
	engine_spin = lerpf(engine_spin, stall, clampf(dt / SLIP_SETTLE, 0.0, 1.0))
	var available := Powertrain.curve(spec, engine_spin * 60.0 / TAU) * throttle
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
	var wheels := count * spec[CarSpec.WHEEL_INERTIA] / (gearing * gearing)
	var engine := spec[CarSpec.ENGINE_INERTIA]
	var shared := (engine * engine_spin + wheels * mean * gearing) / (engine + wheels)
	var change := shared / gearing - mean
	for i in 4:
		if driven(i):
			spin[i] += change
	engine_spin = shared


## The engine on its own for a step with [param open] throttle: the throttle revs it, its drag and
## the idle governor bring it back to idle, and the limiter holds it at the redline.
func _rev_freely(dt: float, open: float) -> void:
	# Just caught, it runs up to idle under the governor rather than jumping there.
	var floor := minf(engine_spin, _idle_spin() * 0.85)
	engine_spin += _engine_torque(open) / spec[CarSpec.ENGINE_INERTIA] * dt
	engine_spin = clampf(engine_spin, floor, spec[CarSpec.REDLINE_RPM] * TAU / 60.0)


## The engine not running for a step: the starter turns it at its revolutions, or else its
## friction stops it.
func _wind_down(dt: float) -> void:
	if engine == EngineState.CRANKING:
		var starter := spec[CarSpec.STARTER_RPM] * TAU / 60.0
		engine_spin = lerpf(engine_spin, starter, clampf(dt / SLIP_SETTLE, 0.0, 1.0))
		return
	var drag := Powertrain.FRICTION + spec[CarSpec.ENGINE_BRAKING] * engine_spin * 60.0 / TAU \
		/ spec[CarSpec.REDLINE_RPM]
	engine_spin = maxf(engine_spin - drag / spec[CarSpec.ENGINE_INERTIA] * dt, 0.0)


## The engine's torque at its spin with [param open] throttle, the idle governor's included.
func _engine_torque(open: float) -> float:
	var at := engine_spin * 60.0 / TAU
	var governor := clampf((spec[CarSpec.IDLE_RPM] - at) / 150.0, 0.0, 1.0) * GOVERNOR_TORQUE
	return Powertrain.engine_torque(spec, at, open) + governor


func _idle_spin() -> float:
	return spec[CarSpec.IDLE_RPM] * TAU / 60.0


func _stall_spin() -> float:
	return spec[CarSpec.STALL_RPM] * TAU / 60.0


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


## Solves wheel [param i]'s spin at the end of the step, implicitly so a stiff tyre stays stable:
## the spin at which the drive [param drive], the brake [param brake] and the tyre's pull balance
## the change of spin of [param inertia], the wheel's own and any engine's locked to it. Then sets the wheel's slip and its tyre's force.
func _solve_wheel(i: int, dt: float, drive: float, brake: float, load: float, ground: float,
		side: float, mu: float, inertia: float) -> void:
	var r := spec[CarSpec.WHEEL_RADIUS]
	var slip_angle := TyreModel.slip_angle(ground, side)
	var w := spin[i]
	var rolling := ground / r
	var reach := (absf(drive) + brake) * dt / inertia + absf(w - rolling) + 5.0
	var lo := minf(w, rolling) - reach
	var hi := maxf(w, rolling) + reach
	if load <= 0.0:
		# In the air: only the drive and brake turn it.
		w += drive * dt / inertia
		w = move_toward(w, 0.0, brake * dt / inertia)
		spin[i] = w
		ratio[i] = 0.0
		angle[i] = slip_angle
		force[i] = Vector2.ZERO
		usage[i] = 0.0
		return
	for k in SOLVE_STEPS:
		var mid := (lo + hi) * 0.5
		if _residual(dt, w, mid, drive, brake, load, ground, slip_angle, mu, inertia) > 0.0:
			hi = mid
		else:
			lo = mid
	var solved := (lo + hi) * 0.5
	# A braked wheel this close to still is held still.
	if absf(solved) < 0.05 and brake > 0.0:
		solved = 0.0
	spin[i] = solved
	ratio[i] = TyreModel.slip_ratio(solved * r, ground)
	angle[i] = slip_angle
	var f := TyreModel.force(spec, ratio[i], slip_angle, load, mu)
	# At walking pace the tyre pushes sideways no harder than stops the slide within the step.
	var most := spec[CarSpec.MASS] * 0.25 * absf(side) / dt
	f.y = clampf(f.y, -most, most)
	if solved == 0.0 and absf(ground) < 1.5:
		# A wheel held still at a crawl grips as static friction: as hard as stops the car's share
		# within the step and draws back what it has crept since it was held, so a slope cannot
		# ease it down a little every step; up to the tyre's grip.
		held_drift[i] += ground * dt
		var top := TyreModel.peak(spec, load, mu)
		f.x = clampf(-spec[CarSpec.MASS] * 0.25 * (ground + held_drift[i] * HOLD_PULL) / dt,
			-top, top)
	else:
		held_drift[i] = 0.0
	force[i] = f
	usage[i] = TyreModel.usage(spec, ratio[i], slip_angle)


## The imbalance on a wheel spinning [param from] at the start of the step and [param to] at its
## end: positive when [param to] is too fast.
func _residual(dt: float, from: float, to: float, drive: float, brake: float, load: float,
		ground: float, slip_angle: float, mu: float, inertia: float) -> float:
	var r := spec[CarSpec.WHEEL_RADIUS]
	var k := TyreModel.slip_ratio(to * r, ground)
	var pull := TyreModel.force(spec, k, slip_angle, load, mu).x
	var held := brake * signf(to)
	return inertia * (to - from) / dt - drive + pull * r + held
