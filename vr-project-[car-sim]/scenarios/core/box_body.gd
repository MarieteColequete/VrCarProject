class_name BoxBody
extends RefCounted
## Gives a body a box: a collision shape standing on the body's origin, and a look of the same
## size, a model of the [KitModels] stretched to the box or a coloured box.


## Adds to [param body] a box of [param size] and the model at [param model] fitted to it; a box
## of [param colour] when no model is given or it does not load.
static func build(body: CollisionObject3D, size: Vector3, colour: Color, model := "") -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	body.add_child(shape)
	var built := KitModels.mesh(model) if not model.is_empty() else null
	if built:
		var part := MeshInstance3D.new()
		part.mesh = built
		part.scale = size / built.get_aabb().size.max(Vector3.ONE * 0.001)
		body.add_child(part)
		return
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	box_mesh.material = material
	mesh.mesh = box_mesh
	mesh.position.y = size.y * 0.5
	body.add_child(mesh)
