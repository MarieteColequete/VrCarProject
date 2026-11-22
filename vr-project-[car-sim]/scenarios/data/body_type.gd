@tool
class_name BodyType
extends Resource
## What kind of solid thing a body is: its physics layer, what it collides with, its surface, and
## whether touching it is judged. Kept in [constant FOLDER], one per layer of [Layers] but for the
## world layer, which has two surfaces: the ground (grass) and the roads' asphalt; then pavement,
## obstacle, vehicle, pedestrian, and the player's car. Bodies take their settings from their type
## through [method apply], so a kind of thing collides the same everywhere.

const FOLDER := "res://scenarios/data/body_types/"

@export var title := ""
## The layer the body is on, a bit of [Layers].
@export_flags_3d_physics var layer := 0
## The layers the body collides with; zero for bodies that never move.
@export_flags_3d_physics var mask := 0
## The surface's grip and bounce. Wheel physics reads them from the body a wheel stands on, so a
## road's asphalt grips better than the grass beside it.
@export_range(0.0, 1.0) var friction := 1.0
@export_range(0.0, 1.0) var bounce := 0.0

var _material: PhysicsMaterial


## The type [param kind] of [constant FOLDER], such as [code]&"obstacle"[/code].
static func of(kind: StringName) -> BodyType:
	return load(FOLDER + kind + ".tres") as BodyType


## Whether the bake turns its boxes into obstacle entities: road users see them, and
## [ContactCheck] judges touching them. It follows the layer: [constant Layers.JUDGED].
func judged() -> bool:
	return (layer & Layers.JUDGED) != 0


## The surface as a physics material, built once.
func material() -> PhysicsMaterial:
	if _material == null:
		_material = PhysicsMaterial.new()
		_material.friction = friction
		_material.bounce = bounce
	return _material


## Gives [param body] the type's layer, mask, and surface.
func apply(body: CollisionObject3D) -> void:
	body.collision_layer = layer
	body.collision_mask = mask
	if body is StaticBody3D:
		(body as StaticBody3D).physics_material_override = material()
	elif body is RigidBody3D:
		(body as RigidBody3D).physics_material_override = material()


## Gives the server body [param body] the type's layer and mask.
func apply_rid(body: RID) -> void:
	PhysicsServer3D.body_set_collision_layer(body, layer)
	PhysicsServer3D.body_set_collision_mask(body, mask)
