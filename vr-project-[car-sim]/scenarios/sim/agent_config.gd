class_name AgentConfig
extends RefCounted
## What a road user is and how it drives, as authored on its [ScriptedAgent] or given by a
## [TrafficSource]; never changed once baked, so the states of one road user share it.

var name: StringName
## Metres per second.
var speed := 1.4
var start_delay := 0.0
## The zone whose entry arms the start delay; 0 to start at once.
var trigger := 0
var loop := false
var pedestrian := false
var pause_at := -1.0
var pause_time := 0.0
var body_size := Vector3(1.8, 1.4, 4.2)
var colour := Color(0.85, 0.75, 0.2)
## The lanes to take where a lane offers a choice, in order.
var route := PackedInt64Array()
var route_seed := 0
var reactive := true
var max_accel := 2.0
var comfort_decel := 3.0
var max_decel := 8.0
var hard_brake := 4.0
var min_gap := 2.0
var time_headway := 1.5
var patience := 4.0
var change_time := 2.0
