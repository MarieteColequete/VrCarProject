class_name WheelSet
extends RefCounted
## A car's four wheels on their tyres, in [CarDynamics]' order: each wheel's spin, its tread's
## deflection at the road ([method TyreModel.contact]), and its tyre's slip and force in the last
## step. [method solve] finds a wheel's spin at the end of a step from the torques on it and its
## tyre's grip; [method turn] turns the front wheels over their treads as the steering moves them.
## It knows nothing of the engine: [CarDynamics] works out the drive and the brakes and hands them
## over.

## Iterations of the solve for each wheel's spin at most, and the bracket, rad/s, it stops at.
const SOLVE_STEPS := 18
const SOLVE_CLOSE := 0.001

## The car's [method CarSpec.packed] spec.
var spec: PackedFloat64Array
## Each wheel's spin, rad/s, forward positive.
var spin := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## Each tyre's tread deflection at its contact, as a share of its peak's (along, across), in the
## wheel's frame: see [method TyreModel.contact].
var deflect := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
## Each wheel's slip ratio and slip angle in the last step.
var ratio := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var angle := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## Each tyre's force in the last step, newtons, (along, across) in the wheel's frame.
var force := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

## Each wheel's road angle in the last step, radians.
var _angles := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])


func _init(p_spec: PackedFloat64Array) -> void:
	spec = p_spec


## Turns each wheel to its road angle [param angles] (radians, left positive) over its tread.
func turn(angles: PackedFloat64Array) -> void:
	for i in 4:
		_turn_tread(i, angles[i] - _angles[i])
	_angles = angles.duplicate()


## Solves wheel [param i]'s spin at the end of the step, implicitly so a stiff tyre stays stable:
## the spin at which the drive [param drive], the brakes [param brake] and the rolling resistance
## (both against its turning, as friction) and the tread's pull ([method TyreModel.contact]) balance
## the change of spin of [param inertia], the wheel's own and any engine's locked to it. Then sets
## the tread's deflection, the tyre's force and, for whoever listens, its slip.
func solve(i: int, dt: float, drive: float, brake: float, load: float, ground: float,
		side: float, mu: float, inertia: float) -> void:
	var r := spec[CarSpec.WHEEL_RADIUS]
	var w := spin[i]
	angle[i] = TyreModel.slip_angle(ground, side)
	if load <= 0.0:
		# In the air: only the drive and brake turn it, and the tread springs back.
		w += drive * dt / inertia
		w = move_toward(w, 0.0, brake * dt / inertia)
		spin[i] = w
		deflect[i] = Vector2.ZERO
		ratio[i] = 0.0
		force[i] = Vector2.ZERO
		return
	brake += spec[CarSpec.ROLLING] * load * r
	var rolling := ground / r
	var reach := (absf(drive) + brake) * dt / inertia + absf(w - rolling) + 5.0
	var lo := minf(w, rolling) - reach
	var hi := maxf(w, rolling) + reach
	var road := TyreModel.prepare(spec, deflect[i], ground, side, load, mu, dt)
	for k in SOLVE_STEPS:
		var mid := (lo + hi) * 0.5
		var turning := _torque(road, dt, w, mid, drive, inertia)
		if turning + brake * signf(mid) > 0.0:
			hi = mid
		else:
			lo = mid
		if hi - lo < SOLVE_CLOSE:
			break
	var solved := (lo + hi) * 0.5
	# Friction holds a wheel this close to still while it can.
	if absf(solved) < 0.05 and absf(_torque(road, dt, w, 0.0, drive, inertia)) <= brake:
		solved = 0.0
	var touch := TyreModel.touch(road, solved * r)
	spin[i] = solved
	deflect[i] = Vector2(touch.z, touch.w)
	force[i] = Vector2(touch.x, touch.y)
	ratio[i] = TyreModel.slip_ratio(solved * r, ground)


## Turns wheel [param i] by [param by] radians, left positive, over its tread: the tread's
## deflection stays where it lies on the road, so in the wheel's frame it turns the other way. A
## wheel turned on a still car deflects nothing new.
func _turn_tread(i: int, by: float) -> void:
	if by == 0.0 or deflect[i] == Vector2.ZERO:
		return
	var scale := TyreModel.tread_scale(spec)
	var px := scale.x
	var py := scale.y
	# Where the tread's surface lies on the road from the wheel, metres: a tread driven ahead of
	# the road (a positive deflection along) has its surface pushed back.
	var lying := Vector2(-deflect[i].x * px, deflect[i].y * py).rotated(-by)
	deflect[i] = Vector2(-lying.x / px, lying.y / py)


## The torque left over on a wheel spinning [param from] at the start of the step and [param to]
## at its end, brakes aside, its tyre on [param road] ([method TyreModel.prepare]): positive when
## [param to] is too fast.
func _torque(road: PackedFloat64Array, dt: float, from: float, to: float, drive: float,
		inertia: float) -> float:
	var r := spec[CarSpec.WHEEL_RADIUS]
	return inertia * (to - from) / dt - drive + TyreModel.touch(road, to * r).x * r
