class_name TrafficView
extends RefCounted
## Draws the road users and gives them bodies, reading only the world: one [MultiMesh] of boxes,
## coloured and sized per road user and interpolated between physics ticks, and a kinematic box
## per road user in the physics server, on the obstacle or pedestrian layer, so the player's car
## collides with them as with any car or walker. Neither takes part in the simulation; with no
## view at all, traffic runs the same.

const MATERIAL_COLOUR := Color.WHITE
## Floats per instance in the buffer: a 3x4 transform and a colour.
const STRIDE := 16

var _instance: MultiMeshInstance3D
var _multimesh: MultiMesh
var _space: RID
# Road user entity to its slot in the multimesh, and to its body, shape, and last transform.
var _slots := {}
var _bodies := {}
var _drawn := {}
var _current := PackedFloat32Array()
var _previous := PackedFloat32Array()


## A view under [param parent], with room for [param capacity] road users to start with.
func _init(parent: Node3D, capacity: int) -> void:
	_multimesh = MultiMesh.new()
	_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	_multimesh.use_colors = true
	var box := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = MATERIAL_COLOUR
	box.material = material
	_multimesh.mesh = box
	_multimesh.instance_count = maxi(capacity, 1)
	_multimesh.visible_instance_count = 0
	_current.resize(_multimesh.instance_count * STRIDE)
	_previous.resize(_multimesh.instance_count * STRIDE)
	_instance = MultiMeshInstance3D.new()
	_instance.name = "RoadUsers"
	_instance.multimesh = _multimesh
	parent.add_child(_instance)
	_space = parent.get_world_3d().space


## The view's step: places every road user's box and body where the world has it. The boxes go to
## the multimesh as one buffer, with the last tick's as the one to interpolate from; a body moves
## only when its road user did.
func draw(world: World) -> void:
	var store := world.store(Schema.AGENT)
	if store == null or store.size() == 0:
		return
	var agents := AgentTable.view_of(store)
	for i in agents.size():
		var id := agents.ids[i]
		if not _slots.has(id):
			_slots[id] = _slots.size()
			_body(id, agents.body_size[i], agents.pedestrian[i] == 1)
	_grow(_slots.size())
	for i in agents.size():
		var id := agents.ids[i]
		var slot: int = _slots[id]
		var size := agents.body_size[i]
		var place := agents.transform(i)
		var box := place * Transform3D(Basis.from_scale(size), Vector3(0, size.y * 0.5, 0))
		_write(_current, slot, box, agents.colour[i])
		if agents.jumped[i] or not _drawn.has(id):
			_write(_previous, slot, box, agents.colour[i])
			_drawn[id] = true
		var pair: Array = _bodies[id]
		if pair[2] != place:
			pair[2] = place
			PhysicsServer3D.body_set_state(pair[0], PhysicsServer3D.BODY_STATE_TRANSFORM, place)
	_multimesh.set_buffer_interpolated(_current, _previous)
	_multimesh.visible_instance_count = _slots.size()
	_previous = _current.duplicate()


## Writes a transform and colour into slot [param slot] of [param buffer], in the multimesh's
## layout: the transform's three rows, then the colour.
static func _write(buffer: PackedFloat32Array, slot: int, t: Transform3D, colour: Color) -> void:
	var i := slot * STRIDE
	var b := t.basis
	buffer[i] = b.x.x
	buffer[i + 1] = b.y.x
	buffer[i + 2] = b.z.x
	buffer[i + 3] = t.origin.x
	buffer[i + 4] = b.x.y
	buffer[i + 5] = b.y.y
	buffer[i + 6] = b.z.y
	buffer[i + 7] = t.origin.y
	buffer[i + 8] = b.x.z
	buffer[i + 9] = b.y.z
	buffer[i + 10] = b.z.z
	buffer[i + 11] = t.origin.z
	buffer[i + 12] = colour.r
	buffer[i + 13] = colour.g
	buffer[i + 14] = colour.b
	buffer[i + 15] = colour.a


## Frees the bodies and the multimesh's node.
func clear() -> void:
	for pair: Array in _bodies.values():
		PhysicsServer3D.free_rid(pair[0])
		PhysicsServer3D.free_rid(pair[1])
	_bodies.clear()
	_slots.clear()
	_drawn.clear()
	if is_instance_valid(_instance):
		_instance.queue_free()


func _body(id: int, size: Vector3, is_pedestrian: bool) -> void:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_KINEMATIC)
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, size * 0.5)
	PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis(), Vector3(0, size.y * 0.5, 0)))
	PhysicsServer3D.body_set_collision_layer(body,
		Layers.PEDESTRIAN if is_pedestrian else Layers.OBSTACLE)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	PhysicsServer3D.body_set_space(body, _space)
	_bodies[id] = [body, shape, Transform3D()]


func _grow(needed: int) -> void:
	if needed <= _multimesh.instance_count:
		return
	# Resizing clears the instances; every slot is set again in the same draw.
	_multimesh.instance_count = maxi(needed, _multimesh.instance_count * 2)
	_multimesh.visible_instance_count = 0
	_current.resize(_multimesh.instance_count * STRIDE)
	_previous.resize(_multimesh.instance_count * STRIDE)
	_drawn.clear()
