class_name CarMirrors
extends Node
## The player's car's three mirrors: their glass on the model, set for the driver's seat, at the
## quality the project setting [code]car/mirrors[/code] picks; the mirror switch that
## tilts the picked one with the look controls; the hands that tilt one they hold; the driver's
## tilts kept between sessions; and the drawing, spread over the frames.

## The mirrors, interior first, then left and right door; empty with the setting off.
var mirrors: Array[CarMirror] = []
## The names the mirrors' tilts are saved by, in the order of [member mirrors].
var keys: Array[StringName] = []
## The mirror switch, for setting the mirrors with the controls.
var adjust := MirrorAdjust.new()
## The settings file the driver's mirror tilts are kept in between sessions.
var settings_path := "user://car.cfg"

var _driver_view: DriverView
var _quality := "full"
var _frame := 0
var _held := false


## Puts the glass on [param model]'s mirrors, set for [param driver_view]'s seat, at
## [param quality] ([code]full[/code], [code]low[/code], or [code]off[/code]); returns where each
## mirror is in the car's space, for the gaze checks, whatever the quality.
func mount(model: PlayerCarModel, driver_view: DriverView, quality: String) -> PackedVector3Array:
	_driver_view = driver_view
	_quality = quality
	var points := PackedVector3Array()
	var seat := driver_view.position
	for key: StringName in [&"rear", &"left", &"right"]:
		var spot := model.mirror_spot(key, seat)
		if spot.is_empty():
			continue
		var at: Transform3D = spot.transform
		points.append(at.origin)
		if quality == "off":
			continue
		var width: int = spot.width / 2 if quality == "low" else spot.width
		var mirror := CarMirror.make(String(key).to_pascal_case() + "Mirror", spot.size, width,
			spot.glass)
		mirror.transform = at
		mirror.rest_pivot = at.affine_inverse() * (spot.aim as Transform3D)
		mirror.widen = spot.widen
		mirror.eye = driver_view.eye()
		model.cabin.add_child(mirror)
		mirrors.append(mirror)
		keys.append(key)
	load_tilts()
	return points


## Sets the mirrors as the driver last left them, from [member settings_path].
func load_tilts() -> void:
	var tilts := CarMirror.load_tilts(settings_path)
	for i in mirrors.size():
		mirrors[i].tilt = tilts.get(keys[i], Vector2.ZERO)


## Keeps the mirrors as the driver has set them, in [member settings_path].
func save_tilts() -> void:
	if mirrors.is_empty():
		return
	var tilts := {}
	for i in mirrors.size():
		tilts[keys[i]] = mirrors[i].tilt
	CarMirror.save_tilts(settings_path, tilts)


## Moves the mirror switch on to the next mirror, or to none, lighting the mirror picked and
## giving it the look controls.
func switch() -> void:
	adjust.cycle(mirrors.size())
	_show_picked()


## A step of the mirror switch, standing still or driving: the picked mirror tilts with the
## tilt controls; once the switch lets go, the mirrors are saved as they are.
func step_switch(delta: float) -> void:
	if not adjust.active():
		return
	var tilt := adjust.step(delta, _driver_view.mirror_look())
	if adjust.active():
		mirrors[adjust.picked].nudge(tilt)
	else:
		_show_picked()
		save_tilts()


## The mirrors in the driver's hands: a held mirror tilts as the hand moves across it, and is
## saved once let go.
func step_hands() -> void:
	if mirrors.is_empty():
		return
	var glasses: Array = []
	for mirror in mirrors:
		glasses.append(mirror.global_transform)
	var tilts := _driver_view.grab_mirrors(glasses)
	for i in mini(tilts.size(), mirrors.size()):
		if tilts[i] != Vector2.ZERO:
			mirrors[i].nudge(tilts[i])
	var held := _driver_view.mirror_grab.held()
	if _held and not held:
		save_tilts()
	_held = held


## Draws the mirrors, spread over the frames: at full quality the interior mirror one frame and the
## door mirrors the next, at low quality one mirror a frame.
func draw() -> void:
	if mirrors.is_empty():
		return
	_frame += 1
	if _quality == "low":
		mirrors[_frame % mirrors.size()].render()
	elif _frame % 2 == 0:
		mirrors[0].render()
	else:
		for i in range(1, mirrors.size()):
			mirrors[i].render()


func _show_picked() -> void:
	for i in mirrors.size():
		mirrors[i].selected = i == adjust.picked
	_driver_view.look_locked = adjust.active()
