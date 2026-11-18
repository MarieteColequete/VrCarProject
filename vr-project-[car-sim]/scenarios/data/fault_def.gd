class_name FaultDef
extends Resource
## One kind of fault a check can report, such as not stopping at a stop sign.
##
## The tier names a [FaultTier] of the session's [ScoringPolicy]; the policy, not the fault,
## decides what the tier costs.

@export var id: StringName
@export var title: String
@export_multiline var description: String
@export var tier: StringName = &"minor"
