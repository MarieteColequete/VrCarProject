extends SceneTree
## Headless tests of the scenario framework. Run from the repository root:
##   godot --headless --xr-mode off --fixed-fps 60 --path 'vr-project-[car-sim]' -s res://tests/run_tests.gd
## Runs every [TestCase] in [code]res://tests/cases/[/code] whose file ends in
## [code]_test.gd[/code], in name order, and exits 0 when every test passes, 1 otherwise.
## TESTS_VERBOSE=1 also prints each pass; TESTS_FILTER=<text> runs only the cases whose file
## name contains it. Drives move the car along fixed legs, one step per physics tick, so results
## do not depend on the machine's speed; --fixed-fps 60 makes each frame one tick without
## waiting for the clock, so minutes of simulated driving run in seconds.

const CASES := "res://tests/cases/"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var filter := OS.get_environment("TESTS_FILTER")
	var passed := 0
	var failed := 0
	var files := Array(DirAccess.get_files_at(CASES))
	files.sort()
	for file: String in files:
		if not file.ends_with("_test.gd") or (not filter.is_empty() and not file.contains(filter)):
			continue
		var case: TestCase = load(CASES + file).new()
		case.setup(self)
		var started := Time.get_ticks_msec()
		await case.run()
		passed += case.passed
		failed += case.failed
		if OS.has_environment("TESTS_VERBOSE") or case.failed > 0:
			print("%s: %d passed, %d failed in %.1f s" % [file.get_basename(), case.passed,
				case.failed, (Time.get_ticks_msec() - started) / 1000.0])
	print("\n%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 or passed == 0 else 0)
