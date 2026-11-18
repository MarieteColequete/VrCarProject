class_name LightLogic
extends RefCounted
## Traffic lights as a pure phase machine: red, red and amber, green, amber, red. A cycling light
## loops through the phases on their timers; a light on approach holds its initial phase until the
## car enters its trigger zone, waits its delay, turns amber, and runs the phases once until it is
## green again, where it holds.


## The light system: advances every light by [param dt], with a [code]&"light_changed"[/code]
## event for each change of phase.
static func run(world: World, dt: float) -> Delta:
	var d := Delta.new()
	var s := world.store(Schema.LIGHT)
	if s == null:
		return d
	for row in s.size():
		var id := s.ids[row]
		var light := {}
		for column: StringName in s.columns:
			light[column] = s.columns[column][row]
		var trigger: int = light.trigger
		var triggered: bool = trigger != 0 and world.has(Schema.ZONE, trigger) \
			and world.get_value(Schema.ZONE, trigger, &"entered")
		var next := step(light, dt, triggered)
		d.write_all(Schema.LIGHT, id, next)
		if next.state != light.state:
			d.emit(WorldEvent.new(&"light_changed", id, {state = next.state}))
	return d


## The light [param light] (column name to value) after [param dt] seconds; [param triggered]
## when the car entered its trigger zone this tick.
static func step(light: Dictionary, dt: float, triggered: bool) -> Dictionary:
	var out := {clock = light.clock + dt, time_in_state = light.time_in_state + dt,
		state = light.state, holding = light.holding, triggered_at = light.triggered_at}
	if triggered and out.holding and out.triggered_at < 0.0:
		out.triggered_at = out.clock
	if out.holding:
		if out.triggered_at >= 0.0 and out.clock - out.triggered_at >= light.trigger_delay:
			out.holding = false
			out.state = TrafficLight.Light.AMBER
			out.time_in_state = 0.0
		return out
	if out.time_in_state >= duration(light, out.state):
		out.state = next_phase(out.state)
		out.time_in_state = 0.0
		if light.mode == TrafficLight.Mode.ON_APPROACH and out.state == TrafficLight.Light.GREEN:
			out.holding = true
			out.triggered_at = INF
	return out


## A new light's starting values from its timings and mode.
static func initial(light: Dictionary) -> Dictionary:
	return {state = light.initial, time_in_state = 0.0, clock = 0.0, triggered_at = -1.0,
		holding = light.mode == TrafficLight.Mode.ON_APPROACH}


static func is_red(state: int) -> bool:
	return state == TrafficLight.Light.RED or state == TrafficLight.Light.RED_AMBER


static func duration(light: Dictionary, state: int) -> float:
	match state:
		TrafficLight.Light.RED:
			return light.red_time
		TrafficLight.Light.RED_AMBER:
			return light.red_amber_time
		TrafficLight.Light.GREEN:
			return light.green_time
	return light.amber_time


static func next_phase(state: int) -> int:
	match state:
		TrafficLight.Light.RED:
			return TrafficLight.Light.RED_AMBER
		TrafficLight.Light.RED_AMBER:
			return TrafficLight.Light.GREEN
		TrafficLight.Light.GREEN:
			return TrafficLight.Light.AMBER
	return TrafficLight.Light.RED
