@tool
class_name TrafficLightCheck
extends Check
## A traffic light's stop line, placed at the line with its -Z axis in the direction of traffic.
## Crossing into [member line_zone] while the light shows red (or red and amber) is running a red
## light. Crossing on amber is a fault only when the car could have stopped when the light
## turned amber: the distance from the car's front to the line was at least its stopping
## distance, [code]v * reaction_time + v^2 / (2 * deceleration)[/code].

@export var light: TrafficLight
## Entering this zone counts as crossing the line; it starts just past the line.
@export var line_zone: TriggerZone
@export var red_fault: FaultDef = preload("res://scenarios/data/faults/red_light.tres")
@export var amber_fault: FaultDef = preload("res://scenarios/data/faults/amber_light.tres")
## Seconds before braking starts.
@export var reaction_time := 0.75
## A firm but comfortable deceleration, metres per second squared.
@export var deceleration := 4.0

var _could_stop_on_amber := false


func required_exports() -> PackedStringArray:
	return ["light", "line_zone"]


func _on_bound() -> void:
	if light:
		light.state_changed.connect(_on_light_changed)
	watch(line_zone, _on_line_entered)


## Metres from the car's front to the line along the direction of traffic; negative once past.
func distance_to_line(p: VehicleProbe) -> float:
	var front := p.global_position + p.forward() * p.body_length * 0.5
	return (global_position - front).dot(_traffic_direction())


func stopping_distance(speed: float) -> float:
	return speed * reaction_time + speed * speed / (2.0 * deceleration)


func _on_light_changed(state: TrafficLight.Light) -> void:
	if state == TrafficLight.Light.AMBER and is_live():
		var p := probe()
		var distance := distance_to_line(p)
		_could_stop_on_amber = p.travels_along(_traffic_direction()) and distance > 0.0 \
			and distance >= stopping_distance(maxf(p.speed, 0.0))
	elif state == TrafficLight.Light.GREEN:
		_could_stop_on_amber = false


func _on_line_entered(p: VehicleProbe) -> void:
	if not p.travels_along(_traffic_direction()):
		return
	if light.is_red():
		report_here(red_fault)
	elif light.state == TrafficLight.Light.AMBER and _could_stop_on_amber:
		report_here(amber_fault)


func _traffic_direction() -> Vector3:
	var d := -global_basis.z
	d.y = 0.0
	return d.normalized()
