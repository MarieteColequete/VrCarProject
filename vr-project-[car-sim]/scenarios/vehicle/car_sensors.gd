class_name CarSensors
extends RefCounted
## The player's car's sensors: they measure the plant as a real car's hardware does and write it
## into [CarSignals]. Wheel speed sensors read each wheel's own spin, not the body's speed, so a
## locked wheel reads nought and a wheel spinning in the air reads its spin; the accelerometer reads
## specific force, so it feels 1 g up at rest and nothing in free fall; the gyro reads the body's
## turn about its own vertical. Plain functions, for any thread.

## The least brake pedal that closes its switch.
const BRAKE_SWITCH := 0.02


## Measures [param dynamics] (the wheels, the engine, the gearbox), the body's [param motion]
## ([code]{yaw_rate, specific_force}[/code]: rad/s about the car's up, left positive; and the
## acceleration less gravity in the car's frame, [code]Vector3(forward, left, up)[/code] m/s²), and
## the driver's [param controls] ([code]{steer_angle, throttle, brake, handbrake}[/code]) into
## [param signals].
static func measure(signals: CarSignals, dynamics: CarDynamics, motion: Dictionary,
		controls: Dictionary) -> void:
	var r := dynamics.spec[CarSpec.WHEEL_RADIUS]
	for i in 4:
		signals.wheel_speed[i] = dynamics.spin[i] * r
	signals.shaft_speed = dynamics.wheel_speed()
	signals.rpm = dynamics.rpm
	signals.yaw_rate = float(motion.get("yaw_rate", 0.0))
	var force: Vector3 = motion.get("specific_force", Vector3(0.0, 0.0, CarSpec.G))
	signals.accel = Vector2(force.x, force.y)
	signals.accel_up = force.z
	signals.steer_angle = float(controls.get("steer_angle", 0.0))
	signals.throttle_position = clampf(float(controls.get("throttle", 0.0)), 0.0, 1.0)
	signals.brake_pedal = clampf(float(controls.get("brake", 0.0)), 0.0, 1.0)
	signals.brake_switch = signals.brake_pedal > BRAKE_SWITCH
	signals.handbrake_switch = float(controls.get("handbrake", 0.0)) > 0.5
	signals.gear = dynamics.gear
	signals.selector = dynamics.gearbox.selector
	signals.gear_letter = dynamics.gearbox.letter()
	signals.reverse_switch = dynamics.gear == -1
	signals.shifting = dynamics.shifting > 0.0
	signals.engine_state = dynamics.engine
	signals.stalled = dynamics.stalled
	signals.start_refused = dynamics.start_refused
