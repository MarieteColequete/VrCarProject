@tool
class_name StopCheck
extends Check
## A stop line: the car must come to a complete stop inside the approach zone, for at least
## [member min_stop_time], before it enters the line zone. Only traffic moving along this node's
## forward axis (-Z) is checked, so the line applies to one direction.

## Where the car must stop: the stretch of road just before the line.
@export var approach_zone: TriggerZone
## Entering this zone counts as crossing the line; it starts at the line's far edge.
@export var line_zone: TriggerZone
@export var stop_fault: FaultDef = preload("res://scenarios/data/faults/stop_not_made.tres")
## Seconds the car must stay stopped.
@export var min_stop_time := 0.5

var _stop := Episode.new()
var _satisfied := false
var _judged := false


func required_exports() -> PackedStringArray:
	return ["approach_zone", "line_zone"]


func _on_bound() -> void:
	watch(approach_zone, _on_approach_entered)
	watch(line_zone, _on_line_entered)


func _physics_process(delta: float) -> void:
	if not is_live() or _satisfied:
		return
	var p := probe()
	if _stop.update(approach_zone.contains(p) and p.is_stopped(), delta, min_stop_time):
		_satisfied = true


func _on_approach_entered(p: VehicleProbe) -> void:
	if p.travels_along(-global_basis.z):
		_stop.reset()
		_satisfied = false
		_judged = false


func _on_line_entered(p: VehicleProbe) -> void:
	if _judged or not p.travels_along(-global_basis.z):
		return
	_judged = true
	if not _satisfied:
		report_here(stop_fault)
