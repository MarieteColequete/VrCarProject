class_name BoxBody
extends RefCounted
## Gives a body a plain box: a collision shape and a coloured mesh of the same size, standing on
## the body's origin. Stands in for real models of cars and pedestrians.


static func build(body: CollisionObject3D, size: Vector3, colour: Color) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	box_mesh.material = material
	mesh.mesh = box_mesh
	mesh.position.y = size.y * 0.5
	body.add_child(mesh)
