@tool
class_name RoadSign
extends Node3D
## A road sign on a pole, its face towards +Z, to the traffic coming down -Z. It is scenery: the
## rule it shows is a lane's or a check's, so a speed limit sign beside a 30 zone goes with a
## [SpeedLimitCheck] or the lanes' speed limit.

enum Kind { STOP, GIVE_WAY, SPEED_LIMIT, NO_ENTRY, PEDESTRIAN_CROSSING, ROUNDABOUT, NO_PARKING,
	ONE_WAY }

@export var kind := Kind.STOP:
	set(value):
		kind = value
		_queue_rebuild()
## The number a speed limit sign shows, km/h.
@export var value := 30:
	set(v):
		value = v
		_queue_rebuild()
## Height of the plate's centre, metres.
@export var height := 2.4:
	set(v):
		height = v
		_queue_rebuild()

const RED := Color(0.8, 0.05, 0.05)
const BLUE := Color(0.1, 0.3, 0.75)
const WHITE := Color(0.95, 0.95, 0.95)
const METAL := Color(0.6, 0.6, 0.62)
## Per kind: the plate's sides (0 for round), its colour, its text, and the text's colour.
const LOOKS := {
	Kind.STOP: [8, RED, "STOP", WHITE],
	Kind.GIVE_WAY: [3, WHITE, "GIVE\nWAY", RED],
	Kind.SPEED_LIMIT: [0, WHITE, "", Color.BLACK],
	Kind.NO_ENTRY: [0, RED, "", WHITE],
	Kind.PEDESTRIAN_CROSSING: [4, BLUE, "ZEBRA", WHITE],
	Kind.ROUNDABOUT: [0, BLUE, "O", WHITE],
	Kind.NO_PARKING: [0, BLUE, "P", RED],
	Kind.ONE_WAY: [4, BLUE, "ONE\nWAY", WHITE],
}

var _parts: Node3D
var _rebuild_queued := false


func _ready() -> void:
	rebuild()


func rebuild() -> void:
	_rebuild_queued = false
	if _parts:
		_parts.queue_free()
	_parts = Node3D.new()
	add_child(_parts, false, INTERNAL_MODE_BACK)
	var pole := CylinderMesh.new()
	pole.top_radius = 0.04
	pole.bottom_radius = 0.04
	pole.height = height
	_part(pole, METAL, Transform3D(Basis.IDENTITY, Vector3(0, height / 2.0, 0)))
	var look: Array = LOOKS[kind]
	var plate := CylinderMesh.new()
	plate.top_radius = 0.4
	plate.bottom_radius = 0.4
	plate.height = 0.03
	plate.radial_segments = look[0] if look[0] > 0 else 32
	# The cylinder's axis turned to face +Z; a triangle and a square are turned to sit flat.
	var turn := Basis(Vector3.RIGHT, PI / 2.0)
	if look[0] == 3:
		turn = turn * Basis(Vector3.UP, PI / 2.0)
	elif look[0] == 4:
		turn = turn * Basis(Vector3.UP, PI / 4.0)
	_part(plate, look[1], Transform3D(turn, Vector3(0, height, 0.05)))
	var text: String = str(value) if kind == Kind.SPEED_LIMIT else look[2]
	if kind == Kind.SPEED_LIMIT:
		var ring := CylinderMesh.new()
		ring.top_radius = 0.42
		ring.bottom_radius = 0.42
		ring.height = 0.02
		_part(ring, RED, Transform3D(turn, Vector3(0, height, 0.035)))
	if kind == Kind.NO_ENTRY:
		var bar := BoxMesh.new()
		bar.size = Vector3(0.55, 0.12, 0.02)
		_part(bar, WHITE, Transform3D(Basis.IDENTITY, Vector3(0, height, 0.07)))
	var label := Label3D.new()
	label.text = text
	label.font_size = 48 if text.length() > 2 else 72
	label.modulate = look[3]
	label.outline_size = 0
	label.position = Vector3(0, height, 0.07)
	_parts.add_child(label)


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func _part(mesh: Mesh, colour: Color, at: Transform3D) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = colour
	part.material_override = material
	part.transform = at
	_parts.add_child(part)
