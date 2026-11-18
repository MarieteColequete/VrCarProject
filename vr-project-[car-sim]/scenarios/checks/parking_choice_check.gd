@tool
class_name ParkingChoiceCheck
extends Check
## Whether the car is parked somewhere allowed. When the car settles (stopped with the handbrake
## on, or stopped for [member settle_time]) it is judged once: inside a [NoParkingZone] or with a
## corner within [member line_distance] of a no-parking line is illegal; in a reserved bay, or in
## one marked occupied, is a fault of its own. Limit it with [member Check.active_steps] to the
## steps where the driver is choosing a place, so waiting in traffic is never read as parking.

## Seconds stopped, without the handbrake, after which the car counts as parked; longer than
## [member ParkingCheck.settle_time], so a pause while manoeuvring is not judged as a choice.
@export var settle_time := 5.0
## Distance, in metres, from a no-parking line within which a corner counts as parked on it.
@export var line_distance := 1.0
@export var illegal_fault: FaultDef = preload("res://scenarios/data/faults/parking_illegal.tres")
@export var reserved_fault: FaultDef = preload("res://scenarios/data/faults/parking_reserved.tres")
@export var occupied_fault: FaultDef = preload("res://scenarios/data/faults/parking_occupied.tres")


func rule_script() -> Script:
	return ParkingChoiceRule


func rule_params(_bake: Bake) -> Dictionary:
	return {settle_time = settle_time, line_distance = line_distance,
		illegal_fault = illegal_fault, reserved_fault = reserved_fault,
		occupied_fault = occupied_fault}
