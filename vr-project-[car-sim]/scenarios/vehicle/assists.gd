class_name Assists
extends RefCounted
## The driving aids a road car's ABS module runs: anti-lock brakes (ABS), traction control (TCS)
## and stability control (ESC). They act only through the brakes and the engine, as on a road
## car; none of them steers, which is the driver's alone ([Steering]). Three presets:
## [code]exam[/code], every aid on and forgiving, the default in exam attempts; [code]sport[/code],
## ABS and a late traction control only; [code]sim[/code], ABS only. A preset is a
## [PackedFloat64Array] read by the index constants. Pure and allocation free.

## Indices into a preset: each aid's strength, 0 off to 1 full.
const ABS := 0
const TCS := 1
const ESC := 2
const SIZE := 3
const PRESETS := ["exam", "sport", "sim"]
## The project setting that picks the preset outside exam attempts.
const SETTING := "car/assists"


static func preset(title: String) -> PackedFloat64Array:
	match title:
		"sim":
			return PackedFloat64Array([1.0, 0.0, 0.0])
		"sport":
			return PackedFloat64Array([1.0, 0.5, 0.0])
	return PackedFloat64Array([1.0, 1.0, 1.0])


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
