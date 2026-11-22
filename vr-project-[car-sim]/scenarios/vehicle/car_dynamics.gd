class_name CarDynamics
extends RefCounted
## A four-wheeled car's drive, brakes and tyres, a step at a time: the gearbox picks a gear, the
## engine's torque goes through a limited slip differential to the driven wheels, the brakes and
## the handbrake hold the wheels back, the aids ([Assists]) step in, each wheel's spin follows its
## torques and its tyre's grip, and each tyre ([TyreModel]) pushes on the road. It knows nothing
## of nodes: whoever drives it measures each wheel's load and how its contact patch moves, and
## applies the forces it gives back ([member force]) at the contact patches. The player's car
## does so on a rigid body; the tests on flat ground.
##
## Wheels are in the order front left, front right, rear left, rear right. A wheel's frame has
## along forward and across to the left.

const FL := 0
const FR := 1
const RL := 2
const RR := 3
## Iterations of the solve for each wheel's spin.
const SOLVE_STEPS := 18

## The car's [method CarSpec.packed] spec and its [Assists] preset.
var spec: PackedFloat64Array
var aids: PackedFloat64Array
## Whether the driver changes gear (with [code]shift[/code]) instead of the automatic.
var manual := false
## Each wheel's spin, rad/s, forward positive.
var spin := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## Each wheel's slip ratio and slip angle in the last step.
var ratio := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var angle := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## Each tyre's force in the last step, newtons, (along, across) in the wheel's frame.
var force := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
## Each tyre's work in the last step: 1 at its peak grip; see [method TyreModel.usage].
var usage := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var gear := 0
var rpm := 850.0
## The throttle the engine got after the aids, 0 to 1.
var throttle := 0.0
## Seconds left of a gear change.
var shifting := 0.0
## Whether each aid stepped in during the last step.
var abs_active := false
var tcs_active := false
var esc_active := false


func _init(p_spec: PackedFloat64Array, p_aids := Assists.preset("exam")) -> void:
	spec = p_spec
	aids = p_aids
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
## (left positive), [code]reverse[/code] true to drive backward with the throttle, and
## [code]shift[/code] +1 or -1 to change gear in the manual. Each wheel's [param loads] newtons,
## its contact patch's speed [param along] and [param across] its own frame (m/s), and the
## surface's friction [param mu]; the car's [param speed] forward (m/s) and [param yaw_rate]
## (rad/s, left positive).
func step(dt: float, controls: Dictionary, loads: PackedFloat64Array, along: PackedFloat64Array,
		across: PackedFloat64Array, mu: PackedFloat64Array, speed: float, yaw_rate: float) -> void:
	var pedal := clampf(float(controls.get("throttle", 0.0)), 0.0, 1.0)
	var brake := clampf(float(controls.get("brake", 0.0)), 0.0, 1.0)
	var handbrake := clampf(float(controls.get("handbrake", 0.0)), 0.0, 1.0)
	var steer := float(controls.get("steer", 0.0))
	_change_gear(dt, pedal, speed, bool(controls.get("reverse", false)),
		int(controls.get("shift", 0)))
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
	if shifting > 0.0:
		throttle = 0.0

	var mean_spin := 0.0
	for i in 4:
		if driven(i):
			mean_spin += spin[i] / count
	rpm = Powertrain.engine_rpm(spec, mean_spin, gear, throttle)
	var engine := Powertrain.wheel_torque(spec, rpm, throttle, gear) if shifting <= 0.0 else 0.0
	var drives := _split(engine)

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

	for i in 4:
		_solve_wheel(i, dt, drives[i], brakes[i], loads[i], along[i], across[i], mu[i])


## The step's gear: the driver's in the manual, else the automatic's; reverse when asked to drive
## backward, and drive cut while a forward change goes through.
func _change_gear(dt: float, pedal: float, speed: float, reverse: bool, shift: int) -> void:
	shifting = maxf(shifting - dt, 0.0)
	var next := gear
	if reverse:
		next = -1
	elif manual:
		if shift != 0 and shifting <= 0.0:
			next = clampi(gear + shift, -1, Powertrain.gear_count(spec))
		if next == 0 and shift > 0 and gear < 0:
			next = 1
		# Pulling away from neutral, it takes first.
		if next == 0 and shift == 0 and pedal > 0.0:
			next = 1
	elif gear < 0 and speed > -0.5:
		next = 1
	else:
		next = Powertrain.next_gear(spec, gear, speed, pedal)
	if next != gear:
		if gear > 0 and next > 0:
			shifting = spec[CarSpec.SHIFT_TIME]
		gear = next


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
## the change of spin. Then sets the wheel's slip and its tyre's force.
func _solve_wheel(i: int, dt: float, drive: float, brake: float, load: float, ground: float,
		side: float, mu: float) -> void:
	var r := spec[CarSpec.WHEEL_RADIUS]
	var inertia := spec[CarSpec.WHEEL_INERTIA]
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
		if _residual(dt, w, mid, drive, brake, load, ground, slip_angle, mu) > 0.0:
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
	force[i] = f
	usage[i] = TyreModel.usage(spec, ratio[i], slip_angle)


## The imbalance on a wheel spinning [param from] at the start of the step and [param to] at its
## end: positive when [param to] is too fast.
func _residual(dt: float, from: float, to: float, drive: float, brake: float, load: float,
		ground: float, slip_angle: float, mu: float) -> float:
	var r := spec[CarSpec.WHEEL_RADIUS]
	var k := TyreModel.slip_ratio(to * r, ground)
	var pull := TyreModel.force(spec, k, slip_angle, load, mu).x
	var held := brake * signf(to)
	return spec[CarSpec.WHEEL_INERTIA] * (to - from) / dt - drive + pull * r + held
