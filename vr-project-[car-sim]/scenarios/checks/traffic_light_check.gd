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
@export var red_fault: FaultDef
@export var amber_fault: FaultDef
## Seconds before braking starts.
@export var reaction_time := 0.75
## A firm but comfortable deceleration, metres per second squared.
@export var deceleration := 4.0

var _could_stop_on_amber := false


func _on_bound() -> void:
	light.state_changed.connect(_on_light_changed)
	line_zone.vehicle_entered.connect(_on_line_entered)


## Metres from the car's front to the line along the direction of traffic; negative once past.
func distance_to_line(p: VehicleProbe) -> float:
	var front := p.global_position + p.forward() * p.body_length * 0.5
	return (front - global_position).dot(_traffic_direction() * -1.0)


func stopping_distance(speed: float) -> float:
	return speed * reaction_time + speed * speed / (2.0 * deceleration)


func _on_light_changed(state: TrafficLight.Light) -> void:
	if state == TrafficLight.Light.AMBER and is_live():
		var p := probe()
		var distance := distance_to_line(p)
		_could_stop_on_amber = _travels_forward(p) and distance > 0.0 \
			and distance >= stopping_distance(maxf(p.speed, 0.0))
	elif state == TrafficLight.Light.GREEN:
		_could_stop_on_amber = false


func _on_line_entered(p: VehicleProbe) -> void:
	if p != probe() or not is_live() or not _travels_forward(p):
		return
	if light.is_red():
		report(red_fault, p.global_position)
	elif light.state == TrafficLight.Light.AMBER and _could_stop_on_amber:
		report(amber_fault, p.global_position)


func _traffic_direction() -> Vector3:
	var d := -global_basis.z
	d.y = 0.0
	return d.normalized()


func _travels_forward(p: VehicleProbe) -> bool:
	return p.forward().dot(_traffic_direction()) > 0.0
