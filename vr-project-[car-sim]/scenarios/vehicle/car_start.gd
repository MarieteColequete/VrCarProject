class_name CarStart
extends Resource
## How the car is when a scenario starts: its engine off or running, its lever, and how fast it is
## already going. A scenario about the checks before driving starts parked with the engine off; one
## that joins traffic may start rolling. A [ScenarioDefinition] without one leaves the car as it
## makes itself: running, in park (the manual in neutral), standing still.

## Whether the engine is running; a car that starts moving always has it running.
@export var engine_running := false
## The lever: P, R, N or D. The manual has no park, so P is neutral there, and D the gear that
## suits the speed.
@export_enum("P", "R", "N", "D") var lever := "P"
## How fast the car is already going forward, m/s. Above 0 the engine runs and the lever is D.
@export_range(0.0, 40.0, 0.1) var speed := 0.0


## The lever as a [enum Gearbox.Selector].
func selector() -> Gearbox.Selector:
	if speed > 0.0:
		return Gearbox.Selector.DRIVE
	return ["P", "R", "N", "D"].find(lever) as Gearbox.Selector


## Whether the engine runs at the start.
func running() -> bool:
	return engine_running or speed > 0.0
