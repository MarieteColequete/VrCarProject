@tool
class_name PoleBody
extends RefCounted
## The solid body of a pole standing on its node's origin, as road signs and traffic lights have.


## A static body of the obstacle [BodyType] with one box of [param size] standing on the origin.
static func make(size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Body"
	BodyType.of(&"obstacle").apply(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2.0
	body.add_child(shape)
	return body
