class_name TrafficLight
extends Node3D
## A traffic light, as authored and as drawn: red, red and amber, green, amber, red. In
## [constant Mode.CYCLE] it loops through the phases on their timers from [member initial]. In
## [constant Mode.ON_APPROACH] it holds [member initial] until the car enters [member trigger],
## waits [member trigger_delay], turns amber, and then runs the phases once until it is green
## again, where it holds; scenarios use this to put a change at a chosen distance. The phases run
## in [LightLogic]; the node draws a pole and three lamps, lit by the light view through
## [method show_state]. A [TrafficLightCheck] at the stop line judges the car.

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

var _lamps: Array[StandardMaterial3D] = []
var _shown := -1


func _ready() -> void:
	if draw_lamps:
		_build()
	show_state(initial)


## Whether [param light_state] stops traffic: red, or red and amber.
static func is_red_state(light_state: int) -> bool:
	return light_state == Light.RED or light_state == Light.RED_AMBER


## Lights the lamps of [param light_state].
func show_state(light_state: int) -> void:
	if light_state == _shown:
		return
	_shown = light_state
	_show()


func _show() -> void:
	if _lamps.is_empty():
		return
	var lit := [
		_shown == Light.RED or _shown == Light.RED_AMBER,
		_shown == Light.AMBER or _shown == Light.RED_AMBER,
		_shown == Light.GREEN]
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
