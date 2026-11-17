class_name Scenario
extends Node3D
## The root of a scenario scene: the world, a spawn point, the [Check] nodes that judge it, and
## optionally the [ScenarioStep]s of its task. The queries below are built on first use and kept,
## since a scenario's markings, bays, and checks do not change during an attempt.

@export var definition: ScenarioDefinition
## Where and facing which way the car starts.
@export var spawn_point: Marker3D

var _marking_index: MarkingIndex
var _bays: Array[ParkingBay] = []
var _no_parking: Array[NoParkingZone] = []
var _scanned := false


## The scene's road markings, indexed for detection.
func marking_index() -> MarkingIndex:
	if _marking_index == null:
		_marking_index = MarkingIndex.new()
		for node in _descendants():
			if node is RoadMarking:
				_marking_index.add(node)
	return _marking_index


## Every [Check] in the scene, in tree order.
func get_checks() -> Array[Check]:
	var found: Array[Check] = []
	for node in _descendants():
		if node is Check:
			found.append(node)
	return found


## Every [ScenarioStep] in the scene, in tree order, which is the order they run in.
func get_steps() -> Array[ScenarioStep]:
	var found: Array[ScenarioStep] = []
	for node in _descendants():
		if node is ScenarioStep:
			found.append(node)
	return found


## Every [ParkingBay] in the scene.
func bays() -> Array[ParkingBay]:
	_scan()
	return _bays


## Every [NoParkingZone] in the scene.
func no_parking_zones() -> Array[NoParkingZone]:
	_scan()
	return _no_parking


## The bay holding [param point], or null.
func bay_at(point: Vector3) -> ParkingBay:
	for bay in bays():
		if bay.contains(point):
			return bay
	return null


func _scan() -> void:
	if _scanned:
		return
	_scanned = true
	for node in _descendants():
		if node is ParkingBay:
			_bays.append(node)
		elif node is NoParkingZone:
			_no_parking.append(node)


## The scene's nodes below the root, in tree order. Internal children, such as the edges a
## [ParkingBay] draws for itself, belong to their owner and are left out.
func _descendants() -> Array[Node]:
	var out: Array[Node] = []
	_collect(self, out)
	return out


static func _collect(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		out.append(child)
		_collect(child, out)
