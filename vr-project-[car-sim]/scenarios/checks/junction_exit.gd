class_name JunctionExit
extends TriggerZone
## One way out of a junction or roundabout, placed as a child of its [JunctionCheck]: which
## indicator leaving this way needs, and whether the scenario allows it.

## The indicator this exit needs; OFF for straight on, where none is needed.
@export var side := VehicleProbe.Indicator.OFF
## Whether the scenario's route may use this exit.
@export var allowed := true
