@tool
class_name TrafficSource
extends Node3D
## A steady flow of road users onto a [TrafficLane]: up to [member count] cars, the first after
## [member start_delay] and the rest at headways drawn between [member min_headway] and
## [member max_headway] seconds, each only once the lane's entry is clear. Headways and each car's
## route come from [member random_seed], so the same seed always gives the same traffic. The cars
## are reactive [ScriptedAgent]s, added as children of the source and named after it.

## The lane the cars enter at its start.
@export var lane: TrafficLane
@export var count := 5
@export var start_delay := 0.0
@export var min_headway := 3.0
@export var max_headway := 6.0
## The cars' scripted speed, metres per second; the lane's limit still applies.
@export var speed := 10.0
@export var random_seed := 1
## The lanes the cars take where a lane offers a choice; others are picked per car from the seed.
@export var route: Array[TrafficLane] = []
## Metres from the lane's start that must be free of other road users before a car enters; at
## least the room a car needs to stop comfortably from [member speed].
@export var entry_gap := 6.0
@export var colours: Array[Color] = [Color(0.85, 0.75, 0.2), Color(0.3, 0.55, 0.85),
	Color(0.75, 0.75, 0.78), Color(0.2, 0.6, 0.35), Color(0.55, 0.25, 0.6)]

## The cars spawned so far, in order.
var spawned: Array[ScriptedAgent] = []

var _rng := RandomNumberGenerator.new()
var _clock := 0.0
var _next_at := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	_rng.seed = random_seed
	_next_at = start_delay


func _physics_process(delta: float) -> void:
	_clock += delta
	if lane == null or spawned.size() >= count or _clock < _next_at or not entry_is_clear():
		return
	_spawn()
	_next_at = _clock + _rng.randf_range(min_headway, max_headway)


## Whether no road user is within the entry gap of the lane's start: [member entry_gap], or the
## room to stop comfortably (3 m/s²) from [member speed] plus 2 m, whichever is longer.
func entry_is_clear() -> bool:
	var needed := maxf(entry_gap, speed * speed / 6.0 + 2.0)
	for user: Node3D in get_tree().get_nodes_in_group(Layers.GROUP_ROAD_USER):
		if user.get(&"path") == lane:
			var length: float = user.get(&"body_size").z
			if float(user.get(&"progress")) < needed + length:
				return false
	return true


func _spawn() -> void:
	var car := ScriptedAgent.new()
	car.name = "%s%d" % [name, spawned.size() + 1]
	car.path = lane
	car.speed = speed
	car.route = route
	car.route_seed = _rng.randi()
	if not colours.is_empty():
		car.colour = colours[spawned.size() % colours.size()]
	# Placed at the lane's start before entering the tree, so its body never stands anywhere else.
	car.transform = global_transform.affine_inverse() * Transform3D(Basis(), lane.point_at(0.0))
	add_child(car)
	spawned.append(car)


func _get_configuration_warnings() -> PackedStringArray:
	if lane == null:
		return ["Set the lane the cars enter."]
	return []
