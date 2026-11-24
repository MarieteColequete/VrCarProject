@tool
class_name GpsRoute
extends Path3D
## The way a scenario wants the car to go, as the dashboard's GPS shows it ([CarTablet]): a curve
## along the road from the start to the goal, drawn with the Path3D editor in the scenario scene.
## It judges nothing; the checks do. With [member step] set it is that step's way, shown while the
## step is current; empty, it is the whole attempt's.

## The step this is the way for; empty for the whole attempt.
@export var step: ScenarioStep


## The curve's points in world space, every few metres along it.
func world_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	if curve == null or curve.point_count < 2:
		return out
	for point in curve.get_baked_points():
		out.append(global_transform * point)
	return out


func _get_configuration_warnings() -> PackedStringArray:
	if curve == null or curve.point_count < 2:
		return ["Draw the way with at least two points."]
	return []
