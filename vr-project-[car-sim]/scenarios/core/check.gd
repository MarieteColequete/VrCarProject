@tool
@abstract
class_name Check
extends Node3D
## Base of every check placed in a scenario scene: the authoring side of a rule. A check holds the
## rule's settings as exports, with configuration warnings in the editor; when the scenario loads,
## a [Bake] turns it into a rule entity, its parameters with every node reference resolved to an
## entity, and the rule's pure functions ([method rule_script]) judge the attempt from then on.
## The node itself does nothing at runtime.
##
## A new check names its rule script, lists its parameters in [method rule_params], and lists the
## exports it cannot work without in [method required_exports]. Every fault export defaults to its
## fault from [code]res://scenarios/data/faults/[/code], so a scene only sets one to use a
## different fault. When [member active_steps] is set, the rule only acts during those steps.

## The steps during which the check acts; empty for the whole attempt.
@export var active_steps: Array[ScenarioStep] = []


## The script holding the rule's static [code]initial[/code], [code]step[/code], and
## [code]finish[/code] functions.
@abstract func rule_script() -> Script


## The rule's parameters, node references resolved through [param bake].
@abstract func rule_params(bake: Bake) -> Dictionary


## The exports the check cannot work without; an empty one shows as a configuration warning.
func required_exports() -> PackedStringArray:
	return PackedStringArray()


## Every fault the check may report, from its exports.
func fault_defs() -> Array[FaultDef]:
	var out: Array[FaultDef] = []
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value: Variant = get(property.name)
			if value is FaultDef:
				out.append(value)
	return out


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for property in required_exports():
		var value: Variant = get(property)
		if value == null or (value is Array and value.is_empty()):
			warnings.append("%s is not set." % property.capitalize())
	return warnings
