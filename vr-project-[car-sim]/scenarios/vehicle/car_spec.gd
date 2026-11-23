class_name CarSpec
extends Resource
## A car's physical make-up: its mass and size, its engine and gearbox, its brakes, its tyres,
## its suspension and its aerodynamics, in SI units. The player's car and every road user drive on
## a spec through the shared vehicle core ([TyreModel], [Powertrain], [Assists], [CarDynamics],
## [PlanarVehicle]).
##
## Worker threads never read the resource: [method packed] flattens it into a
## [PackedFloat64Array] read by the index constants below, so the road users' thinking reads plain
## numbers.

enum Drive { REAR, FRONT, ALL }

## Indices into [method packed].
const MASS := 0
const YAW_INERTIA := 1
const WHEELBASE := 2
const TRACK := 3
const COG_HEIGHT := 4
const FRONT_SHARE := 5
const WHEEL_RADIUS := 6
const WHEEL_INERTIA := 7
const DRIVE := 8
const DIFF_LOCK := 9
const IDLE_RPM := 10
const REDLINE_RPM := 11
const ENGINE_BRAKING := 12
const REVERSE_RATIO := 13
const FINAL_DRIVE := 14
const EFFICIENCY := 15
const SHIFT_TIME := 16
const UP_GENTLE := 17
const UP_FULL := 18
const DOWN_RPM := 19
const BRAKE_TORQUE := 20
const BRAKE_BIAS := 21
const HANDBRAKE_TORQUE := 22
const GRIP := 23
const LOAD_SENSITIVITY := 24
const PEAK_RATIO := 25
const PEAK_ANGLE := 26
const TYRE_SHAPE := 27
const TYRE_B := 28
const SPRING_RATE := 29
const DAMPER_RATE := 30
const TRAVEL := 31
const ANTI_ROLL := 32
const DRAG_AREA := 33
const DOWNFORCE_AREA := 34
const ROLLING := 35
const STEER_LOCK := 36
const LAUNCH_RPM := 37
const GEAR_COUNT := 38
const ENGINE_INERTIA := 39
const CREEP_TORQUE := 40
const CRANK_TIME := 41
const STARTER_RPM := 42
const STALL_RPM := 43
const RELAXATION := 44
## The gears' ratios start here, first gear first, [constant GEAR_COUNT] of them; the torque
## curve follows them, [constant CURVE_SAMPLES] samples [constant CURVE_STEP] rpm apart from 0.
const GEARS := 45
const CURVE_SAMPLES := 9
const CURVE_STEP := 1000.0
## Air density, kg/m³, and gravity, m/s².
const AIR := 1.225
const G := 9.81

@export var title := "Car"
@export_group("Body")
## Kilograms, driver included.
@export var mass := 1250.0
## Kilogram square metres about the vertical axis, about the car's width (pitching) and about its
## length (rolling).
@export var yaw_inertia := 1900.0
@export var pitch_inertia := 1700.0
@export var roll_inertia := 450.0
@export var wheelbase := 2.6
@export var track := 1.55
## The centre of mass's height above the ground, metres.
@export var cog_height := 0.46
## The share of the weight on the front axle, standing still.
@export_range(0.2, 0.8) var front_share := 0.53
@export_group("Wheels")
@export var wheel_radius := 0.31
## Each wheel's spin inertia, with its share of the drivetrain, kg·m².
@export var wheel_inertia := 1.1
@export var drive := Drive.REAR
## A limited slip differential's lock: 0 an open differential, 1 locked.
@export_range(0.0, 1.0) var diff_lock := 0.35
@export_group("Engine and gearbox")
## The engine's torque at full throttle, Nm, every 1000 rpm from 0 to 8000.
@export var torque_curve := PackedFloat64Array(
	[120.0, 150.0, 165.0, 180.0, 190.0, 195.0, 205.0, 200.0, 170.0])
@export var idle_rpm := 850.0
@export var redline_rpm := 7400.0
## The engine's revolutions while the clutch slips to pull away at full throttle.
@export var launch_rpm := 3200.0
## The engine's drag with the throttle shut, Nm at the redline.
@export var engine_braking := 60.0
## The engine's and flywheel's spin inertia, kg·m².
@export var engine_inertia := 0.12
## The torque, Nm, an automatic's converter passes at idle with the throttle shut: the creep.
@export var creep_torque := 12.0
## Seconds the starter must turn the engine over before it catches.
@export var crank_time := 1.0
## The revolutions the starter turns the engine at.
@export var starter_rpm := 250.0
## Below these revolutions a running engine dies.
@export var stall_rpm := 500.0
@export var gear_ratios := PackedFloat64Array([3.63, 2.19, 1.54, 1.21, 1.0, 0.77])
@export var reverse_ratio := 3.44
@export var final_drive := 4.1
@export_range(0.5, 1.0) var efficiency := 0.88
## Seconds a gear change takes, without drive.
@export var shift_time := 0.2
## Revolutions the automatic gearbox changes up at, gently and at full throttle, and down below.
@export var up_gentle := 2500.0
@export var up_full := 6900.0
@export var down_rpm := 1500.0
@export_group("Brakes")
## All four wheels' brake torque at full pedal, Nm.
@export var brake_torque := 4600.0
## The front wheels' share of it.
@export_range(0.3, 0.8) var brake_bias := 0.66
## Each rear wheel's handbrake torque, Nm.
@export var handbrake_torque := 1600.0
@export_group("Tyres")
## The tyres' friction on a surface of friction 1.
@export var grip := 1.0
## How much a tyre's friction falls as its load grows past a quarter of the car's weight.
@export var load_sensitivity := 0.12
## The slip ratio and slip angle (radians) the tyre grips best at.
@export var peak_ratio := 0.1
@export var peak_angle := deg_to_rad(7.0)
## The Pacejka shape factor: how much grip is left past the peak (1.45 keeps three quarters).
@export_range(1.1, 1.9) var tyre_shape := 1.45
## The tyre's relaxation length, metres: how far it rolls for its tread's deflection to build
## toward a new slip. The tread deflects only as its contact patch slides over the road, so a
## wheel turned on a car standing still deflects nothing and pushes nothing.
@export var relaxation := 0.5
@export_group("Suspension")
## Each corner's spring, N/m, and damper, N·s/m.
@export var spring_rate := 38000.0
@export var damper_rate := 3600.0
## How far each wheel travels, metres.
@export var travel := 0.16
## Each axle's anti-roll bar, N/m of difference between its wheels.
@export var anti_roll := 12000.0
@export_group("Aerodynamics")
## Drag coefficient times the frontal area, m².
@export var drag_area := 0.72
## Downforce coefficient times the area, m².
@export var downforce_area := 0.1
## Rolling resistance coefficient.
@export var rolling := 0.012
@export_group("Steering")
## The front wheels' turn at full lock, radians.
@export var steer_lock := deg_to_rad(34.0)


## The spec as plain numbers, for the vehicle core and worker threads.
func packed() -> PackedFloat64Array:
	var p := PackedFloat64Array()
	p.resize(GEARS + gear_ratios.size() + CURVE_SAMPLES)
	p[MASS] = mass
	p[YAW_INERTIA] = yaw_inertia
	p[WHEELBASE] = wheelbase
	p[TRACK] = track
	p[COG_HEIGHT] = cog_height
	p[FRONT_SHARE] = front_share
	p[WHEEL_RADIUS] = wheel_radius
	p[WHEEL_INERTIA] = wheel_inertia
	p[DRIVE] = drive
	p[DIFF_LOCK] = diff_lock
	p[IDLE_RPM] = idle_rpm
	p[REDLINE_RPM] = redline_rpm
	p[ENGINE_BRAKING] = engine_braking
	p[REVERSE_RATIO] = reverse_ratio
	p[FINAL_DRIVE] = final_drive
	p[EFFICIENCY] = efficiency
	p[SHIFT_TIME] = shift_time
	p[UP_GENTLE] = up_gentle
	p[UP_FULL] = up_full
	p[DOWN_RPM] = down_rpm
	p[BRAKE_TORQUE] = brake_torque
	p[BRAKE_BIAS] = brake_bias
	p[HANDBRAKE_TORQUE] = handbrake_torque
	p[GRIP] = grip
	p[LOAD_SENSITIVITY] = load_sensitivity
	p[PEAK_RATIO] = peak_ratio
	p[PEAK_ANGLE] = peak_angle
	p[TYRE_SHAPE] = tyre_shape
	# The magic formula's stiffness that puts its peak at a normalised slip of 1.
	p[TYRE_B] = tan(PI / (2.0 * tyre_shape))
	p[SPRING_RATE] = spring_rate
	p[DAMPER_RATE] = damper_rate
	p[TRAVEL] = travel
	p[ANTI_ROLL] = anti_roll
	p[DRAG_AREA] = drag_area
	p[DOWNFORCE_AREA] = downforce_area
	p[ROLLING] = rolling
	p[STEER_LOCK] = steer_lock
	p[LAUNCH_RPM] = launch_rpm
	p[GEAR_COUNT] = gear_ratios.size()
	p[ENGINE_INERTIA] = engine_inertia
	p[CREEP_TORQUE] = creep_torque
	p[CRANK_TIME] = crank_time
	p[STARTER_RPM] = starter_rpm
	p[STALL_RPM] = stall_rpm
	p[RELAXATION] = relaxation
	for i in gear_ratios.size():
		p[GEARS + i] = gear_ratios[i]
	var curve := GEARS + gear_ratios.size()
	for i in CURVE_SAMPLES:
		p[curve + i] = torque_curve[i] if i < torque_curve.size() else 0.0
	return p


## The distance from the centre of mass to the front axle, and to the rear, metres.
static func to_front(spec: PackedFloat64Array) -> float:
	return spec[WHEELBASE] * (1.0 - spec[FRONT_SHARE])


static func to_rear(spec: PackedFloat64Array) -> float:
	return spec[WHEELBASE] * spec[FRONT_SHARE]
