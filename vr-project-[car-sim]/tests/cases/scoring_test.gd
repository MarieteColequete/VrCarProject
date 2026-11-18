extends TestCase
## Scoring: the default policy's tiers and limits.

const POLICY := preload("res://scenarios/data/default_policy.tres")


func run() -> void:
	_test_scoring()


func _faults(ids: Array) -> Array[FaultRecord]:
	var list: Array[FaultRecord] = []
	for id in ids:
		list.append(FaultRecord.new(load(FAULTS % id), 0.0, Vector3.ZERO))
	return list


func _test_scoring() -> void:
	var minors := []
	for i in 9:
		minors.append("lane_drift")
	expect(POLICY.evaluate(_faults([])).passed, "no faults pass")
	expect(POLICY.evaluate(_faults(minors)).passed, "nine minor faults pass")
	expect(not POLICY.evaluate(_faults(minors + ["lane_drift"])).passed, "ten minor faults fail")
	expect(POLICY.evaluate(_faults(["off_route"])).passed, "one serious fault passes")
	var two_serious := POLICY.evaluate(_faults(["off_route", "speeding_serious"]))
	expect(not two_serious.passed and two_serious.failing_tier == &"serious",
		"two serious faults fail on the serious tier")
	var critical := POLICY.evaluate(_faults(["stop_not_made"]))
	expect(not critical.passed and critical.failing_tier == &"critical",
		"one critical fault fails on the critical tier")
	var unknown := FaultDef.new()
	unknown.id = &"test_unknown"
	unknown.tier = &"no_such_tier"
	var with_unknown: Array[FaultRecord] = [FaultRecord.new(unknown, 0.0, Vector3.ZERO)]
	expect(not POLICY.evaluate(with_unknown).passed, "a fault of an unknown tier fails")
