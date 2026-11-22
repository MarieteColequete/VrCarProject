extends TestCase
## The hill start scenario on the hill road: a stop halfway up a 12% climb, then on over the
## crossroads to the plateau, judged on the stop line and on rolling back after the stop.

const HILL_START := preload("res://scenarios/scenes/hill_start/hill_start.tscn")
const HILL_ROAD := preload("res://maps/hill_road/hill_road.tscn")
## Where the car stops on the climb, inside the approach to the stop line.
const STOP_AT := 32.0

var _terrain: Terrain
var _map: Node


func run() -> void:
	_map = HILL_ROAD.instantiate()
	root.add_child(_map)
	await process_frame
	_terrain = Terrain.of(_map)
	_test_climb()
	await _test_physics_climb()
	await _test_drives()
	_map.queue_free()
	await process_frame


func _test_climb() -> void:
	var foot := _on_road(55.0).y
	var line := _on_road(30.0).y
	var top := _on_road(-40.0).y
	expect(top - foot > 4.5, "the road climbs onto the plateau: %.1f m" % (top - foot))
	var grade := (_on_road(25.0).y - _on_road(35.0).y) / 10.0
	expect(grade > 0.09 and grade <= 0.125, "the stop line is on the steep part: %.1f %%"
		% (grade * 100.0))
	expect(line > foot and line < top, "halfway up")


func _test_physics_climb() -> void:
	var runner := spawn_runner(HILL_START)
	var car: RigidBody3D = runner.car
	await frames(30)
	var foot := car.global_position.y
	car.held_controls = {select = "D", throttle = 0.5}
	await frames(480)
	var risen := car.global_position.y - foot
	expect(risen > 2.0 and car.grounded.count(1) == 4,
		"the car's own physics drives it up the generated road and terrain: %.1f m up, on %d wheels"
		% [risen, car.grounded.count(1)])
	runner.queue_free()
	await process_frame


func _test_drives() -> void:
	var r := await drive([
		{to = _on_road(STOP_AT), speed = 8.0}, {wait = 1.0},
		{to = _on_road(-40.0), speed = 8.0}], HILL_START)
	expect_clean(r, "stopping on the climb and pulling away without rolling back is clean")

	r = await drive([
		{to = _on_road(STOP_AT), speed = 8.0}, {wait = 1.0},
		{to = _on_road(STOP_AT + 1.2), speed = 0.8, crab = true}, {wait = 0.5},
		{to = _on_road(-40.0), speed = 8.0}], HILL_START)
	expect_only(r, &"rolled_back", "rolling back 1.2 m after the stop is one minor fault")

	r = await drive([
		{to = _on_road(STOP_AT), speed = 8.0}, {wait = 1.0},
		{to = _on_road(STOP_AT + 0.3), speed = 0.8, crab = true},
		{to = _on_road(-40.0), speed = 8.0}], HILL_START)
	expect_clean(r, "a 0.3 m roll is within what is allowed")

	r = await drive([{to = _on_road(-40.0), speed = 8.0}], HILL_START)
	expect_eliminated(r, &"stop_not_made", "driving through the stop line is eliminating")


## The right-hand lane's road surface at [param z].
func _on_road(z: float) -> Vector3:
	var point := at(z)
	point.y = _terrain.height_at(point) + Terrain.ROAD_SINK
	return point
