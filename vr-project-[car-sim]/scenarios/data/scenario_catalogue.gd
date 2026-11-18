class_name ScenarioCatalogue
extends Resource
## Every scenario the game offers, in the order menus list them. Menus read
## [code]res://scenarios/catalogue.tres[/code] and load a chosen scenario through
## [method ExamRunner.load_definition]; nothing needs to scan folders.

const DEFAULT := "res://scenarios/catalogue.tres"

@export var scenarios: Array[ScenarioDefinition] = []


## The project's catalogue.
static func main() -> ScenarioCatalogue:
	return load(DEFAULT) as ScenarioCatalogue


## The definition with [param id], or null.
func find(id: StringName) -> ScenarioDefinition:
	for definition in scenarios:
		if definition and definition.id == id:
			return definition
	return null


## The definitions of one [param category], in catalogue order.
func in_category(category: String) -> Array[ScenarioDefinition]:
	var found: Array[ScenarioDefinition] = []
	for definition in scenarios:
		if definition and definition.category == category:
			found.append(definition)
	return found
