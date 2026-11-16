class_name StopCheck
extends Check
## A stop line: the car must come to a complete stop inside the approach zone, for at least
## [member min_stop_time], before it enters the line zone. Only traffic moving along this node's
## forward axis (-Z) is checked, so the line applies to one direction.

## Where the car must stop: the stretch of road just before the line.
@export var approach_zone: TriggerZone
## Entering this zone counts as crossing the line; it starts at the line's far edge.
@export var line_zone: TriggerZone
@export var fault: FaultDef
## Seconds the car must stay stopped.
@export var min_stop_time := 0.5

var _stopped_for := 0.0
var _satisfied := false
var _judged := false


func _on_bound() -> void:
	approach_zone.vehicle_entered.connect(_on_approach_entered)
	line_zone.vehicle_entered.connect(_on_line_entered)


func _physics_process(delta: float) -> void:
	if not is_live() or _satisfied or not approach_zone.contains(probe()):
		return
	if probe().is_stopped():
		_stopped_for += delta
		if _stopped_for >= min_stop_time:
			_satisfied = true
	else:
		_stopped_for = 0.0


func _on_approach_entered(p: VehicleProbe) -> void:
	if p == probe() and _travels_forward(p):
		_stopped_for = 0.0
		_satisfied = false
		_judged = false


func _on_line_entered(p: VehicleProbe) -> void:
	if p != probe() or _judged or not is_live() or not _travels_forward(p):
		return
	_judged = true
	if not _satisfied:
		report(fault, p.global_position)


func _travels_forward(p: VehicleProbe) -> bool:
	var line_forward := -global_basis.z
	line_forward.y = 0.0
	return p.forward().dot(line_forward.normalized()) > 0.0
