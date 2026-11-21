class_name AgentSpawner
extends Node3D
## Fills parking bays with parked cars, chosen from a seed: the same seed always takes the same
## bays, so an attempt can be replayed, and a new seed gives a new car park. Reserved bays and
## bays already marked occupied are never chosen, and at least [member keep_free] bays stay free.
## When the scenario loads, a [Bake] marks each chosen bay occupied, which the parking rules read,
## and adds a parked car there as an obstacle; the obstacle view draws it.

## The seed; the same seed takes the same bays.
@export var random_seed := 1
@export var bays: Array[ParkingBay] = []
## Fraction of the eligible bays to fill.
@export_range(0.0, 1.0) var occupancy := 0.5
@export var keep_free := 1
## The parked car; empty for a plain box of a car's size.
@export var parked_car_scene: PackedScene
## The colour of a parked car without a model.
@export var colour := Color(0.3, 0.35, 0.6)

## A parked car's box, metres.
const CAR_SIZE := Vector3(1.8, 1.4, 4.2)

var _cars_made := 0

## The bays to fill, from [member random_seed]: [param eligible] is whether each of [member bays]
## may be chosen (neither reserved nor occupied). Pure: the same seed gives the same bays.
func choose(eligible: Array[bool]) -> Array[int]:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var order: Array[int] = []
	for i in bays.size():
		if eligible[i]:
			order.append(i)
	# Fisher-Yates with the seeded generator, so the order does not depend on the engine's.
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := order[i]
		order[i] = order[j]
		order[j] = swap
	var count := clampi(roundi(occupancy * order.size()), 0, maxi(order.size() - keep_free, 0))
	return order.slice(0, count)


## A parked car's body for a bay: the scene, or a box of a car's size showing one of the kit's
## cars, each call the next. The obstacle view places it.
func make_car() -> Node3D:
	if parked_car_scene:
		return parked_car_scene.instantiate()
	var body := StaticBody3D.new()
	BodyType.of(&"vehicle").apply(body)
	BoxBody.build(body, CAR_SIZE, colour, KitModels.car(_cars_made))
	_cars_made += 1
	return body
