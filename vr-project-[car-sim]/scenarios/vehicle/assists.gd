class_name Assists
extends RefCounted
## The driving aids, as in the racing games and in road cars: anti-lock brakes (ABS), traction
## control (TCS), stability control (ESC), and steering help for keys and sticks (a lock that
## shrinks with speed to what the tyres can use, and counter-steer that catches a slide). Three
## presets: [code]exam[/code], every aid on and forgiving, the default in exam attempts;
## [code]sport[/code], ABS and a late traction control only; [code]sim[/code], ABS only, as a
## modern road car. A preset is a [PackedFloat64Array] read by the index constants. Pure and
## allocation free.

## Indices into a preset: each aid's strength, 0 off to 1 full.
const ABS := 0
const TCS := 1
const ESC := 2
const STEER_HELP := 3
const COUNTER_STEER := 4
const SIZE := 5
const PRESETS := ["exam", "sport", "sim"]
## The project setting that picks the preset outside exam attempts.
const SETTING := "car/assists"


static func preset(title: String) -> PackedFloat64Array:
	match title:
		"sim":
			return PackedFloat64Array([1.0, 0.0, 0.0, 0.0, 0.0])
		"sport":
			return PackedFloat64Array([1.0, 0.5, 0.0, 0.6, 0.4])
	return PackedFloat64Array([1.0, 1.0, 1.0, 1.0, 1.0])


## The preset the project settings pick, [code]exam[/code] by default.
static func from_settings() -> PackedFloat64Array:
	return preset(str(ProjectSettings.get_setting(SETTING, "exam")))


## A wheel's brake torque with ABS: eased off while the wheel's slip ratio [param ratio] shows it
## locking under braking.
static func brake(aids: PackedFloat64Array, spec: PackedFloat64Array, torque: float,
		ratio: float) -> float:
	if aids[ABS] <= 0.0 or torque <= 0.0:
		return torque
	var limit := -spec[CarSpec.PEAK_RATIO] * 1.2
	if ratio < limit:
		return torque * lerpf(1.0, 0.35, aids[ABS])
	return torque


## The throttle with traction control: cut while the driven wheels' slip ratio
## [param ratio] runs past the peak; a weaker control lets more slip through.
static func throttle(aids: PackedFloat64Array, spec: PackedFloat64Array, input: float,
		ratio: float) -> float:
	if aids[TCS] <= 0.0:
		return input
	var allowed := spec[CarSpec.PEAK_RATIO] * lerpf(3.0, 1.2, aids[TCS])
	var over := (absf(ratio) - allowed) / allowed
	return input * clampf(1.0 - over * 2.0, 0.15, 1.0) if over > 0.0 else input


## The yaw rate a driver means with the front wheels at [param angle] radians at [param speed]
## m/s on a surface of friction [param mu]: the bicycle model's, kept within what the tyres hold.
static func target_yaw(spec: PackedFloat64Array, speed: float, angle: float, mu: float) -> float:
	var wanted := speed * tan(angle) / spec[CarSpec.WHEELBASE]
	if absf(speed) < 1.0:
		return wanted
	var most := 0.85 * mu * spec[CarSpec.GRIP] * CarSpec.G / absf(speed)
	return clampf(wanted, -most, most)


## Stability control's correction: how far, rad/s, the car yaws past what the driver means, left
## positive; 0 within a margin, or with ESC off, or slowly.
static func yaw_error(aids: PackedFloat64Array, spec: PackedFloat64Array, speed: float,
		angle: float, yaw_rate: float, mu: float) -> float:
	if aids[ESC] <= 0.0 or speed < 5.0:
		return 0.0
	var error := yaw_rate - target_yaw(spec, speed, angle, mu)
	var margin := 0.08
	if absf(error) < margin:
		return 0.0
	return (error - signf(error) * margin) * aids[ESC]


## The front wheels' lock for keys and sticks at [param speed]: the spec's lock slowly, shrinking
## with steering help toward the turn the tyres can hold at speed, plus their peak slip angle.
static func steer_lock(aids: PackedFloat64Array, spec: PackedFloat64Array, speed: float,
		mu: float) -> float:
	var full := spec[CarSpec.STEER_LOCK]
	var v2 := speed * speed
	if v2 < 1.0 or aids[STEER_HELP] <= 0.0:
		return full
	var holds := atan(mu * spec[CarSpec.GRIP] * CarSpec.G * spec[CarSpec.WHEELBASE] / v2) \
		+ spec[CarSpec.PEAK_ANGLE]
	return lerpf(full, minf(full, holds), aids[STEER_HELP])


## Counter-steer that catches a slide: steering, radians, toward where the rear axle slides at
## slip angle [param rear_angle].
static func counter_steer(aids: PackedFloat64Array, spec: PackedFloat64Array,
		rear_angle: float) -> float:
	if aids[COUNTER_STEER] <= 0.0:
		return 0.0
	var beyond := absf(rear_angle) - spec[CarSpec.PEAK_ANGLE] * 0.5
	if beyond <= 0.0:
		return 0.0
	return signf(rear_angle) * beyond * aids[COUNTER_STEER]
