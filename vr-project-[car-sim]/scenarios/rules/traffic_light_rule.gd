class_name TrafficLightRule
extends RefCounted
## A traffic light's stop line: entering the line zone on red is running a red light; on amber it
## is a fault only when the car could have stopped when the light turned amber, its front at least
## its stopping distance, [code]v * reaction_time + v^2 / (2 * deceleration)[/code], from the line.


static func initial(_p: Dictionary) -> Dictionary:
	return {could_stop = false}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var n := s.duplicate()
	var r := RuleResult.new(n)
	var car := f.car
	var changed := f.light_changed(p.light)
	if changed == TrafficLight.Light.AMBER and live:
		var distance := distance_to_line(p, car)
		n.could_stop = car.travels_along(p.direction) and distance > 0.0 \
			and distance >= stopping_distance(p, maxf(car.speed, 0.0))
	elif changed == TrafficLight.Light.GREEN:
		n.could_stop = false
	if live and f.entered(p.line) and car.travels_along(p.direction):
		var state := f.light_state(p.light)
		if LightLogic.is_red(state):
			r.report_here(p.red_fault, f)
		elif state == TrafficLight.Light.AMBER and n.could_stop:
			r.report_here(p.amber_fault, f)
	return r


## Metres from the car's front to the line along the direction of traffic; negative once past.
static func distance_to_line(p: Dictionary, car: CarState) -> float:
	var front := car.position + car.forward * car.body_length * 0.5
	return (p.position - front).dot(p.direction)


static func stopping_distance(p: Dictionary, speed: float) -> float:
	return speed * p.reaction_time + speed * speed / (2.0 * p.deceleration)
