class_name ScenarioStep
extends Node
## One step of a scenario's task, such as "park in a free bay" and then "leave the car park".
## Steps run in tree order; a [GoalCheck] bound to a step ends it, and the last step's goal ends
## the attempt. A [Check] can be limited to some steps through [member Check.active_steps].

@export var title: String
@export_multiline var instruction: String
