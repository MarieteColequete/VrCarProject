extends TestCase
## Steering with the hands on the wheel ([WheelGrab]): taking hold near the rim only, turning with
## one hand and with two, letting go and the wheel centring, and the car's wheel frame.

const CAR := preload("res://scenarios/scenes/debug_car.tscn")
const RADIUS := 0.18
const STEP := 1.0 / 60.0


## A point on the rim of a wheel facing +Z at the origin, at [param degrees] anticlockwise from
## 12 o'clock as the driver sees it, [param out] metres off the rim.
func _rim(degrees: float, out := 0.0) -> Vector3:
	var a := deg_to_rad(degrees)
	return Vector3(-sin(a), cos(a), 0.0) * (RADIUS + out)


func run() -> void:
	_test_geometry()
	_test_grab()
	await _test_car()


func _test_geometry() -> void:
	var frame := Transform3D.IDENTITY
	expect(is_zero_approx(WheelGrab.rim_angle(frame, _rim(0.0))), "12 o'clock is nought")
	expect(is_equal_approx(WheelGrab.rim_angle(frame, _rim(90.0)), PI / 2.0),
		"9 o'clock, to the driver's left, is a quarter turn anticlockwise")
	expect(absf(WheelGrab.rim_distance(frame, RADIUS, _rim(30.0, 0.05)) - 0.05) < 0.0001,
		"a hand 5 cm outside the rim is 5 cm from it")
	expect(WheelGrab.on_rim(frame, RADIUS, _rim(45.0, 0.04)).is_equal_approx(_rim(45.0)),
		"a holding hand is drawn on the rim")


func _test_grab() -> void:
	var frame := Transform3D.IDENTITY
	var w := WheelGrab.new()
	var far := Vector3(0.0, 0.0, 0.5)
	w.step(STEP, frame, RADIUS, [_rim(-60.0, 0.2), far], [true, false], 0.0)
	expect(not w.held(), "a grip 20 cm off the rim does not take hold")
	w.step(STEP, frame, RADIUS, [_rim(90.0, 0.03), far], [true, false], 0.0)
	expect(w.held() and is_zero_approx(w.angle), "a grip at the rim takes hold, without a jerk")
	for degrees in range(90, 136, 5):
		w.step(STEP, frame, RADIUS, [_rim(degrees), far], [true, false], 0.0)
	expect(absf(rad_to_deg(w.angle) - 45.0) < 0.5 and w.steer() > 0.0,
		"moving the hand 45° anticlockwise turns the wheel 45° to the left: %.1f°"
		% rad_to_deg(w.angle))
	# Both hands, the right one sliding back while the left holds still: half the turn.
	w.step(STEP, frame, RADIUS, [_rim(135.0), _rim(-90.0)], [true, true], 0.0)
	w.step(STEP, frame, RADIUS, [_rim(135.0), _rim(-110.0)], [true, true], 0.0)
	expect(absf(rad_to_deg(w.angle) - 35.0) < 0.5,
		"with both hands, the wheel turns by their average: %.1f°" % rad_to_deg(w.angle))
	for i in 600:
		w.step(STEP, frame, RADIUS, [_rim(0.0), _rim(0.0)], [true, true], 0.0)
		w.step(STEP, frame, RADIUS, [_rim(170.0), _rim(170.0)], [true, true], 0.0)
	expect(is_equal_approx(w.angle, w.lock), "the wheel stops at its lock")
	for i in 120:
		w.step(STEP, frame, RADIUS, [far, far], [false, false], 0.0)
	expect(not w.held() and is_zero_approx(w.angle), "let go, it centres itself")
	var v := WheelGrab.new()
	v.step(STEP, frame, RADIUS, [_rim(0.0), far], [true, false], -0.5)
	expect(is_equal_approx(v.steer(), -0.5), "taking hold keeps the car's steering")


func _test_car() -> void:
	var car: Node3D = CAR.instantiate()
	root.add_child(car)
	await physics_frame
	var model: PlayerCarModel = car.model
	var frame := car.global_transform * model.steering_frame()
	var eye: Vector3 = car.driver_view.eye().global_position
	expect(frame.basis.z.dot((eye - frame.origin).normalized()) > 0.7,
		"the wheel's frame faces the driver")
	expect(model.steering_radius > 0.14 and model.steering_radius < 0.24,
		"the rim's radius is a steering wheel's: %.2f m" % model.steering_radius)
	expect(car.driver_view.hands.is_empty() and not car.driver_view.wheel.held(),
		"without a headset there are no hands on the wheel")
	car.queue_free()
	await process_frame
