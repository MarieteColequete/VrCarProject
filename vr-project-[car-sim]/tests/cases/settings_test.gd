extends TestCase
## The options as the window applies them ([code]autoload/settings.gd[/code]).


func run() -> void:
	var settings: GDScript = load("res://autoload/settings.gd")
	expect(is_equal_approx(settings.window_scale(1.0, false), 1.0)
		and is_equal_approx(settings.window_scale(0.75, false), 0.75),
		"on a monitor the window draws its 3D at the scale chosen")
	var full: float = settings.window_scale(1.0, true)
	expect(full < 1.0 and full > 0.98,
		"in VR a chosen 1.0 is drawn a hair under it, which Godot draws without failing: %.3f" % full)
	expect(is_equal_approx(settings.window_scale(0.85, true), 0.85),
		"in VR any other scale is drawn as chosen")
