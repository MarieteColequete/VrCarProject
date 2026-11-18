class_name Layers
extends RefCounted
## The physics layers the scenario framework agrees on, for the bodies the player's car collides
## with. The bits match the names in [code]project.godot[/code]: 1 world, 2 vehicle, 3 obstacles,
## 4 pedestrians. Detection does not use physics; it is geometry ([Detection]).

## The player's car body.
const VEHICLE := 1 << 1
## Parked cars and scripted vehicles.
const OBSTACLE := 1 << 2
## Scripted pedestrians.
const PEDESTRIAN := 1 << 3
