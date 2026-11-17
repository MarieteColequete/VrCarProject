class_name TrafficLight
extends Node3D
## A traffic light running red, red and amber, green, amber, red. In [constant Mode.CYCLE] it
## loops through the phases on their timers from [member initial]. In
## [constant Mode.ON_APPROACH] it holds [member initial] until a vehicle enters
## [member trigger], waits [member trigger_delay], turns amber, and then runs the phases once until
## it is green again, where it holds; scenarios use this to put a change at a chosen distance. It
## draws a pole and three lamps; a [TrafficLightCheck] at the stop line judges the car.

signal state_changed(state: Light)

enum Light { RED, RED_AMBER, GREEN, AMBER }
enum Mode { CYCLE, ON_APPROACH }

@export var mode := Mode.CYCLE
@export var initial := Light.RED
@export var red_time := 6.0
@export var red_amber_time := 1.0
@export var green_time := 6.0
@export var amber_time := 3.0
@export var trigger: TriggerZone
@export var trigger_delay := 0.0
@export var draw_lamps := true

const LAMP_COLOURS := [Color(0.9, 0.1, 0.1), Color(0.95, 0.6, 0.05), Color(0.1, 0.85, 0.3)]

var state := Light.RED
## Seconds spent in the current phase.
var time_in_state := 0.0

var _holding := false
var _triggered_at := -1.0
var _clock := 0.0
var _lamps: Array[StandardMaterial3D] = []


func _ready() -> void:
	state = initial
	_holding = mode == Mode.ON_APPROACH
	if trigger and mode == Mode.ON_APPROACH:
		trigger.vehicle_entered.connect(_on_triggered)
	if draw_lamps:
		_build()
	_show()


func is_red() -> bool:
	return state == Light.RED or state == Light.RED_AMBER


func _on_triggered(_probe: VehicleProbe) -> void:
	if _holding and _triggered_at < 0.0:
		_triggered_at = _clock


func _physics_process(delta: float) -> void:
	_clock += delta
	time_in_state += delta
	if _holding:
		if _triggered_at >= 0.0 and _clock - _triggered_at >= trigger_delay:
			_holding = false
			_change(Light.AMBER)
		return
	if time_in_state >= _duration(state):
		var next := _next(state)
		_change(next)
		if mode == Mode.ON_APPROACH and next == Light.GREEN:
			_holding = true
			_triggered_at = INF


func _change(next: Light) -> void:
	state = next
	time_in_state = 0.0
	_show()
	state_changed.emit(state)


func _duration(light: Light) -> float:
	match light:
		Light.RED:
			return red_time
		Light.RED_AMBER:
			return red_amber_time
		Light.GREEN:
			return green_time
	return amber_time


func _next(light: Light) -> Light:
	match light:
		Light.RED:
			return Light.RED_AMBER
		Light.RED_AMBER:
			return Light.GREEN
		Light.GREEN:
			return Light.AMBER
	return Light.RED


func _show() -> void:
	if _lamps.is_empty():
		return
	var lit := [
		state == Light.RED or state == Light.RED_AMBER,
		state == Light.AMBER or state == Light.RED_AMBER,
		state == Light.GREEN]
	for i in 3:
		_lamps[i].emission_enabled = lit[i]
		_lamps[i].albedo_color = LAMP_COLOURS[i] if lit[i] else LAMP_COLOURS[i].darkened(0.8)


func _build() -> void:
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.06
	pole_mesh.bottom_radius = 0.06
	pole_mesh.height = 2.6
	pole.mesh = pole_mesh
	pole.position.y = 1.3
	add_child(pole, false, INTERNAL_MODE_BACK)
	var housing := MeshInstance3D.new()
	var housing_mesh := BoxMesh.new()
	housing_mesh.size = Vector3(0.35, 1.0, 0.25)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.1, 0.1, 0.1)
	housing_mesh.material = dark
	housing.mesh = housing_mesh
	housing.position.y = 3.1
	add_child(housing, false, INTERNAL_MODE_BACK)
	for i in 3:
		var lamp := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.12
		sphere.height = 0.24
		var material := StandardMaterial3D.new()
		material.emission = LAMP_COLOURS[i]
		material.emission_energy_multiplier = 2.0
		sphere.material = material
		lamp.mesh = sphere
		# Lamps face +Z, towards traffic driving along -Z.
		lamp.position = Vector3(0.0, 3.4 - i * 0.3, 0.14)
		add_child(lamp, false, INTERNAL_MODE_BACK)
		_lamps.append(material)
