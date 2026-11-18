@tool
class_name ScriptedAgent
extends Node3D
## Another road user, as authored in a scenario scene: a car or a pedestrian that plays its script
## by the book until it is forced to react. The script follows a [Path3D] at a set speed, starting
## after [member start_delay] counted from when it is armed (at once, or when the car enters
## [member trigger]); it can pause once along the way, and loop.
##
## When the scenario loads, a [Bake] turns the node into a road user entity ([AgentConfig] and
## [AgentState]) and frees it; [AgentLogic] drives it from then on, and the traffic view draws it
## and gives it a body the player's car collides with. With [member reactive] on, it reacts to what
## is in its way and keeps its lane's rules; see [AgentLogic].

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
## On lanes: the lanes to take where a lane offers a choice, in order; others are picked from
## [member route_seed].
@export var route: Array[TrafficLane] = []
@export var route_seed := 0

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
## Seconds stuck behind something that is not traffic before it changes lanes round it.
@export var patience := 4.0
## Seconds a lane change takes.
@export var change_time := 2.0
@export_group("")

## What the bake reads: the authored settings as an [AgentConfig], node references resolved
## through [param bake].
func config(bake: Bake) -> AgentConfig:
	var c := AgentConfig.new()
	c.name = name
	c.speed = speed
	c.start_delay = start_delay
	c.trigger = bake.id_of(trigger)
	c.loop = loop
	c.pedestrian = pedestrian
	c.pause_at = pause_at
	c.pause_time = pause_time
	c.body_size = body_size
	c.colour = colour
	c.route = bake.lanes_of(route)
	c.route_seed = route_seed
	c.reactive = reactive
	c.max_accel = max_accel
	c.comfort_decel = comfort_decel
	c.max_decel = max_decel
	c.hard_brake = hard_brake
	c.min_gap = min_gap
	c.time_headway = time_headway
	c.patience = patience
	c.change_time = change_time
	return c


func _get_configuration_warnings() -> PackedStringArray:
	if path == null:
		return ["Set the path the agent follows."]
	return []
