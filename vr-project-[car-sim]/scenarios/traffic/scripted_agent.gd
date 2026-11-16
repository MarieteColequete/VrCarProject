class_name ScriptedAgent
extends AnimatableBody3D
## Another road user on a fixed script: a car or a pedestrian that follows a [Path3D] at a set
## speed. It starts after [member start_delay], counted from when it is armed: at once, or when
## a vehicle enters [member trigger]. It can pause once along the way, and loop. The same script
## always plays out the same way, so scenarios with traffic stay reproducible.
##
## Cars sit on the obstacle layer and pedestrians on the pedestrian layer and in the
## [code]pedestrian[/code] group, so the [ContactCheck] tells them apart. Without a
## [CollisionShape3D] child, it builds a box of [member body_size].

signal started
signal finished

enum State { WAITING, MOVING, PAUSED, DONE }

@export var path: Path3D
## Metres per second.
@export var speed := 1.4
@export var start_delay := 0.0
## Starts the delay when a vehicle enters this zone; empty to start at once.
@export var trigger: TriggerZone
@export var loop := false
@export var pedestrian := false
## Distance along the path, in metres, where the agent pauses once per lap; negative for none.
@export var pause_at := -1.0
@export var pause_time := 0.0
@export var body_size := Vector3(1.8, 1.4, 4.2)
@export var colour := Color(0.85, 0.75, 0.2)

var state := State.WAITING
## Distance travelled along the path in the current lap, in metres.
var progress := 0.0

var _armed := false
var _clock := 0.0
var _paused_for := 0.0
var _paused_this_lap := false


func _ready() -> void:
	collision_layer = VehicleProbe.PEDESTRIAN_LAYER if pedestrian else VehicleProbe.OBSTACLE_LAYER
	collision_mask = 0
	if pedestrian:
		add_to_group(&"pedestrian")
	if not _has_shape():
		_build_body()
	_armed = trigger == null
	if trigger:
		trigger.vehicle_entered.connect(func(_p: VehicleProbe) -> void: _armed = true)
	_place(0.0)


## Seconds until the agent reaches [param offset] along its path at its speed, counting the
## remaining start delay and pause; INF when it will not get there (not armed, done, or past it
## without looping).
func time_to(offset: float) -> float:
	if state == State.DONE or (state == State.WAITING and not _armed):
		return INF
	var length := path.curve.get_baked_length()
	var remaining := offset - progress
	if remaining < 0.0:
		if not loop:
			return INF
		remaining += length
	var wait := 0.0
	if state == State.WAITING:
		wait = maxf(start_delay - _clock, 0.0)
	elif state == State.PAUSED:
		wait = maxf(pause_time - _paused_for, 0.0)
	if pause_at >= 0.0 and not _paused_this_lap and pause_at <= offset and state != State.PAUSED:
		wait += pause_time
	return wait + remaining / maxf(speed, 0.001)


func _physics_process(delta: float) -> void:
	match state:
		State.WAITING:
			if not _armed:
				return
			_clock += delta
			if _clock >= start_delay:
				state = State.MOVING
				started.emit()
		State.PAUSED:
			_paused_for += delta
			if _paused_for >= pause_time:
				state = State.MOVING
		State.MOVING:
			_advance(speed * delta)


func _advance(step: float) -> void:
	var length := path.curve.get_baked_length()
	progress += step
	if pause_at >= 0.0 and not _paused_this_lap and progress >= pause_at:
		progress = pause_at
		_paused_this_lap = true
		_paused_for = 0.0
		state = State.PAUSED
	elif progress >= length:
		if loop:
			progress = fmod(progress, length)
			_paused_this_lap = false
		else:
			progress = length
			state = State.DONE
			finished.emit()
	_place(progress)


func _place(offset: float) -> void:
	if path == null or path.curve == null:
		return
	var curve := path.curve
	var length := curve.get_baked_length()
	var here := path.global_transform * curve.sample_baked(offset)
	var ahead := path.global_transform * curve.sample_baked(minf(offset + 0.5, length))
	var behind := path.global_transform * curve.sample_baked(maxf(offset - 0.5, 0.0))
	var tangent := ahead - behind
	tangent.y = 0.0
	var facing := global_basis
	if tangent.length() > 0.001:
		facing = Basis.looking_at(tangent.normalized(), Vector3.UP)
	global_transform = Transform3D(facing, here)


func _has_shape() -> bool:
	for child in get_children():
		if child is CollisionShape3D:
			return true
	return false


func _build_body() -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = body_size
	shape.shape = box
	shape.position.y = body_size.y * 0.5
	add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = body_size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	box_mesh.material = material
	mesh.mesh = box_mesh
	mesh.position.y = body_size.y * 0.5
	add_child(mesh)
