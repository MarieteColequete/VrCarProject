class_name SceneViews
extends RefCounted
## The views of what the scenario scene already draws: the lamps of its traffic lights, lit from
## the world's light phases, and the parked cars its spawners chose, placed once.


## Lights every light's lamps for its phase in the world.
static func draw_lights(world: World, lights: Dictionary) -> void:
	var s := world.store(Schema.LIGHT)
	if s == null:
		return
	for row in s.size():
		var light := lights.get(s.ids[row]) as TrafficLight
		if light and is_instance_valid(light):
			light.show_state(s.column(&"state")[row])


## Places a parked car body for every obstacle a spawner added, under its spawner.
static func place_parked_cars(world: World, spawners: Dictionary) -> void:
	var s := world.store(Schema.OBSTACLE)
	if s == null:
		return
	for id: int in spawners:
		var spawner := spawners[id] as AgentSpawner
		if spawner == null or not s.has(id):
			continue
		var car := spawner.make_car()
		spawner.add_child(car)
		# The obstacle's box stands on the bay; the car's origin is the bay's.
		car.global_transform = (s.get_value(id, &"transform") as Transform3D).translated_local(
			Vector3(0, -0.7, 0))
		car.reset_physics_interpolation()
