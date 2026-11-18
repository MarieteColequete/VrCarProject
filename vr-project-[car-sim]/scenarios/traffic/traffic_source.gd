@tool
class_name TrafficSource
extends Node3D
## A steady flow of road users onto a [TrafficLane]: up to [member count] cars, the first after
## [member start_delay] and the rest at headways drawn between [member min_headway] and
## [member max_headway] seconds, each only once the lane's entry is clear. Headways and each car's
## route come from [member random_seed], so the same seed always gives the same traffic. When the
## scenario loads, a [Bake] turns the source into a source entity that [SourceLogic] runs; the cars
## are reactive road users named after the source.

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

## The source entity's columns, node references resolved through [param bake].
func values(bake: Bake) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	return {name = name, lane = bake.lane_of(lane), count = count, start_delay = start_delay,
		min_headway = min_headway, max_headway = max_headway, speed = speed,
		route = Array(bake.lanes_of(route)), entry_gap = entry_gap, colours = Array(colours),
		rng_state = rng.state, next_at = start_delay}


func _get_configuration_warnings() -> PackedStringArray:
	if lane == null:
		return ["Set the lane the cars enter."]
	return []
