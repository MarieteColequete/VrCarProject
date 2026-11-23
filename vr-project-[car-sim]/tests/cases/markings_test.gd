extends TestCase
## Road markings: paint, the marking index, and the line rule.

const LINES_FIXTURE := preload("res://tests/fixtures/lines_fixture.tscn")


func run() -> void:
	await _test_markings()
	await _test_lines()


func _marking(kind: RoadMarking.Kind, from: Vector3, to: Vector3) -> RoadMarking:
	var marking := RoadMarking.new()
	marking.kind = kind
	marking.curve = Curve3D.new()
	marking.curve.add_point(from)
	marking.curve.add_point(to)
	root.add_child(marking)
	return marking


func _vertex_count(marking: RoadMarking) -> int:
	var mesh := marking.get_child(0, true) as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return 0
	return mesh.mesh.surface_get_array_len(0)


func _test_markings() -> void:
	var solid := _marking(RoadMarking.Kind.SOLID, Vector3(0, 0, 0), Vector3(0, 0, -30))
	var dashed := _marking(RoadMarking.Kind.DASHED, Vector3(5, 0, 0), Vector3(5, 0, -30))
	await process_frame
	expect(_vertex_count(solid) > 0, "a solid line draws paint")
	@warning_ignore("integer_division")
	expect(_vertex_count(dashed) > 0 and _vertex_count(dashed) < _vertex_count(solid) / 2,
		"a dashed line draws a third of a solid one (3 m dash, 6 m gap)")

	var index := MarkingIndex.new()
	index.add(1, solid.kind, solid.half_width(), solid.world_points())
	index.add(2, dashed.kind, dashed.half_width(), dashed.world_points())
	var hits := index.crossings(Vector3(-1, 0, -10), Vector3(1, 0, -10))
	expect(hits.size() == 1 and hits[0].marking == 1 and hits[0].kind == RoadMarking.Kind.SOLID
		and (hits[0].normal as Vector3).is_equal_approx(Vector3.RIGHT),
		"a point moving right across the solid line crosses it once, onto its right")
	expect(index.crossings(Vector3(-1, 0, -10), Vector3(-0.5, 0, -10)).is_empty(),
		"a point short of the line does not cross it")
	expect(index.crossings(Vector3(4, 0, -12), Vector3(6, 0, -12)).size() == 1,
		"a dashed line is crossed in its gaps too")
	expect(index.overlapping(Vector3(0.05, 0, -20)) == PackedInt64Array([1])
		and index.overlapping(Vector3(0.3, 0, -20)).is_empty(),
		"a point within the paint is on the line, one beside it is not")
	solid.free()
	dashed.free()


func _test_lines() -> void:
	var left := VehicleProbe.Indicator.LEFT
	var off := VehicleProbe.Indicator.OFF
	var r := await drive([{to = at(-100), speed = 8.0}], LINES_FIXTURE)
	expect_clean(r, "keeping to the lane is clean")

	r = await drive([
		{indicator = left}, {to = at(-10), speed = 8.0},
		{to = Vector3(-1.75, 0, -25), speed = 8.0}, {indicator = off},
		{to = Vector3(-1.75, 0, -100), speed = 8.0}], LINES_FIXTURE)
	expect_clean(r, "crossing the dashed line while indicating left is clean")

	r = await drive([
		{to = at(-10), speed = 8.0}, {to = Vector3(-1.75, 0, -25), speed = 8.0},
		{to = Vector3(-1.75, 0, -100), speed = 8.0}], LINES_FIXTURE)
	expect_only(r, &"no_indicator_lane_change",
		"crossing the dashed line without indicating is one minor fault")

	r = await drive([
		{indicator = VehicleProbe.Indicator.RIGHT}, {to = at(-10), speed = 8.0},
		{to = Vector3(-1.75, 0, -25), speed = 8.0}, {to = Vector3(-1.75, 0, -100), speed = 8.0}],
		LINES_FIXTURE)
	expect_only(r, &"no_indicator_lane_change", "indicating the wrong way is no indication", &"")

	r = await drive([
		{indicator = left}, {to = at(-50), speed = 8.0},
		{to = Vector3(-1.75, 0, -65), speed = 8.0}, {to = Vector3(-1.75, 0, -100), speed = 8.0}],
		LINES_FIXTURE)
	expect_only(r, &"line_solid_crossed",
		"crossing the solid line is a serious fault even when indicating", &"")

	r = await drive([
		{to = Vector3(0.85, 0, -30), speed = 8.0}, {to = Vector3(0.85, 0, -100), speed = 8.0}],
		LINES_FIXTURE)
	expect_only(r, &"line_straddled", "riding on the centre line is one minor fault")

	r = await drive([
		{to = at(-10), speed = 8.0}, {to = Vector3(3.0, 0, -25), speed = 8.0},
		{to = Vector3(3.0, 0, -100), speed = 8.0}], LINES_FIXTURE)
	expect_only(r, &"kerb_mounted", "crossing the kerb is one serious fault", &"")
