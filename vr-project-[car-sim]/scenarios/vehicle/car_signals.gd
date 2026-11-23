class_name CarSignals
extends RefCounted
## The player's car's signals for one step, as on a real car's bus: what its sensors measured
## ([CarSensors]) and what its control units made of it ([AbsModule], [TransmissionUnit],
## [BodyController]). The control units and everything the driver sees, hears from the
## instruments, or feels through the aids read the car only through this record; only the plant
## (the body, its contacts, [CarDynamics]' wheel solve) reads the physics itself.
##
## Wheels are in [CarDynamics]' order: front left, front right, rear left, rear right.

## The wheel speed sensors: each wheel's tread speed, m/s, forward positive.
var wheel_speed := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## The output shaft's speed, as tread speed of the driven wheels, m/s.
var shaft_speed := 0.0
## The crank sensor, revolutions per minute.
var rpm := 0.0
## The yaw-rate gyro, rad/s, left positive.
var yaw_rate := 0.0
## The accelerometer: the specific force (acceleration less gravity) along the car (forward
## positive), across it (left positive), m/s², and up through it, so 9.81 at rest and 0 falling.
var accel := Vector2.ZERO
var accel_up := 0.0
## The steering angle sensor: the front wheels' angle, radians, left positive.
var steer_angle := 0.0
## The throttle position sensor, 0 to 1.
var throttle_position := 0.0
## The brake pedal's switch and how far it is pressed (0 to 1), and the handbrake's switch.
var brake_switch := false
var brake_pedal := 0.0
var handbrake_switch := false
## The reverse switch on the gearbox: closed in reverse gear.
var reverse_switch := false
## The gearbox's gear (1 and up, -1 reverse, 0 neutral or park), its lever ([enum Gearbox.Selector])
## and its letter as the cluster shows it.
var gear := 0
var selector := 0
var gear_letter := "P"
## Whether a change is under way, whether the last change asked for went through, and whether it
## was refused at the lever's end.
var shifting := false
var shifted := false
var shift_refused := false
## The engine's state ([enum CarDynamics.EngineState]), and whether it stalled or the starter was
## refused this step.
var engine_state := 0
var stalled := false
var start_refused := false

## The ABS module's estimates: the car's speed over the road from its four wheels, m/s, and each
## wheel's slip against it (as [method TyreModel.slip_ratio]); and the rear axle's slip angle,
## radians, from the gyro and the accelerometer.
var vehicle_speed := 0.0
var wheel_slip := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var rear_slip := 0.0
## Whether ABS, traction control and stability control acted this step.
var abs_active := false
var tcs_active := false
var esc_active := false
## What the ABS module asks of the brakes and the engine for the next step: each wheel's brake as a
## share of the driver's, torque added to each by stability control (Nm), and the engine's share of
## the driver's throttle.
var brake_scale := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
var brake_extra := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var throttle_scale := 1.0
## The transmission control unit's hold: the automatic keeps its gear while the driven wheels flare.
var gear_hold := false
## The body controller's lamps.
var brake_light := false
var reverse_light := false
