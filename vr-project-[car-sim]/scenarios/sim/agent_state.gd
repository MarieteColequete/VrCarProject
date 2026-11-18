class_name AgentState
extends RefCounted
## A road user in one tick, as a value: [AgentLogic] returns a new state rather than changing
## this one, so a state read by a thread or held by a view stays what it was.

enum State { WAITING, MOVING, PAUSED, DONE }

var config: AgentConfig
var state := State.WAITING
## Distance along the current path in this lap, metres.
var progress := 0.0
## The speed it moves at, metres per second: the scripted speed unless it reacts.
var current_speed := 0.0
## What it reacts to, as in its [code]&"reacted"[/code] events; empty while it plays its script.
var reaction: StringName = &""
## The lane entity it is on, its length, and the lane it continues onto (0 for none).
var lane := 0
var length := 0.0
var upcoming := 0
## The generator of its route choices, as its state.
var rng_state := 0
## It has committed to crossing the current lane's stop line.
var committed := false
var blocked_for := 0.0
## The offset from the lane during a lane change, and the seconds left until it fades out.
var shift := Vector3.ZERO
var shift_left := 0.0
var armed := false
var clock := 0.0
var paused_for := 0.0
var paused_this_lap := false
var braking_hard := false
## Where it stands and which way it faces.
var transform := Transform3D()
## It jumped this tick (spawned, or wrapped round a loop), so a view draws it there at once.
var jumped := false
## What its sensor saw ahead, the entity, or 0.
var leader := 0


func copy() -> AgentState:
	var c := AgentState.new()
	copy_into(c)
	return c


## Writes this state's values into [param c], a state not yet seen by anyone, such as one made on
## the main thread for a worker to fill; its jumped flag starts clear.
func copy_into(c: AgentState) -> void:
	c.config = config
	c.state = state
	c.progress = progress
	c.current_speed = current_speed
	c.reaction = reaction
	c.lane = lane
	c.length = length
	c.upcoming = upcoming
	c.rng_state = rng_state
	c.committed = committed
	c.blocked_for = blocked_for
	c.shift = shift
	c.shift_left = shift_left
	c.armed = armed
	c.clock = clock
	c.paused_for = paused_for
	c.paused_this_lap = paused_this_lap
	c.braking_hard = braking_hard
	c.transform = transform
	c.jumped = false
	c.leader = leader


func position() -> Vector3:
	return transform.origin


## Facing on the ground, normalised.
func forward() -> Vector3:
	var f := -transform.basis.z
	f.y = 0.0
	return f.normalized()


func is_done() -> bool:
	return state == State.DONE
