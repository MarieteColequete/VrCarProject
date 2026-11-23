@tool
class_name MapPalette
extends RefCounted
## The Map Kit's palette: each piece placed by clicking in the 3D view, with the function that
## builds it.

const ICONS := "res://addons/map_kit/icons/"
## What each terrain shape does, by its kind's name as the palette shows it.
const SHAPE_NOTES := {
	"Hill": "A rise in the land, full within its radius, easing out over its falloff.",
	"Valley": "A hollow in the land, full within its radius, easing out over its falloff.",
	"Ramp": "A slope over its rectangle, from the node's height at its +Z end to its height "
		+ "above that at its -Z end.",
	"Plateau": "Flat land at its height above the node within its radius, easing out over its "
		+ "falloff."}


## The palette, in the order the dock lists it.
static func pieces() -> Array[MapKitTools.Piece]:
	var out: Array[MapKitTools.Piece] = []
	var road := MapKitTools.Piece.new("Road", "Roads", "Roads", func() -> Node3D: return road(false),
		_icon("road"), "A two-way road along a curve; shape it, then generate its lanes.")
	var one_way := MapKitTools.Piece.new("One-way road", "Roads", "Roads", func() -> Node3D: return road(true),
		_icon("one_way_road"), "A road whose lanes all run along its curve.")
	var crossroads := MapKitTools.Piece.new("Crossroads", "Roads", "Roads",
		func() -> Node3D: return junction(RoadJunction.Shape.CROSSROADS), _icon("crossroads"),
		"A junction of four arms.")
	var t_junction := MapKitTools.Piece.new("T junction", "Roads", "Roads",
		func() -> Node3D: return junction(RoadJunction.Shape.T), _icon("t_junction"),
		"A junction of three arms.")
	for piece in [road, one_way, crossroads, t_junction]:
		piece.joins_roads = true
		out.append(piece)
	out.append(MapKitTools.Piece.new("Lane", "Lanes and markings", "Lanes", _lane, _icon("lane"),
		"A lane road users drive along, drawn in their direction of travel."))
	var markings := {"Solid line": RoadMarking.Kind.SOLID, "Dashed line": RoadMarking.Kind.DASHED,
		"Double solid line": RoadMarking.Kind.DOUBLE_SOLID, "Stop line": RoadMarking.Kind.STOP_LINE,
		"Give way line": RoadMarking.Kind.GIVE_WAY_LINE, "Zebra": RoadMarking.Kind.ZEBRA,
		"No-parking line": RoadMarking.Kind.NO_PARKING, "Kerb": RoadMarking.Kind.KERB}
	for label: String in markings:
		var kind: int = markings[label]
		out.append(MapKitTools.Piece.new(label, "Lanes and markings", "Markings",
			func() -> Node3D: return _marking(kind), _icon("marking"),
			"A %s painted along a curve." % label.to_lower()))
	out.append(MapKitTools.Piece.new("Traffic light", "Traffic", "Traffic", _light, _icon("traffic_light"),
		"A light; point lanes at it to make their traffic obey it."))
	out.append(MapKitTools.Piece.new("Traffic source", "Traffic", "Traffic", _source, _icon("traffic_source"),
		"Sends road users down its lanes."))
	out.append(MapKitTools.Piece.new("Checkpoint", "Traffic", "Traffic", _checkpoint, _icon("checkpoint"),
		"A point road users drive to; pair it with a car under Road users."))
	for kind: int in RoadSign.Kind.values():
		var key: String = RoadSign.Kind.keys()[kind]
		out.append(MapKitTools.Piece.new(sentence(key), "Signs", "Signs", func() -> Node3D: return _sign(kind),
			_icon("sign_" + key.to_lower()), "A %s sign; scenery only." % sentence(key).to_lower()))
	for label: String in SHAPE_NOTES:
		var kind: int = TerrainShape.Kind[label.to_upper()]
		out.append(MapKitTools.Piece.new(label, "Terrain", "", func() -> Node3D: return _terrain_shape(kind),
			_icon("terrain_" + label.to_lower()), SHAPE_NOTES[label] + " Shapes the map's terrain."))
	out.append(MapKitTools.Piece.new("Spawn", "Zones and places", "", spawn, _icon("spawn"),
		"Where the car may start, facing the arrow."))
	out.append(MapKitTools.Piece.new("Trigger zone", "Zones and places", "Zones",
		func() -> Node3D: return _zone(TriggerZone.new(), "TriggerZone"), _icon("zone"),
		"A box that starts lights and road users when the car enters it."))
	out.append(MapKitTools.Piece.new("No-parking zone", "Zones and places", "Zones",
		func() -> Node3D: return _zone(NoParkingZone.new(), "NoParkingZone"),
		_icon("no_parking_zone"), "A box the car must not stop in."))
	out.append(MapKitTools.Piece.new("Crossing area", "Zones and places", "Zones", _crossing,
		_icon("crossing"), "A pedestrian crossing: its zone, and who walks over it."))
	out.append(MapKitTools.Piece.new("Parking bay", "Zones and places", "Zones", _bay, _icon("parking_bay"),
		"A bay the car can park in."))
	return out


## [param key], an enum key such as [code]PARKED_CAR[/code], in sentence case: "Parked car".
static func sentence(key: String) -> String:
	var words := key.to_lower().replace("_", " ")
	return words.left(1).to_upper() + words.substr(1)


static func _icon(icon_name: String) -> String:
	return ICONS + icon_name + ".svg"


static func road(one_way: bool) -> RoadSegment:
	var road := RoadSegment.new()
	road.name = "OneWayRoad" if one_way else "Road"
	road.one_way = one_way
	road.curve = MapKitTools.straight(20.0)
	return road


static func junction(shape: RoadJunction.Shape) -> Node3D:
	var junction := RoadJunction.new()
	junction.name = "Crossroads" if shape == RoadJunction.Shape.CROSSROADS else "TJunction"
	junction.shape = shape
	return junction


static func _lane() -> Node3D:
	var lane := TrafficLane.new()
	lane.name = "Lane"
	lane.curve = MapKitTools.straight(20.0)
	return lane


static func _marking(kind: RoadMarking.Kind) -> Node3D:
	var marking := RoadMarking.new()
	marking.name = String(RoadMarking.Kind.keys()[kind]).to_pascal_case()
	marking.kind = kind
	if kind in [RoadMarking.Kind.STOP_LINE, RoadMarking.Kind.GIVE_WAY_LINE, RoadMarking.Kind.ZEBRA]:
		marking.curve = Curve3D.new()
		marking.curve.add_point(Vector3(-1.75, 0, 0))
		marking.curve.add_point(Vector3(1.75, 0, 0))
		marking.width = 3.0 if kind == RoadMarking.Kind.ZEBRA else 0.3
	else:
		marking.curve = MapKitTools.straight(20.0)
	return marking


static func _terrain_shape(kind: TerrainShape.Kind) -> Node3D:
	var shape := TerrainShape.new()
	shape.name = String(TerrainShape.Kind.keys()[kind]).to_pascal_case()
	shape.kind = kind
	return shape


static func _light() -> Node3D:
	var light := TrafficLight.new()
	light.name = "TrafficLight"
	return light


static func _source() -> Node3D:
	var source := TrafficSource.new()
	source.name = "TrafficSource"
	return source


static func _sign(kind: RoadSign.Kind) -> Node3D:
	var road_sign := RoadSign.new()
	road_sign.name = String(RoadSign.Kind.keys()[kind]).to_pascal_case() + "Sign"
	road_sign.kind = kind
	return road_sign


static func _checkpoint() -> Node3D:
	var checkpoint := Checkpoint.new()
	checkpoint.name = "Checkpoint"
	return checkpoint


static func spawn() -> Node3D:
	var spawn := MapSpawn.new()
	spawn.name = "Spawn"
	return spawn


static func _zone(zone: TriggerZone, zone_name: String) -> Node3D:
	zone.name = zone_name
	zone.position.y = 1.5
	zone.add_child(box(Vector3(4, 3, 4)))
	return zone


static func box(size: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	return shape


static func _crossing() -> Node3D:
	var crossing := Crossing.new()
	crossing.name = "Crossing"
	var zone := _zone(TriggerZone.new(), "Zone") as TriggerZone
	(zone.get_child(0) as CollisionShape3D).shape.size = Vector3(7, 3, 3)
	crossing.add_child(zone)
	crossing.zone = zone
	return crossing


static func _bay() -> Node3D:
	var bay := ParkingBay.new()
	bay.name = "ParkingBay"
	return bay
