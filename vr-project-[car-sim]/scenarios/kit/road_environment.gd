@tool
class_name RoadEnvironment
extends Node3D
## The world every scenario shares: daylight, a sky, and a flat grass ground the car drives on.
## The ground is [member ground_size] metres, centred on [member ground_offset]; it is built
## here, as internal children, so a scenario only sets the two values. A map with a [Terrain]
## turns [member ground] off: the terrain is its ground.

const GRASS := preload("res://scenarios/kit/grass.tres")

## Width (X) and length (Z) of the ground, metres.
@export var ground_size := Vector2(200, 200):
	set(value):
		ground_size = value
		_rebuild()
## Whether the flat ground is built; off for a map whose [Terrain] is the ground.
@export var ground := true:
	set(value):
		ground = value
		_rebuild()
## Where the ground's centre sits, relative to this node.
@export var ground_offset := Vector3.ZERO:
	set(value):
		ground_offset = value
		_rebuild()

var _ground: StaticBody3D


func _ready() -> void:
	var sun := DirectionalLight3D.new()
	sun.transform = Transform3D(Vector3(0.8660254, 0, -0.5), Vector3(-0.35355338, 0.70710677,
		-0.61237246), Vector3(0.35355338, 0.70710677, 0.61237246), Vector3(0, 20, 0))
	sun.shadow_enabled = true
	add_child(sun, false, INTERNAL_MODE_FRONT)
	var sky := Environment.new()
	sky.background_mode = Environment.BG_COLOR
	sky.background_color = Color(0.55, 0.7, 0.85)
	sky.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	sky.ambient_light_color = Color(0.8, 0.8, 0.85)
	sky.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = sky
	add_child(world, false, INTERNAL_MODE_FRONT)
	_rebuild()


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _ground:
		remove_child(_ground)
		_ground.queue_free()
		_ground = null
	if not ground:
		return
	_ground = StaticBody3D.new()
	_ground.name = "Ground"
	BodyType.of(&"ground").apply(_ground)
	_ground.position = ground_offset
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ground_size.x, 0.2, ground_size.y)
	shape.shape = box
	shape.position.y = -0.1
	_ground.add_child(shape)
	var grass := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = ground_size
	grass.mesh = plane
	grass.material_override = GRASS
	_ground.add_child(grass)
	add_child(_ground, false, INTERNAL_MODE_FRONT)
