extends TestCase
## Setting a mirror with the hand ([MirrorGrab]): taking hold near the glass only, a hand on the
## steering wheel taking none, tilting it right and up as the hand moves, and letting go.

## Two mirrors' glass, facing the driver (+Z): one ahead on the left, one in the middle.
var _glasses: Array = [Transform3D(Basis.IDENTITY, Vector3(-0.9, 1.0, -0.5)),
	Transform3D(Basis.IDENTITY, Vector3(0.0, 1.3, -0.1))]
var _away := Vector3(0.3, 0.8, 0.2)


func run() -> void:
	var grab := MirrorGrab.new()
	var glass: Transform3D = _glasses[0]
	grab.step(_glasses, [glass.origin + Vector3(0.0, 0.0, 0.15), _away], [true, false],
		[false, false])
	expect(not grab.held(), "a grip 15 cm from the glass takes no hold")
	grab.step(_glasses, [glass.origin, _away], [false, false], [false, false])
	var near := glass.origin + Vector3(0.02, 0.0, 0.04)
	var r := grab.step(_glasses, [near, _away], [true, false], [true, false])
	expect(not grab.held(), "a hand on the steering wheel takes no mirror")
	r = grab.step(_glasses, [near, _away], [true, false], [false, false])
	expect(grab.held() and grab.holds[0].mirror == 0 and r.taken == [0],
		"a grip at the glass takes hold of that mirror")
	r = grab.step(_glasses, [near + Vector3(0.04, 0.0, 0.0), _away], [true, false], [false, false])
	var tilts: Array = r.tilts
	expect(tilts[0].x > 0.0 and is_zero_approx(tilts[0].y) and tilts[1] == Vector2.ZERO,
		"moving the hand right tilts the held mirror right: %s" % [tilts])
	expect(is_equal_approx(tilts[0].x, 0.04 * MirrorGrab.PER_METRE), "by how far the hand moved")
	r = grab.step(_glasses, [near + Vector3(0.04, 0.03, 0.0), _away], [true, false], [false, false])
	expect((r.tilts as Array)[0].y > 0.0, "and up tilts it up")
	expect(MirrorGrab.on_glass(glass, near + Vector3(0.0, 0.0, 0.03)).is_equal_approx(
		glass.origin + Vector3(0.02, 0.0, 0.0)), "the holding hand is drawn on the glass")
	grab.step(_glasses, [near, _away], [false, false], [false, false])
	expect(not grab.held(), "letting go of the grip lets go of the mirror")
	var second: Transform3D = _glasses[1]
	grab.step(_glasses, [_away, second.origin], [false, true], [false, false])
	expect(grab.holds[1] != null and grab.holds[1].mirror == 1, "the other hand takes the other mirror")
