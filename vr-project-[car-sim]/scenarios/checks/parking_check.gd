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


func rule_script() -> Script:
	return ParkingRule


func rule_params(bake: Bake) -> Dictionary:
	return {step = bake.step_index(step), bays = bake.ids_of(bays), settle_time = settle_time,
		overhang_margin = overhang_margin, facing_tolerance = facing_tolerance,
		max_direction_changes = max_direction_changes, time_limit = time_limit,
		overhang_minor_fault = overhang_minor_fault,
		overhang_serious_fault = overhang_serious_fault, misaligned_fault = misaligned_fault,
		manoeuvres_fault = manoeuvres_fault, too_slow_fault = too_slow_fault}
