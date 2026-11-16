class_name SpeedLimitCheck
extends Check
## A speed limit over a zone. An overspeed episode starts when the car exceeds the limit and ends
## when it slows below it, leaves the zone, or the attempt ends. An episode longer than
## [member grace_time] is one fault, serious when the highest excess reached
## [member serious_excess] of the limit, minor otherwise.

@export var zone: TriggerZone
@export var limit_kmh := 50.0
## Seconds over the limit before it counts.
@export var grace_time := 1.0
## Fraction of the limit above it that makes the fault serious (0.2 is 20 % over).
@export var serious_excess := 0.2
@export var minor_fault: FaultDef
@export var serious_fault: FaultDef

var _over_for := 0.0
var _peak_kmh := 0.0
var _peak_at := Vector3.ZERO


func _on_bound() -> void:
	zone.vehicle_exited.connect(func(p: VehicleProbe) -> void:
		if p == probe():
			_end_episode())


func _physics_process(delta: float) -> void:
	if not is_live() or not zone.contains(probe()):
		return
	var kmh := probe().speed_kmh()
	if kmh > limit_kmh:
		_over_for += delta
		if kmh > _peak_kmh:
			_peak_kmh = kmh
			_peak_at = probe().global_position
	else:
		_end_episode()


func finalize() -> void:
	_end_episode()


func _end_episode() -> void:
	if _over_for > grace_time and is_live():
		var serious := _peak_kmh >= limit_kmh * (1.0 + serious_excess)
		report(serious_fault if serious else minor_fault, _peak_at)
	_over_for = 0.0
	_peak_kmh = 0.0
