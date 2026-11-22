class_name RouteTable
extends RefCounted
## The lanes as columns, one row (slot) per lane, built once from the world's [LaneData] and
## never changed: what road users read of a lane while they think, as plain arrays rather than
## shared objects. What a lane's rules say now (its light, its way, its crossings) changes every
## tick and lives apart, in the flags [LaneRules] evaluates.
##
## A lane's crossings and the lanes it gives way to are flattened: a lane's own run of them starts
## at its [code]*_first[/code] and holds [code]*_count[/code] entries.

## Metres between the curvature's samples.
const CURVATURE_STEP := 1.0

## Lane entity to its slot.
var slots := {}
var lane_ids := PackedInt64Array()
var is_lane := PackedByteArray()
var length := PackedFloat64Array()
var speed_limit := PackedFloat64Array()
var stop_at := PackedFloat64Array()
var safe_gap := PackedFloat64Array()
## The neighbour lanes' entities, or 0.
var left := PackedInt64Array()
var right := PackedInt64Array()
## The light entity at the stop line, or 0.
var light := PackedInt64Array()
## Per slot its [Curve3D], baked on the main thread before any thread samples it, and its
## transform and inverse, as [Transform3D] values.
var curves: Array = []
var transforms: Array = []
var inverses: Array = []
## Per slot, the lane's curvature (1/m, left positive) every [constant CURVATURE_STEP] metres
## along it, as a [PackedFloat64Array]; empty for a lane without a curve.
var curvature: Array = []
## Where traffic waits before each crossing.
var crossing_first := PackedInt32Array()
var crossing_count := PackedInt32Array()
var crossing_stops := PackedFloat64Array()
## Each lane the slot gives way to, and the offset on that lane of the slot's stop line: where
## the two meet.
var give_way_first := PackedInt32Array()
var give_way_count := PackedInt32Array()
var give_way_lane := PackedInt64Array()
var give_way_at := PackedFloat64Array()


## The table of [param lanes] (entity to [LaneData]), slots in ascending entity order.
static func of(lanes: Dictionary) -> RouteTable:
	var t := RouteTable.new()
	var ids := PackedInt64Array(lanes.keys())
	ids.sort()
	for id in ids:
		var lane: LaneData = lanes[id]
		t.slots[id] = t.lane_ids.size()
		t.lane_ids.append(id)
		t.is_lane.append(1 if lane.is_lane else 0)
		t.length.append(lane.length)
		t.speed_limit.append(lane.speed_limit)
		t.stop_at.append(lane.stop_at)
		t.safe_gap.append(lane.safe_gap)
		t.left.append(lane.left)
		t.right.append(lane.right)
		t.light.append(lane.light)
		if lane.curve:
			lane.curve.get_baked_length()
		t.curves.append(lane.curve)
		t.transforms.append(lane.transform)
		t.inverses.append(lane.inverse)
		t.curvature.append(curvature_of(lane))
		t.crossing_first.append(t.crossing_stops.size())
		for crossing in lane.crossings:
			t.crossing_stops.append(crossing.stop)
		t.crossing_count.append(lane.crossings.size())
		t.give_way_first.append(t.give_way_lane.size())
		var count := 0
		if lane.is_lane and lane.curve:
			var meeting := lane.point_at(lane.stop_at)
			for priority_id in lane.give_way_to:
				var priority: LaneData = lanes.get(priority_id)
				if priority == null or priority.curve == null:
					continue
				t.give_way_lane.append(priority_id)
				t.give_way_at.append(priority.project(meeting).x)
				count += 1
		t.give_way_count.append(count)
	return t


## The curvature of [param lane] every [constant CURVATURE_STEP] metres, 1/m, left positive: the
## turn of its heading on the ground over the distance either side.
static func curvature_of(lane: LaneData) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	if lane.curve == null or lane.length <= 0.0:
		return out
	var count := int(ceil(lane.length / CURVATURE_STEP)) + 1
	var headings := PackedFloat64Array()
	for k in count + 2:
		var at := (k - 1) * CURVATURE_STEP
		var ahead := lane.point_at(at + 0.5) - lane.point_at(at - 0.5)
		headings.append(atan2(-ahead.x, -ahead.z) if Vector2(ahead.x, ahead.z).length() > 0.001
			else (headings[k - 1] if k > 0 else 0.0))
	for k in count:
		var turn := wrapf(headings[k + 2] - headings[k], -PI, PI)
		out.append(turn / (2.0 * CURVATURE_STEP))
	# At the ends the samples either side are clamped onto the lane, so take the neighbours'.
	if count > 2:
		out[0] = out[1]
		out[count - 1] = out[count - 2]
	return out


func size() -> int:
	return lane_ids.size()


## The table of the world's lanes: built once, and again only when lanes are added.
static func of_world(world: World) -> RouteTable:
	var lanes: Dictionary = world.resources.get(Schema.LANES, {})
	var cached: Array = world.memo.get(&"routes", [])
	if not cached.is_empty() and cached[0] == lanes.size():
		return cached[1]
	var t := of(lanes)
	world.memo[&"routes"] = [lanes.size(), t]
	return t
