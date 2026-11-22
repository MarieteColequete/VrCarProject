class_name CarDrivetrain
extends RefCounted
## The player's car's drivetrain and steering, as pure functions of its state: a five speed
## automatic gearbox with the engine's revolutions, the pull each gear gives, and steering that
## turns the car along its wheels (a bicycle model), with less lock as the speed rises so the car
## never turns harder than [constant GRIP] allows. The car's node keeps the state; nothing here
## touches nodes.

## Forward gears' ratios, first to fifth, and the final drive.
const RATIOS: Array[float] = [3.6, 2.1, 1.4, 1.0, 0.8]
const REVERSE_RATIO := 3.4
const FINAL_DRIVE := 4.1
## The wheel radius the revolutions are worked out with, metres.
const WHEEL_RADIUS := 0.3
const IDLE_RPM := 800.0
const REDLINE_RPM := 6800.0
## Revolutions at which the gearbox changes up, at no throttle and at full throttle.
const UP_GENTLE := 2400.0
const UP_FULL := 4000.0
## Revolutions below which it changes down.
const DOWN_RPM := 1300.0
## Seconds a gear change takes, without drive.
const SHIFT_TIME := 0.25
## How much of the car's acceleration each forward gear gives.
const PULL: Array[float] = [1.25, 1.1, 1.0, 0.85, 0.7]
## The front wheels' turn at full lock, radians, and the sideways acceleration the car's turn is
## kept within, metres per second squared.
const LOCK := deg_to_rad(32.0)
const GRIP := 6.0
## How fast the steering moves toward the input, and back to centre, in full locks per second.
const STEER_RATE := 3.0
const RETURN_RATE := 4.0


## The engine's revolutions per minute at [param speed] metres per second in [param gear]
## (1 to 5, or -1 for reverse; 0 is neutral and idles).
static func rpm(speed: float, gear: int) -> float:
	if gear == 0:
		return IDLE_RPM
	var ratio := REVERSE_RATIO if gear < 0 else RATIOS[gear - 1]
	var wheel := absf(speed) / WHEEL_RADIUS
	return clampf(wheel * ratio * FINAL_DRIVE * 60.0 / TAU, IDLE_RPM, REDLINE_RPM)


## The gear to be in after [param gear] at [param speed] with [param throttle] (0 to 1):
## reverse while moving back, first from a stop, up a gear past the change-up revolutions, which
## rise with the throttle, and down below [constant DOWN_RPM].
static func next_gear(gear: int, speed: float, throttle: float) -> int:
	if speed < -0.05:
		return -1
	if gear <= 0:
		return 1
	var now := rpm(speed, gear)
	var up := lerpf(UP_GENTLE, UP_FULL, clampf(throttle, 0.0, 1.0))
	if now > up and gear < RATIOS.size():
		return gear + 1
	if gear > 1 and rpm(speed, gear - 1) < up * 0.9 and now < DOWN_RPM:
		return gear - 1
	return gear


## How much of the car's acceleration [param gear] gives.
static func pull(gear: int) -> float:
	return PULL[clampi(gear, 1, PULL.size()) - 1] if gear > 0 else 1.0


## The front wheels' turn at full lock at [param speed]: [constant LOCK] slowly, less once a full
## turn would push the car sideways harder than [constant GRIP].
static func lock_at(speed: float, wheelbase: float) -> float:
	var v2 := speed * speed
	if v2 < 0.0001:
		return LOCK
	return minf(LOCK, atan(GRIP * wheelbase / v2))


## How fast the car turns, radians per second, at [param speed] with its front wheels turned
## [param wheel_angle] radians (left positive); reversing turns it the other way.
static func yaw_rate(speed: float, wheel_angle: float, wheelbase: float) -> float:
	return speed / wheelbase * tan(wheel_angle)


## The steering [param steer] (-1 full right to 1 full left) eased toward [param input] over
## [param delta] seconds.
static func ease_steer(steer: float, input: float, delta: float) -> float:
	var outward := absf(input) > absf(steer) and input * steer >= 0.0
	var rate := STEER_RATE if outward else RETURN_RATE
	return move_toward(steer, clampf(input, -1.0, 1.0), rate * delta)


## The gear as the cluster shows it: P parked on the handbrake, R, N standing still, or the gear.
static func gear_letter(gear: int, speed: float, handbrake: bool) -> String:
	if handbrake and absf(speed) < 0.1:
		return "P"
	if gear < 0:
		return "R"
	if gear == 0 or absf(speed) < 0.1:
		return "N"
	return str(gear)
