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


func required_exports() -> PackedStringArray:
	return ["light", "line_zone"]


func rule_script() -> Script:
	return TrafficLightRule


func rule_params(bake: Bake) -> Dictionary:
	return {light = bake.id_of(light), line = bake.id_of(line_zone), red_fault = red_fault,
		amber_fault = amber_fault, reaction_time = reaction_time, deceleration = deceleration,
		position = global_position, direction = Geo.ground_direction(-global_basis.z)}
