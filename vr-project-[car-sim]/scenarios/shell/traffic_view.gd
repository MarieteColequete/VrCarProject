class_name TrafficView
extends RefCounted
## Draws the road users and gives them bodies, reading only the world: a car of the
## [KitModels] per vehicle, stretched to its body and lightly tinted with its colour, one
## [MultiMesh] per model, interpolated between physics ticks; an animated [PedestrianModel] per
## pedestrian, a survivor of the retro characters kit standing idle or walking, its node
## interpolated by the engine; and a kinematic box per road user in the physics server, on the
## traffic or pedestrian layer. The player's car meets walkers there as any body; its own body
## ([member ignore]) is exempt from road users' cars, which it meets through [Impacts]. Neither
## takes part in the simulation; with no view at all, traffic runs the same.

## Floats per instance in the buffer: a 3x4 transform and a colour.
const STRIDE := 16
## Road users longer than this, metres, are drawn as a lorry or van.
const LONG := 5.5
## How much of a road user's colour tints its model.
const TINT := 0.35
const WALKER := "walker"

var _parent: Node3D
var _capacity: int
var _space: RID
## The player's car's body, which road users' cars do not meet in the physics engine: their
## crashes are [Impacts]'.
var ignore := RID()
## Model path (or [constant WALKER]) to its group: [code]{multimesh, instance, slots, drawn,
## current, previous}[/code], slots mapping a road user to its instance.
var _groups := {}
# Road user entity to its group's key, and to its body, shape, and last transform.
var _group_of := {}
# Pedestrian entity to its model.
var _walkers := {}
var _bodies := {}


## A view under [param parent], with room for [param capacity] road users per model to start with.
func _init(parent: Node3D, capacity: int) -> void:
	_parent = parent
	_capacity = maxi(capacity, 1)
	_space = parent.get_world_3d().space


## The model a road user is drawn with: [constant WALKER] for a pedestrian, its own [param model] when it
## has one that loads, else a car, or a long vehicle for a long body, picked by its entity so each
## keeps its look.
static func model_for(entity: int, size: Vector3, is_pedestrian: bool, model := "") -> String:
	if is_pedestrian:
		return WALKER
	if not model.is_empty() and KitModels.mesh(model) != null:
		return model
	return KitModels.long_vehicle(entity) if size.z > LONG else KitModels.car(entity)


## The view's step: places every road user's model and body where the world has it. Each group's
## instances go to its multimesh as one buffer, with the last tick's as the one to interpolate from
## (the two buffers swap each tick); a body moves only when its road user did. A road user that
## left the world gives up its instance and body.
func draw(world: World) -> void:
	var store := world.store(Schema.AGENT)
	if store == null:
		return
	if _group_of.size() + _walkers.size() > store.size():
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
	var models: Array = store.column(&"model")
	var speeds: PackedFloat64Array = store.column(&"current_speed")
	for i in ids.size():
		if walkers[i] == 1:
			_draw_walker(ids[i], sizes[i], positions[i], facings[i], speeds[i], jumps[i] == 1)
			continue
		if not _group_of.has(ids[i]):
			var key := model_for(ids[i], sizes[i], walkers[i] == 1, models[i])
			var group := _group(key)
			group.slots[ids[i]] = group.slots.size()
			_group_of[ids[i]] = key
			_body(ids[i], sizes[i], walkers[i] == 1)
	var by_group := {}
	for i in ids.size():
		if walkers[i] == 1:
			continue
		var key: String = _group_of[ids[i]]
		if not by_group.has(key):
			by_group[key] = []
		(by_group[key] as Array).append(i)
	for key: String in _groups:
		var group: Dictionary = _groups[key]
		if _grow(group):
			group.drawn.clear()
		# Taken out of the group while written, so the writes do not copy the buffers.
		var current: PackedFloat32Array = group.current
		var previous: PackedFloat32Array = group.previous
		group.current = PackedFloat32Array()
		group.previous = PackedFloat32Array()
		var drawn: Dictionary = group.drawn
		var slots: Dictionary = group.slots
		for i: int in by_group.get(key, []):
			var id := ids[i]
			var slot: int = slots[id]
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
			var cz := z * size.z
			current[k] = cx.x
			current[k + 1] = 0.0
			current[k + 2] = cz.x
			current[k + 3] = at.x
			current[k + 4] = 0.0
			current[k + 5] = size.y
			current[k + 6] = 0.0
			current[k + 7] = at.y
			current[k + 8] = cx.z
			current[k + 9] = 0.0
			current[k + 10] = cz.z
			current[k + 11] = at.z
			if not drawn.has(id):
				var colour := Color.WHITE.lerp(colours[i], TINT)
				_write_colour(current, slot, colour)
				_write_colour(previous, slot, colour)
			if jumps[i] or not drawn.has(id):
				for c in 12:
					previous[k + c] = current[k + c]
				drawn[id] = true
			var place := Transform3D(Basis(x, Vector3.UP, z), at)
			var pair: Array = _bodies[id]
			if pair[2] != place:
				pair[2] = place
				PhysicsServer3D.body_set_state(pair[0], PhysicsServer3D.BODY_STATE_TRANSFORM,
					place)
		var multimesh: MultiMesh = group.multimesh
		multimesh.set_buffer_interpolated(current, previous)
		multimesh.visible_instance_count = slots.size()
		group.current = previous
		group.previous = current


## How many road users each model draws, by model path, and the pedestrians under
## [constant WALKER]: for tests and the Dev HUD.
func counts() -> Dictionary:
	var out := {}
	for key: String in _groups:
		out[key] = (_groups[key].slots as Dictionary).size()
	if not _walkers.is_empty():
		out[WALKER] = _walkers.size()
	return out


## The pedestrian drawn for [param id]; null when there is none.
func walker(id: int) -> PedestrianModel:
	return _walkers.get(id)


## Places pedestrian [param id]'s model and body, making them on first sight; the model stands
## idle or walks at [param speed], and jumps to its place without interpolating when
## [param jumped].
func _draw_walker(id: int, size: Vector3, at: Vector3, facing: Vector3, speed: float,
		jumped: bool) -> void:
	var fresh := not _walkers.has(id)
	if fresh:
		var made := PedestrianModel.make(id, size.y)
		if made == null:
			return
		_parent.add_child(made)
		_walkers[id] = made
		_body(id, size, true)
	var flat := Vector3(facing.x, 0.0, facing.z)
	var basis := Basis.looking_at(flat, Vector3.UP) if flat.length_squared() > 0.000001 \
		else Basis.IDENTITY
	var place := Transform3D(basis, at)
	var model: PedestrianModel = _walkers[id]
	model.transform = place
	model.set_speed(speed)
	if fresh or jumped:
		model.reset_physics_interpolation()
	var pair: Array = _bodies[id]
	if pair[2] != place:
		pair[2] = place
		PhysicsServer3D.body_set_state(pair[0], PhysicsServer3D.BODY_STATE_TRANSFORM, place)


## Writes [param colour] into slot [param slot] of [param buffer].
static func _write_colour(buffer: PackedFloat32Array, slot: int, colour: Color) -> void:
	var i := slot * STRIDE + 12
	buffer[i] = colour.r
	buffer[i + 1] = colour.g
	buffer[i + 2] = colour.b
	buffer[i + 3] = colour.a


## The group drawing [param key], made on first use.
func _group(key: String) -> Dictionary:
	if _groups.has(key):
		return _groups[key]
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	var material: StandardMaterial3D
	var mesh := KitModels.unit_mesh(key)
	multimesh.mesh = mesh
	var own := mesh.surface_get_material(0) as StandardMaterial3D if mesh else null
	material = own.duplicate() if own else StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	multimesh.instance_count = _capacity
	multimesh.visible_instance_count = 0
	var instance := MultiMeshInstance3D.new()
	instance.name = "RoadUsers_" + key.get_file().get_basename()
	instance.multimesh = multimesh
	instance.material_override = material
	_parent.add_child(instance)
	var current := PackedFloat32Array()
	current.resize(_capacity * STRIDE)
	var previous := PackedFloat32Array()
	previous.resize(_capacity * STRIDE)
	var group := {multimesh = multimesh, instance = instance, slots = {}, drawn = {},
		current = current, previous = previous}
	_groups[key] = group
	return group


## Frees the instance and body of every road user no longer in [param store]: its group's last
## instance moves into each freed one and is drawn there afresh.
func _release(store: ComponentStore) -> void:
	for id: int in _walkers.keys():
		if not store.has(id):
			(_walkers[id] as Node).queue_free()
			_walkers.erase(id)
			var walker_pair: Array = _bodies[id]
			PhysicsServer3D.free_rid(walker_pair[0])
			PhysicsServer3D.free_rid(walker_pair[1])
			_bodies.erase(id)
	var gone := []
	for id: int in _group_of:
		if not store.has(id):
			gone.append(id)
	for id: int in gone:
		var group: Dictionary = _groups[_group_of[id]]
		var slots: Dictionary = group.slots
		var slot: int = slots[id]
		slots.erase(id)
		group.drawn.erase(id)
		_group_of.erase(id)
		var pair: Array = _bodies[id]
		PhysicsServer3D.free_rid(pair[0])
		PhysicsServer3D.free_rid(pair[1])
		_bodies.erase(id)
		var last := slots.size()
		if slot != last:
			for moved: int in slots:
				if slots[moved] == last:
					slots[moved] = slot
					group.drawn.erase(moved)
					break
		(group.multimesh as MultiMesh).visible_instance_count = slots.size()


## Frees the bodies and the multimeshes' nodes.
func clear() -> void:
	for pair: Array in _bodies.values():
		PhysicsServer3D.free_rid(pair[0])
		PhysicsServer3D.free_rid(pair[1])
	_bodies.clear()
	_group_of.clear()
	for model: Node in _walkers.values():
		if is_instance_valid(model):
			model.queue_free()
	_walkers.clear()
	for group: Dictionary in _groups.values():
		if is_instance_valid(group.instance):
			(group.instance as Node).queue_free()
	_groups.clear()


func _body(id: int, size: Vector3, is_pedestrian: bool) -> void:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_KINEMATIC)
	var shape := PhysicsServer3D.box_shape_create()
	PhysicsServer3D.shape_set_data(shape, size * 0.5)
	PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis(), Vector3(0, size.y * 0.5, 0)))
	BodyType.of(&"pedestrian" if is_pedestrian else &"vehicle").apply_rid(body)
	if not is_pedestrian and ignore.is_valid():
		PhysicsServer3D.body_add_collision_exception(body, ignore)
	PhysicsServer3D.body_set_space(body, _space)
	_bodies[id] = [body, shape, Transform3D()]


## Makes room in [param group] for its road users; true when it had to, which clears its
## instances.
func _grow(group: Dictionary) -> bool:
	var multimesh: MultiMesh = group.multimesh
	var needed: int = group.slots.size()
	if needed <= multimesh.instance_count:
		return false
	# Resizing clears the instances; every slot is set again in the same draw.
	multimesh.instance_count = maxi(needed, multimesh.instance_count * 2)
	multimesh.visible_instance_count = 0
	var current: PackedFloat32Array = group.current
	var previous: PackedFloat32Array = group.previous
	current.resize(multimesh.instance_count * STRIDE)
	previous.resize(multimesh.instance_count * STRIDE)
	group.current = current
	group.previous = previous
	return true
