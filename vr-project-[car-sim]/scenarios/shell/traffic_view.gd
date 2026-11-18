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
## the multimesh as one buffer, with the last tick's as the one to interpolate from (the two
## buffers swap each tick); a body moves only when its road user did. A road user that left the
## world gives up its slot and body.
func draw(world: World) -> void:
	var store := world.store(Schema.AGENT)
	if store == null:
		return
	if _slots.size() > store.size():
		_release(store)
	if store.size() == 0:
		return
	var ids := store.ids
	var sizes: PackedVector3Array = store.column(&"body_size")
	var colours: PackedColorArray = store.column(&"colour")
	var positions: PackedVector3Array = store.column(&"position")
	var facings: PackedVector3Array = store.column(&"facing")
	var jumps: PackedByteArray = store.column(&"jumped")
	var walkers: PackedByteArray = store.column(&"pedestrian")
	for i in ids.size():
		if not _slots.has(ids[i]):
			_slots[ids[i]] = _slots.size()
			_body(ids[i], sizes[i], walkers[i] == 1)
	if _grow(_slots.size()):
		_drawn.clear()
	var current := _current
	var previous := _previous
	for i in ids.size():
		var id := ids[i]
		var slot: int = _slots[id]
		var size := sizes[i]
		var at := positions[i]
		var f := facings[i]
		# Facing on the ground, as Basis.looking_at would give it: z behind, x to the right.
		var z := Vector3(-f.x, 0.0, -f.z)
		var x := Vector3(-f.z, 0.0, f.x)
		if f.length_squared() < 0.000001:
			z = Vector3.BACK
			x = Vector3.RIGHT
		var k := slot * STRIDE
		var cx := x * size.x
		var cy := size.y
		var cz := z * size.z
		current[k] = cx.x
		current[k + 1] = 0.0
		current[k + 2] = cz.x
		current[k + 3] = at.x
		current[k + 4] = 0.0
		current[k + 5] = cy
		current[k + 6] = 0.0
		current[k + 7] = at.y + cy * 0.5
		current[k + 8] = cx.z
		current[k + 9] = 0.0
		current[k + 10] = cz.z
		current[k + 11] = at.z
		if not _drawn.has(id):
			_write_colour(current, slot, colours[i])
			_write_colour(previous, slot, colours[i])
		if jumps[i] or not _drawn.has(id):
			for c in 12:
				previous[k + c] = current[k + c]
			_drawn[id] = true
		var place := Transform3D(Basis(x, Vector3.UP, z), at)
		var pair: Array = _bodies[id]
		if pair[2] != place:
			pair[2] = place
			PhysicsServer3D.body_set_state(pair[0], PhysicsServer3D.BODY_STATE_TRANSFORM, place)
	_multimesh.set_buffer_interpolated(current, previous)
	_multimesh.visible_instance_count = _slots.size()
	_previous = current
	_current = previous


## Writes [param colour] into slot [param slot] of [param buffer].
static func _write_colour(buffer: PackedFloat32Array, slot: int, colour: Color) -> void:
	var i := slot * STRIDE + 12
	buffer[i] = colour.r
	buffer[i + 1] = colour.g
	buffer[i + 2] = colour.b
	buffer[i + 3] = colour.a


## Frees the slot and body of every road user no longer in [param store]: the last slot moves into
## each freed one and is drawn there afresh.
func _release(store: ComponentStore) -> void:
	var gone := []
	for id: int in _slots:
		if not store.has(id):
			gone.append(id)
	for id: int in gone:
		var slot: int = _slots[id]
		_slots.erase(id)
		_drawn.erase(id)
		var pair: Array = _bodies[id]
		PhysicsServer3D.free_rid(pair[0])
		PhysicsServer3D.free_rid(pair[1])
		_bodies.erase(id)
		var last := _slots.size()
		if slot != last:
			for moved: int in _slots:
				if _slots[moved] == last:
					_slots[moved] = slot
					_drawn.erase(moved)
					break
	_multimesh.visible_instance_count = _slots.size()


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


## Makes room for [param needed] instances; true when it had to, which clears every slot.
func _grow(needed: int) -> bool:
	if needed <= _multimesh.instance_count:
		return false
	# Resizing clears the instances; every slot is set again in the same draw.
	_multimesh.instance_count = maxi(needed, _multimesh.instance_count * 2)
	_multimesh.visible_instance_count = 0
	_current.resize(_multimesh.instance_count * STRIDE)
	_previous.resize(_multimesh.instance_count * STRIDE)
	return true
