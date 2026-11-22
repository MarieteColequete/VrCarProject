class_name PlanarVehicle
extends RefCounted
## A car on the ground as two axles (the single-track model), for road users: the same spec,
## tyres and engine as the player's car ([CarSpec], [TyreModel], [Powertrain]), without the
## wheels' spin or the suspension. Its driver asks for an acceleration and a steering angle; the
## engine, the brakes and the tyres give what they can, the load moving between the axles as it
## brakes and pulls, and grip shared between turning and braking. Below walking pace it moves as
## its wheels point (the kinematic bicycle), since tyres at a crawl are too stiff to step.
##
## The state is the car's speed forward and to its left (m/s) and its yaw rate (rad/s, left
## positive), returned as a [Vector3] [code](forward, left, yaw)[/code]. The ground may climb or
## fall along the car: its grade (the sine of the slope, positive uphill) pulls the car back by
## gravity's share along it and lightens the axles by the cosine. Pure, allocation free and
## deterministic: road users step it on worker threads.

## Speeds, m/s, between which the kinematic model hands over to the tyres.
const KINEMATIC_BELOW := 2.0
const DYNAMIC_ABOVE := 5.0


## One step of [param dt] seconds from [param state] with the front wheels at [param steer]
## radians, asking for [param wanted] m/s² forward (negative brakes), on friction [param mu], on
## ground of [param grade] along the car. Never drives backward: braking stops it.
static func step(spec: PackedFloat64Array, state: Vector3, steer: float, wanted: float,
		mu: float, dt: float, grade := 0.0) -> Vector3:
	var m := spec[CarSpec.MASS]
	var a := CarSpec.to_front(spec)
	var b := CarSpec.to_rear(spec)
	var l := spec[CarSpec.WHEELBASE]
	var vx := state.x
	var vy := state.y
	var r := state.z
	# Gravity across the ground's normal, and along it, back down the slope.
	var level := sqrt(maxf(1.0 - grade * grade, 0.0))
	var resist := 0.5 * CarSpec.AIR * spec[CarSpec.DRAG_AREA] * vx * absf(vx) \
		+ spec[CarSpec.ROLLING] * m * CarSpec.G * level * signf(vx) + m * CarSpec.G * grade

	# The force asked for along the car, within what the engine gives and the brakes hold.
	var fx := m * wanted + resist
	if fx > 0.0:
		fx = minf(fx, Powertrain.drive_force_max(spec, vx))
	var down := m * CarSpec.G * level + 0.5 * CarSpec.AIR * spec[CarSpec.DOWNFORCE_AREA] * vx * vx
	var front_load := down * b / l - fx * spec[CarSpec.COG_HEIGHT] / l
	var rear_load := down - front_load
	var layout := int(spec[CarSpec.DRIVE])
	var front_share := spec[CarSpec.BRAKE_BIAS] if fx < 0.0 \
		else (0.5 if layout == CarSpec.Drive.ALL else (1.0 if layout == CarSpec.Drive.FRONT else 0.0))
	var fxf := fx * front_share
	var fxr := fx - fxf

	# Each axle's tyres: grip, shared between the pull along and the turn.
	var speed := maxf(absf(vx), 0.5)
	var alpha_f := atan2(vy + a * r, speed) - steer
	var alpha_r := atan2(vy - b * r, speed)
	var top_f := 2.0 * TyreModel.peak(spec, front_load * 0.5, mu)
	var top_r := 2.0 * TyreModel.peak(spec, rear_load * 0.5, mu)
	fxf = clampf(fxf, -top_f, top_f)
	fxr = clampf(fxr, -top_r, top_r)
	var fyf := _across(spec, alpha_f, top_f, fxf)
	var fyr := _across(spec, alpha_r, top_r, fxr)

	var cos_s := cos(steer)
	var sin_s := sin(steer)
	# Below walking pace the tyres' sideways force is not stepped: the kinematic model turns it.
	var w := clampf((absf(vx) - KINEMATIC_BELOW) / (DYNAMIC_ABOVE - KINEMATIC_BELOW), 0.0, 1.0)
	var along := fxf * cos_s - fyf * sin_s * w + fxr - resist
	var next_vx := vx + (along / m) * dt
	# Nor rolls back down a climb its engine cannot take: it stalls there, held.
	if vx >= 0.0 and next_vx < 0.0 and (fx <= 0.0 or grade > 0.0):
		next_vx = 0.0
	var side := fxf * sin_s + fyf * cos_s + fyr
	var dyn_vy := vy + (side / m - vx * r) * dt
	var dyn_r := r + ((fxf * sin_s + fyf * cos_s) * a - fyr * b) / spec[CarSpec.YAW_INERTIA] * dt

	# Slowly, it goes where its wheels point.
	var slip := atan(b * tan(steer) / l)
	var kin_vy := next_vx * tan(slip)
	var kin_r := next_vx * cos(slip) * tan(steer) / l
	w = clampf((absf(next_vx) - KINEMATIC_BELOW) / (DYNAMIC_ABOVE - KINEMATIC_BELOW), 0.0, 1.0)
	return Vector3(next_vx, lerpf(kin_vy, dyn_vy, w), lerpf(kin_r, dyn_r, w))


## An axle's sideways force at slip angle [param alpha], with grip [param top] newtons and
## [param pull] newtons of it taken along.
static func _across(spec: PackedFloat64Array, alpha: float, top: float, pull: float) -> float:
	if top <= 0.0:
		return 0.0
	var sy := tan(clampf(alpha, -1.5, 1.5)) / tan(spec[CarSpec.PEAK_ANGLE])
	var pure := -top * signf(sy) * TyreModel.magic(absf(sy), spec[CarSpec.TYRE_B],
		spec[CarSpec.TYRE_SHAPE])
	var used := clampf(pull / top, -1.0, 1.0)
	return pure * sqrt(1.0 - used * used)


## The front wheels' angle that follows a path curving [param curvature] (1/m, left positive) at
## [param speed], steady: the geometry's angle, plus what the understeer of the spec's weight
## split takes at speed.
static func steer_for(spec: PackedFloat64Array, curvature: float, speed: float) -> float:
	var l := spec[CarSpec.WHEELBASE]
	var a := CarSpec.to_front(spec)
	var b := CarSpec.to_rear(spec)
	var m := spec[CarSpec.MASS]
	# Cornering stiffness of each axle, N/rad, from the tyre's slope at the origin.
	var slope := spec[CarSpec.TYRE_B] * spec[CarSpec.TYRE_SHAPE] / tan(spec[CarSpec.PEAK_ANGLE])
	var cf := slope * spec[CarSpec.GRIP] * m * CarSpec.G * b / l
	var cr := slope * spec[CarSpec.GRIP] * m * CarSpec.G * a / l
	var understeer := m / l * (b / cf - a / cr)
	return atan(curvature * (l + understeer * speed * speed))


## The fastest speed, m/s, a road user takes a curve of [param curvature] at, turning no harder
## than [param lateral] m/s².
static func curve_speed(curvature: float, lateral: float) -> float:
	var k := absf(curvature)
	return sqrt(lateral / k) if k > 0.0001 else INF
