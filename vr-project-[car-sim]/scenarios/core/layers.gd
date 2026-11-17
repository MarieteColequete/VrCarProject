class_name Layers
extends RefCounted
## The physics layers and node groups the scenario framework agrees on. The layer bits match the
## names in [code]project.godot[/code]: 1 world, 2 vehicle, 3 obstacles, 4 pedestrians,
## 5 detection.

## The player's car body.
const VEHICLE := 1 << 1
## Parked cars and scripted vehicles.
const OBSTACLE := 1 << 2
## Scripted pedestrians.
const PEDESTRIAN := 1 << 3
## Zones and the car's contact hull; they detect, nothing collides with them.
const DETECTION := 1 << 4

## Scripted pedestrians also join this group, so contact with them reads as a pedestrian even
## through a child body.
const GROUP_PEDESTRIAN := &"pedestrian"
