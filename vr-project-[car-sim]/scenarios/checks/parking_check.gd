class_name ParkingCheck
extends Check
## How well the car is parked. When the car settles (stopped with the handbrake on, or stopped
## for [member settle_time]) with its centre in a [ParkingBay], the manoeuvre is judged once: how
## far the body overhangs the bay, how far it is from the facing the bay requires, how many
## times it changed direction, and how long it took. Parking in a bay that is free and not
## reserved completes [member step]; whether the place was allowed at all is the
## [ParkingChoiceCheck]'s concern.
##
## The manoeuvre is counted from the moment the check becomes live, so limit it with
## [member Check.active_steps] to the step that asks for the park.

signal parked(bay: ParkingBay)

## The step a good park completes; empty to complete nothing.
@export var step: ScenarioStep
## The bays judged; empty for every bay in the scenario.
@export var bays: Array[ParkingBay] = []
@export var settle_time := 2.0
## Overhang, in metres, up to which leaving the bay is minor.
@export var overhang_margin := 0.3
## Degrees off the required facing allowed.
@export var facing_tolerance := 10.0
## Direction changes allowed for the manoeuvre.
@export var max_direction_changes := 3
## Seconds allowed for the manoeuvre; 0 for no limit.
@export var time_limit := 0.0
@export var overhang_minor_fault: FaultDef
@export var overhang_serious_fault: FaultDef
@export var misaligned_fault: FaultDef
@export var manoeuvres_fault: FaultDef
@export var too_slow_fault: FaultDef

var _baseline := -1
var _started := 0.0
var _judged := false


func _physics_process(_delta: float) -> void:
	if not is_live():
		_baseline = -1
		return
	var p := probe()
	if _baseline < 0:
		_baseline = p.direction_changes
		_started = session.elapsed
	if p.direction != VehicleProbe.Direction.STOPPED:
		_judged = false
		return
	if _judged or not p.is_settled(settle_time):
		return
	_judged = true
	var bay := bay_under(p)
	if bay:
		_judge(bay, p)


## The bay holding the car's centre, among those this check judges.
func bay_under(p: VehicleProbe) -> ParkingBay:
	for bay in _candidates():
		if bay.contains(p.global_position):
			return bay
	return null


func _candidates() -> Array[ParkingBay]:
	if not bays.is_empty():
		return bays
	var found: Array[ParkingBay] = []
	for node in get_tree().get_nodes_in_group(&"parking_bay"):
		if session.scenario.is_ancestor_of(node):
			found.append(node)
	return found


func _judge(bay: ParkingBay, p: VehicleProbe) -> void:
	var at := p.global_position
	var over := bay.overhang(p.corners())
	if over > overhang_margin:
		report(overhang_serious_fault, at)
	elif over > 0.0:
		report(overhang_minor_fault, at)
	if bay.facing_error(p.forward()) > facing_tolerance:
		report(misaligned_fault, at)
	if p.direction_changes - _baseline > max_direction_changes:
		report(manoeuvres_fault, at)
	if time_limit > 0.0 and session.elapsed - _started > time_limit:
		report(too_slow_fault, at)
	parked.emit(bay)
	if step and not bay.reserved and not bay.occupied:
		session.complete_step(step)
