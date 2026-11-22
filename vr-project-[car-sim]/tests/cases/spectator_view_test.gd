extends TestCase
## The instructor's view on the window in VR ([SpectatorView]): the chase view behind and above the
## car, the view from behind the driver's shoulder, both turning with the car's heading only, and
## no spectator without a headset.

const CAR := preload("res://scenarios/scenes/debug_car.tscn")


func run() -> void:
	_test_spots()
	await _test_follow()


func _test_spots() -> void:
	var pose := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(10.0, 0.0, 5.0))
	var chase := SpectatorView.spot(SpectatorView.Mode.CHASE, pose, Vector3.ZERO)
	var ahead := -pose.basis.z
	expect((chase.from - pose.origin).dot(ahead) < -5.0 and chase.from.y > 2.0,
		"the chase view is behind the car and above it")
	expect((chase.at - pose.origin).dot(ahead) > 0.0, "looking ahead of it")
	var tilted := Transform3D(Basis(Vector3.UP, PI / 2.0) * Basis(Vector3.RIGHT, 0.2), pose.origin)
	var steady := SpectatorView.spot(SpectatorView.Mode.CHASE, tilted, Vector3.ZERO)
	expect((steady.from as Vector3).is_equal_approx(chase.from),
		"the car pitching does not move the view")
	var eye := Vector3(9.6, 1.2, 5.3)
	var shoulder := SpectatorView.spot(SpectatorView.Mode.COCKPIT, pose, eye)
	expect((shoulder.from - eye).dot(ahead) < 0.0 and (shoulder.from as Vector3).distance_to(eye)
		< 1.0, "the cockpit view is just behind the driver's eye")


func _test_follow() -> void:
	var car: Node3D = CAR.instantiate()
	root.add_child(car)
	await physics_frame
	expect(car.driver_view.spectator == null and car.driver_view.headset == null,
		"without a headset, there is no spectator")
	var view := SpectatorView.new()
	view.car = car
	view.eye = car.driver_view.eye()
	root.add_child(view)
	await process_frame
	var behind := (view.global_position - car.global_position).dot(-car.global_basis.z)
	expect(behind < -5.0, "the spectator follows the car from behind: %.1f m" % behind)
	view.next_mode()
	await process_frame
	expect(view.mode == SpectatorView.Mode.COCKPIT
		and view.global_position.distance_to(view.eye.global_position) < 1.0,
		"toggling moves it to the driver's shoulder")
	view.next_mode()
	expect(view.mode == SpectatorView.Mode.CHASE, "and back")
	view.queue_free()
	car.queue_free()
	await process_frame
