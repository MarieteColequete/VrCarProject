@tool
class_name ParkingCheck
extends Check
## How well the car is parked. When the car settles (stopped with the handbrake on, or stopped
## for [member settle_time]) with its centre in a [ParkingBay], the manoeuvre is judged once: how
## far the body overhangs the bay, how far it is from the facing the bay requires, how many
## times it changed direction, and how long it took. Parking in a bay not marked occupied or
## reserved completes [member step]; whether the place was allowed at all is the
## [ParkingChoiceCheck]'s concern.
##
## The manoeuvre is counted from the moment the check becomes live, so limit it with
## [member Check.active_steps] to the step that asks for the park.

## The step a good park completes; empty to complete nothing.
@export var step: ScenarioStep
## The bays judged; empty for every bay in the scenario.
@export var bays: Array[ParkingBay] = []
## Seconds stopped, without the handbrake, after which the car counts as parked.
@export var settle_time := 2.0
## Overhang, in metres, up to which leaving the bay is minor.
@export var overhang_margin := 0.3
## Degrees off the required facing allowed.
@export var facing_tolerance := 10.0
## Direction changes allowed for the manoeuvre.
@export var max_direction_changes := 3
## Seconds allowed for the manoeuvre; 0 for no limit.
@export var time_limit := 0.0
@export var overhang_minor_fault: FaultDef = preload("res://scenarios/data/faults/parking_overhang_minor.tres")
@export var overhang_serious_fault: FaultDef = preload("res://scenarios/data/faults/parking_overhang_serious.tres")
@export var misaligned_fault: FaultDef = preload("res://scenarios/data/faults/parking_misaligned.tres")
@export var manoeuvres_fault: FaultDef = preload("res://scenarios/data/faults/parking_too_many_manoeuvres.tres")
@export var too_slow_fault: FaultDef = preload("res://scenarios/data/faults/parking_too_slow.tres")

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
	if bays.is_empty():
		return session.scenario.bay_at(p.global_position)
	for bay in bays:
		if bay and bay.contains(p.global_position):
			return bay
	return null


func _judge(bay: ParkingBay, p: VehicleProbe) -> void:
	var over := bay.overhang(p.corners())
	if over > overhang_margin:
		report_here(overhang_serious_fault)
	elif over > 0.0:
		report_here(overhang_minor_fault)
	if bay.facing_error(p.forward()) > facing_tolerance:
		report_here(misaligned_fault)
	if p.direction_changes - _baseline > max_direction_changes:
		report_here(manoeuvres_fault)
	if time_limit > 0.0 and session.elapsed - _started > time_limit:
		report_here(too_slow_fault)
	if step and not bay.reserved and not bay.occupied:
		session.complete_step(step)
