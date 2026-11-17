@tool
class_name ScriptedAgent
extends AnimatableBody3D
## Another road user: a car or a pedestrian that plays its script by the book until it is forced
## to react. The script follows a [Path3D] at a set speed, starting after [member start_delay]
## counted from when it is armed (at once, or when a vehicle enters [member trigger]); it can
## pause once along the way, and loop. While nothing is in its way the agent moves exactly as
## scripted, so the same script always plays out the same way.
##
## With [member reactive] on, a [TrafficSensor] looks ahead along the path every tick. When
## something in the way forces it (the player's car, another road user, a pedestrian, an
## obstacle), the agent slows or stops by the Intelligent Driver Model, then accelerates back to
## its scripted speed once the way is clear. It reports what it does through [signal reacted], and
## [signal forced_to_brake] when it had to brake harder than [member hard_brake].
##
## Cars sit on the obstacle layer and pedestrians on the pedestrian layer and in the pedestrian
## group (see [Layers]), so the [ContactCheck] tells them apart. Without a
## [CollisionShape3D] child, it builds a box of [member body_size].

signal started
signal finished
## The agent changed what it is doing: [code]&"following"[/code] a slower leader,
## [code]&"stopped"[/code] behind one, or [code]&"resumed"[/code] its script; [param cause] is
## the body it reacts to, null on resuming.
signal reacted(kind: StringName, cause: Node3D)
## Something in the way forced a deceleration beyond [member hard_brake], metres per second
## squared.
signal forced_to_brake(cause: Node3D, deceleration: float)

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

@export_group("Reactions")
## Looks ahead and reacts to what is in the way; off, it plays its script whatever happens.
@export var reactive := true
## Acceleration back to the scripted speed, metres per second squared.
@export var max_accel := 2.0
## A comfortable deceleration, metres per second squared.
@export var comfort_decel := 3.0
## The hardest deceleration it can manage.
@export var max_decel := 8.0
## Deceleration beyond which braking counts as forced.
@export var hard_brake := 4.0
## Metres it keeps from a stopped leader.
@export var min_gap := 2.0
## Seconds of headway it keeps behind a moving leader once it has to follow one.
@export var time_headway := 1.5
@export_group("")

var state := State.WAITING
## Distance travelled along the path in the current lap, in metres.
var progress := 0.0
## The speed it moves at now, metres per second: the scripted speed unless it is reacting.
var current_speed := 0.0
## What it is reacting to, as in [signal reacted]; empty while it plays its script.
var reaction: StringName = &""
## What its sensor saw ahead this tick, or null.
var leader: TrafficSensor.Leader

var _sensor: TrafficSensor
var _braking_hard := false

var _armed := false
var _clock := 0.0
var _paused_for := 0.0
var _paused_this_lap := false
var _length := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	collision_layer = Layers.PEDESTRIAN if pedestrian else Layers.OBSTACLE
	collision_mask = 0
	if pedestrian:
		add_to_group(Layers.GROUP_PEDESTRIAN)
	if not _has_shape():
		BoxBody.build(self, body_size, colour)
	_sensor = TrafficSensor.new(self, body_size)
	if path and path.curve:
		_length = path.curve.get_baked_length()
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
	var remaining := offset - progress
	if remaining < 0.0:
		if not loop:
			return INF
		remaining += _length
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
				current_speed = speed
				started.emit()
		State.PAUSED:
			_paused_for += delta
			if _paused_for >= pause_time:
				state = State.MOVING
		State.MOVING:
			_advance(_drive(delta) * delta)


## The agent's facing on the ground, the direction it moves in.
func forward() -> Vector3:
	var f := -global_basis.z
	f.y = 0.0
	return f.normalized()


## The point of the path [param offset] metres along it, world space; past the end, the end, or
## round again on a looping path.
func path_point(offset: float) -> Vector3:
	if loop and _length > 0.0:
		offset = fposmod(offset, _length)
	return path.global_transform * path.curve.sample_baked(clampf(offset, 0.0, _length))


## Whether the agent has reached the end of its path for good.
func is_done() -> bool:
	return state == State.DONE


## The distance along the path of its point nearest [param point], world space; the offset to
## pass to [method time_to].
func offset_nearest(point: Vector3) -> float:
	return path.curve.get_closest_offset(path.to_local(point))


## This tick's speed: the script's, unless what is ahead forces a reaction.
func _drive(delta: float) -> float:
	if not reactive or _sensor == null:
		current_speed = speed
		return current_speed
	leader = _sensor.sense(get_world_3d().direct_space_state, _ahead())
	var v := current_speed
	var accel := max_accel if v < speed else 0.0
	var kind: StringName = &""
	# Once reacting, the model keeps control until the agent is back at its scripted speed with
	# nothing holding it back, so it neither creeps up on a leader nor lets go too early.
	if leader and (not reaction.is_empty() or _forced(leader, v)):
		var model := _idm(v, leader)
		if not reaction.is_empty() and v >= speed - 0.01 and model >= 0.0:
			model = 0.0
		else:
			accel = model
			kind = &"stopped" if v + accel * delta < 0.3 else &"following"
		if accel < -hard_brake and leader.body and not _braking_hard:
			_braking_hard = true
			forced_to_brake.emit(leader.body, -accel)
	if accel >= -hard_brake:
		_braking_hard = false
	current_speed = clampf(v + accel * delta, 0.0, speed)
	if leader and (leader.gap <= 0.05 or (kind == &"stopped" and absf(leader.speed) < 0.1)):
		# Behind something standing still the agent stands still too, rather than creeping up at
		# the model's crawl, and it never moves into what it already touches.
		current_speed = 0.0
		kind = &"stopped"
	if kind != reaction:
		reaction = kind
		reacted.emit(&"resumed" if kind.is_empty() else kind, leader.body if leader else null)
	return current_speed


## Whether [param ahead] forces a reaction at speed [param v]: it is within the gap kept at a
## reaction's headway, or closing so fast that keeping the script would need braking.
func _forced(ahead: TrafficSensor.Leader, v: float) -> bool:
	if ahead.gap <= min_gap + v * 0.5:
		return true
	var closing := v - ahead.speed
	if closing <= 0.0:
		return false
	return closing * closing / (2.0 * maxf(ahead.gap - min_gap, 0.01)) > 0.5


## The Intelligent Driver Model's acceleration behind [param ahead], towards the scripted speed.
func _idm(v: float, ahead: TrafficSensor.Leader) -> float:
	var closing := v - ahead.speed
	var wanted := min_gap + maxf(0.0, v * time_headway
		+ v * closing / (2.0 * sqrt(max_accel * comfort_decel)))
	var gap := maxf(ahead.gap, 0.05)
	var free := 1.0 - pow(v / maxf(speed, 0.1), 4.0)
	return maxf(max_accel * (free - (wanted / gap) * (wanted / gap)), -max_decel)


## The path ahead of the agent's front, as the sensor sweeps it.
func _ahead() -> PackedVector3Array:
	var points := PackedVector3Array()
	var front := progress + body_size.z * 0.5
	var look := speed * 3.0 + 5.0
	for i in TrafficSensor.SEGMENTS + 1:
		points.append(path_point(front + look * i / TrafficSensor.SEGMENTS))
	return points


func _advance(step: float) -> void:
	var length := _length
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
	var length := _length if _length > 0.0 else curve.get_baked_length()
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


func _get_configuration_warnings() -> PackedStringArray:
	if path == null:
		return ["Set the path the agent follows."]
	return []
