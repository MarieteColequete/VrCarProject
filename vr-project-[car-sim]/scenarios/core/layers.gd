class_name Layers
extends RefCounted
## The physics layers the scenario framework agrees on, one per [BodyType]. The bits match the
## names in [code]project.godot[/code]: 1 world, 2 vehicle, 3 obstacles, 4 pedestrians,
## 5 pavement, 6 traffic. Detection does not use physics; it is geometry ([Detection]).

## The ground, and anything flat to drive on.
const WORLD := 1 << 0
## The player's car body.
const VEHICLE := 1 << 1
## Static obstacles: houses, poles, props, fences.
const OBSTACLE := 1 << 2
## Scripted pedestrians.
const PEDESTRIAN := 1 << 3
## Kerbs and pavements: they stop the car's tyres, and are judged by the kerb lines.
const PAVEMENT := 1 << 4
## Other vehicles: parked cars and road users.
const TRAFFIC := 1 << 5
## The layers whose boxes the bake turns into obstacle entities, for road users to see and
## [ContactCheck] to judge.
const JUDGED := OBSTACLE | PEDESTRIAN | TRAFFIC

## Visual layers, for what each camera draws: the driver's hands, which the mirrors leave out,
## what only the spectator's window shows, which the headset leaves out, and the mirrors' glass.
const HANDS_VISUAL := 1 << 18
const SPECTATOR_VISUAL := 1 << 19
## The mirrors' glass, which no mirror shows: a mirror drawing its own picture would read the
## screen it draws into.
const MIRROR_VISUAL := 1 << 17
