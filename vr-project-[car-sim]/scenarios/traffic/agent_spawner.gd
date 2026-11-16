class_name AgentSpawner
extends Node3D
## Fills parking bays with parked cars, chosen from a seed: the same seed always takes the same
## bays, so an attempt can be replayed, and a new seed gives a new car park. Reserved bays and
## bays already marked occupied are never chosen, and at least [member keep_free] bays stay free.
## Each chosen bay is marked occupied, which the parking checks read.

## The seed; the same seed takes the same bays.
@export var random_seed := 1
@export var bays: Array[ParkingBay] = []
## Fraction of the eligible bays to fill.
@export_range(0.0, 1.0) var occupancy := 0.5
@export var keep_free := 1
## The parked car; empty for a plain box of a car's size.
@export var parked_car_scene: PackedScene
@export var colour := Color(0.3, 0.35, 0.6)

## The bays this spawner filled.
var filled: Array[ParkingBay] = []


func _ready() -> void:
	spawn()


func spawn() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	var eligible: Array[ParkingBay] = []
	for bay in bays:
		if not bay.reserved and not bay.occupied:
			eligible.append(bay)
	# Fisher-Yates with the seeded generator, so the order does not depend on the engine's.
	for i in range(eligible.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap := eligible[i]
		eligible[i] = eligible[j]
		eligible[j] = swap
	var count := clampi(roundi(occupancy * eligible.size()), 0, maxi(eligible.size() - keep_free, 0))
	for i in count:
		var bay := eligible[i]
		bay.occupied = true
		filled.append(bay)
		_park_in(bay)


func _park_in(bay: ParkingBay) -> void:
	var car: Node3D
	if parked_car_scene:
		car = parked_car_scene.instantiate()
	else:
		car = _box_car()
	add_child(car)
	car.global_transform = bay.global_transform


func _box_car() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = VehicleProbe.OBSTACLE_LAYER
	body.collision_mask = 0
	var size := Vector3(1.8, 1.4, 4.2)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y * 0.5
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	box_mesh.material = material
	mesh.mesh = box_mesh
	mesh.position.y = size.y * 0.5
	body.add_child(mesh)
	return body
