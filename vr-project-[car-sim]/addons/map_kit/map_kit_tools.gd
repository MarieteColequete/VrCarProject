@tool
class_name MapKitTools
extends RefCounted
## What the Map Kit editor plugin does to a map, kept apart from the editor so it runs and is
## tested headless, split by what it works on: [MapFiles], [MapPalette], [RoadNetwork],
## [MapProblems], [TerrainAuthoring] and [AssetTools]. Here: a change to an open map, which comes
## back as an [MapKitTools.Edit] the plugin applies with undo and a test applies directly; a
## palette piece; and the few helpers they share.

const ASPHALT := preload("res://scenarios/kit/asphalt.tres")


## One entry of the palette: its button text, the section it is listed under, the map node it is
## added under, its icon, a tooltip, and the function building it.
class Piece:
	extends RefCounted
	var label: String
	var section: String
	var group: String
	var make: Callable
	## An editor theme icon's name, or a path to an icon of the kit's own.
	var icon: String
	var tip: String
	## Whether it joins an open road end when placed near one.
	var joins_roads := false
	## How far it is turned about the vertical when placed, radians.
	var turn := 0.0

	func _init(p_label: String, p_section: String, p_group: String, p_make: Callable,
			p_icon := "", p_tip := "") -> void:
		label = p_label
		section = p_section
		group = p_group
		make = p_make
		icon = p_icon
		tip = p_tip


## A change to an open map: nodes to remove, nodes to add, and properties to set, in that order.
## The plugin turns it into one undo action; [method apply] makes it at once.
class Edit:
	extends RefCounted
	## [code][parent, node][/code] pairs.
	var adds: Array = []
	var removes: Array[Node] = []
	## [code][object, property, value][/code] triples.
	var sets: Array = []

	func is_empty() -> bool:
		return adds.is_empty() and removes.is_empty() and sets.is_empty()

	func add(parent: Node, node: Node) -> Edit:
		adds.append([parent, node])
		return self

	func remove(node: Node) -> Edit:
		if not removes.has(node):
			removes.append(node)
		return self

	func set_value(object: Object, property: StringName, value: Variant) -> Edit:
		sets.append([object, property, value])
		return self

	func merge(other: Edit) -> Edit:
		adds.append_array(other.adds)
		for node in other.removes:
			remove(node)
		sets.append_array(other.sets)
		return self

	## The nodes it adds.
	func added() -> Array[Node]:
		var out: Array[Node] = []
		for pair: Array in adds:
			out.append(pair[1])
		return out

	## Makes the change without undo; added nodes are owned by [param scene_owner].
	func apply(scene_owner: Node) -> void:
		for node in removes:
			node.get_parent().remove_child(node)
			node.free()
		for pair: Array in adds:
			(pair[0] as Node).add_child(pair[1], true)
			MapKitTools.own(pair[1], scene_owner)
		for triple: Array in sets:
			(triple[0] as Object).set(triple[1], triple[2])


## Sets the owner of [param node] and of every descendant that is not internal, so a scene saves
## them.
static func own(node: Node, scene_owner: Node) -> void:
	if node != scene_owner:
		node.owner = scene_owner
	for child in node.get_children():
		own(child, scene_owner)


## [param position] on a grid of [param step] metres, its height kept.
static func snapped(position: Vector3, step := 0.5) -> Vector3:
	if step <= 0.0:
		return position
	return Vector3(snappedf(position.x, step), position.y, snappedf(position.z, step))


static func nodes_of(map: Node) -> Array[Node]:
	if map is RoadMap:
		return (map as RoadMap).nodes()
	var out: Array[Node] = []
	Scenario.collect(map, out)
	return out


static func with_descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(with_descendants(child))
	return out


static func straight(length: float) -> Curve3D:
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 0, length / 2.0))
	curve.add_point(Vector3(0, 0, -length / 2.0))
	return curve


## A straight curve from the origin along -Z.
static func straight_from(length: float) -> Curve3D:
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0, -length))
	return curve


## Moves each of [param nodes] onto the grid of [param step] metres, its height kept.
static func snap_nodes(nodes: Array, step: float) -> Edit:
	var edit := Edit.new()
	for node in nodes:
		if node is Node3D:
			edit.set_value(node, &"position",
				MapKitTools.snapped(node.position, step if step > 0.0 else 0.5))
	return edit
