class_name RoadPieces
extends RefCounted
## What a road and a junction do alike with the children they make: the lanes and markings they
## generate (tagged with a meta key, saved with the scene) and the bodies they keep out of it.
## Static, given the piece; a road is a [Path3D] and a junction a [Node3D], so they share no base.


## [param piece]'s children it generated as [param what], tagged under [param key].
static func generated(piece: Node, key: StringName, what: StringName) -> Array[Node]:
	var out: Array[Node] = []
	for child in piece.get_children():
		if child.get_meta(key, &"") == what:
			out.append(child)
	return out


## Adds [param node] to [param piece] as a child the scene saves.
static func keep(piece: Node, node: Node) -> void:
	piece.add_child(node, true)
	node.owner = piece.owner if piece.owner else piece


## Frees [param piece]'s children it generated as [param what].
static func clear(piece: Node, key: StringName, what: StringName) -> void:
	for child in generated(piece, key, what):
		piece.remove_child(child)
		child.free()


## Replaces [param piece]'s internal body [param old] with [param body], returning it.
static func swap_body(piece: Node, old: StaticBody3D, body: StaticBody3D) -> StaticBody3D:
	if old and is_instance_valid(old):
		piece.remove_child(old)
		old.queue_free()
	if body:
		piece.add_child(body, false, Node.INTERNAL_MODE_BACK)
	return body
