class_name FaultTier
extends Resource
## A severity tier of a [ScoringPolicy].

## The name faults refer to in [member FaultDef.tier].
@export var id: StringName
@export var title: String
## A fault of an eliminating tier fails the attempt and ends the session at once.
@export var eliminating := false
## How many faults of this tier an attempt may collect and still pass; -1 for no limit.
@export var max_allowed := -1
