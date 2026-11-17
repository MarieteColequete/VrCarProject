@tool
class_name JunctionExit
extends TriggerZone
## One way out of a junction or roundabout, placed as a child of its [JunctionCheck]: which
## indicator leaving this way needs, and whether the scenario allows it.

## The indicator this exit needs; none for straight on.
@export_enum("None:1", "Left:2", "Right:3") var side: int = VehicleProbe.Indicator.OFF
## Whether the scenario's route may use this exit.
@export var allowed := true
