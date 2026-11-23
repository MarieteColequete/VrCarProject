class_name PlayerCarModel
extends Node3D
## The player's car as drawn: "Kiri '86 - Low poly model" by Daniel Zhabotinsky (CC BY 4.0, see
## [code]assets/sketchfab/kiri86/[/code]), a fictional 80s compact with a modelled cockpit. It is
## scaled so its wheelbase is the [VehicleProbe]'s and turned to face -Z, its wheels centred on the
## car's origin, standing on the ground. [method drive] moves its live parts: the wheels roll with
## the speed, the front wheels and the steering wheel turn with the steering, and the blinkers,
## brake, reverse, and headlights glow with the car's state. Nothing here takes part in the
## simulation.

const FOLDER := "res://assets/sketchfab/kiri86/"
const MODEL := FOLDER + "kiri86.fbx"
const TEXTURES := FOLDER + "textures/"
## The cabin's materials, CC0 sets from ambientCG, as downloaded but for the carpet's colour,
## made grey by tools/cabin_textures.gd.
const CABIN_FOLDER := "res://assets/ambientcg/"
## How far the front wheels turn at full steering, radians.
const WHEEL_LOCK := deg_to_rad(32.0)
## How far the steering wheel turns at full steering, radians.
const STEERING_LOCK := deg_to_rad(150.0)
const BLINKER := Color(1.0, 0.55, 0.05)
const BRAKE := Color(1.0, 0.05, 0.03)
const REVERSE := Color(1.0, 1.0, 0.95)
const HEADLIGHT := Color(1.0, 0.95, 0.8)
const GLOW := 4.0
## The headlamps' beams: how far they reach, metres, their half-angle, degrees, their brightness,
## and how far they dip below level, degrees.
const BEAM_RANGE := 40.0
const BEAM_ANGLE := 25.0
const BEAM_ENERGY := 3.0
const BEAM_DIP := 3.0
## How far the body leans for each metre per second squared: pitching under acceleration and
## braking, rolling out of a turn, radians; and the most it leans.
const PITCH_PER := 0.004
const ROLL_PER := 0.006
const LEAN_LIMIT := 0.06
## How quickly the body settles to its lean, per second.
const LEAN_SPRING := 9.0
## The mirrors, in the car's space for a 2.6 m wheelbase: the part of the model that holds each
## one's glass, the box its glass lies in, how squarely the glass faces back (the least dot of its
## triangles' normals with +Z), the box its housing lies in, the point behind the car it is set up
## to show, how much wider than flat glass it sees (as a convex mirror does), and the pixels its
## picture has across. The glass is the housing's own face, cut out of the model, and the housing
## is cut out too, for the mirror's own picture to leave out.
const MIRRORS := {
	rear = {part = "Interior", box = AABB(Vector3(-0.11, 1.26, -0.075), Vector3(0.22, 0.075, 0.025)),
		facing = 0.95, shell = AABB(Vector3(-0.13, 1.23, -0.15), Vector3(0.26, 0.15, 0.11)),
		target = Vector3(0.0, 1.1, 20.0), widen = 1.2, width = 512},
	left = {part = "Bottom", box = AABB(Vector3(-0.94, 0.9, -0.53), Vector3(0.21, 0.14, 0.05)),
		facing = 0.95, shell = AABB(Vector3(-0.97, 0.86, -0.7), Vector3(0.27, 0.22, 0.24)),
		target = Vector3(-2.4, 1.0, 20.0), widen = 1.4, width = 256},
	right = {part = "Bottom", box = AABB(Vector3(0.73, 0.9, -0.53), Vector3(0.21, 0.14, 0.05)),
		facing = 0.95, shell = AABB(Vector3(0.7, 0.86, -0.7), Vector3(0.27, 0.22, 0.24)),
		target = Vector3(2.6, 1.0, 20.0), widen = 1.6, width = 256},
}

## The instrument cluster's face, in the car's space for a 2.6 m wheelbase: the part that holds it,
## the box it lies in, and how squarely it faces the driver (the least dot of its triangles' normals
## with +Z). It is the model's own gauge panel, an inset face behind the steering wheel 0.46 m by
## 0.14 m, cut out for the instruments to be drawn on.
const CLUSTER := {part = "Interior", box = AABB(Vector3(-0.545, 0.8, -0.55), Vector3(0.475, 0.155,
	0.015)), facing = 0.95}

## The cabin's parts, each its own mesh and material, cut out of the model's one interior mesh by
## where each triangle is in the car's space for a 2.6 m wheelbase and which way it faces (see
## [method cabin_zone]): each zone's material set, its tint, how many metres one repeat of the
## texture covers, and its roughness when the set's own map is not used.
const CABIN := {
	seats = {set = "Fabric030", tint = Color(0.3, 0.3, 0.31), tile = 0.3},
	bolsters = {set = "Leather026", tint = Color(1.0, 1.0, 1.0), tile = 0.3},
	floor = {set = "Carpet012", tint = Color(0.32, 0.32, 0.33), tile = 0.35, colour = "Grey"},
	headliner = {set = "Fabric034", tint = Color(0.9, 0.9, 0.9), tile = 0.5},
	doors = {set = "Plastic012A", tint = Color(1.0, 1.0, 1.0), tile = 0.4},
	dash = {set = "Plastic012A", tint = Color(1.0, 1.0, 1.0), tile = 0.4},
	wheel = {set = "Leather026", tint = Color(1.0, 1.0, 1.0), tile = 0.12},
}

## The parts that never lean: the wheels and the suspension, which stay on the road. The rest of
## the car, its cockpit included, leans as one.
const STEADY: Array[String] = ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR", "Suspension_front"]

## The model's root, turned and scaled into the car's space.
var body: Node3D
## The wheels: [code]{node, rest, front, sign}[/code] each.
var wheels: Array[Dictionary] = []
var steering_wheel: Node3D
## The steering wheel's column, in its own space, pointing at the driver.
var steering_axis := Vector3.RIGHT
## Where the cockpit's parts are, in the car's space: the steering wheel's centre and the column
## pointing at the driver.
var steering_centre := Vector3.ZERO
## The steering wheel's column in the car's space, pointing at the driver, and its rim's radius,
## metres: where the hands take hold.
var steering_column := Vector3.BACK
var steering_radius := 0.18
var radius := 0.3
## How much larger than the model's own size it is drawn, against a 2.6 m wheelbase.
var fit := 1.0

## The body's lean now, radians: x pitches the nose up, y rolls to the right.
var lean_angles := Vector2.ZERO

var _steering_rest := Transform3D()
var _lean_velocity := Vector2.ZERO
## The parts that lean: [code]{node, rest}[/code] each, in the model's own space.
var _leaning: Array[Dictionary] = []
var _lean_pivot := Vector3.ZERO
var _lights := {}
## The headlamps' beams, lit with the headlights.
var beams: Array[SpotLight3D] = []
## The cabin's parts, cut out of the model's interior: [code]seats[/code], [code]bolsters[/code],
## [code]floor[/code], [code]headliner[/code], [code]doors[/code], and [code]dash[/code], the rest.
var cabin_parts := {}
## Each mirror's housing, cut out of the model round its glass, on a layer the mirrors leave out:
## [code]rear[/code], [code]left[/code], and [code]right[/code].
var mirror_housing := {}
## Each mirror's glass, cut out of its housing: [code]rear[/code], [code]left[/code], and
## [code]right[/code], each with its frame and size in the car's space as metadata.
var mirror_glass := {}
## The instrument cluster's face, cut out of the model with UVs across it, its frame and size in the
## car's space as metadata; null when the model has none.
var cluster_face: MeshInstance3D
## What the car adds to its body in the car's space, the instruments, the mirrors, and the beams:
## it leans with the body, so they stay on it.
var cabin: Node3D


## The car fitted to [param wheelbase] metres; null when the model does not load.
static func make(wheelbase: float) -> PlayerCarModel:
	var scene := load(MODEL) as PackedScene if ResourceLoader.exists(MODEL) else null
	if scene == null:
		return null
	var car := PlayerCarModel.new()
	car.name = "Model"
	car._build(scene.instantiate() as Node3D, wheelbase)
	return car


## Moves the live parts for a step of [param delta] seconds: each wheel turning at its own
## [param spins] (rad/s, forward positive, in [CarDynamics]' order), so a locked wheel stands still
## and a spinning one spins, the front ones steered by [param steer] (-1 full right to 1 full
## left), with the lights as given; the blinkers [param left_on] and [param right_on] are lit or
## dark at this moment of their blink.
func drive(delta: float, spins: PackedFloat64Array, steer: float, left_on: bool, right_on: bool,
		braking: bool, reversing: bool, headlights: bool) -> void:
	var lock := clampf(steer, -1.0, 1.0)
	for wheel in wheels:
		var rest: Transform3D = wheel.rest
		var turn := Basis(Vector3.UP, lock * WHEEL_LOCK) if wheel.front else Basis.IDENTITY
		var turned: float = wheel.roll
		if wheel.index >= 0 and wheel.index < spins.size():
			turned = fmod(turned + spins[wheel.index] * delta, TAU)
			wheel.roll = turned
		var spin := Basis(Vector3.BACK, turned * float(wheel.sign))
		(wheel.node as Node3D).transform = Transform3D(turn * rest.basis * spin, rest.origin)
	if steering_wheel:
		# Steering left turns the wheel anticlockwise as the driver sees it.
		steering_wheel.transform = _steering_rest \
			* Transform3D(Basis(steering_axis, lock * STEERING_LOCK), Vector3.ZERO)
	_light(&"blinkers_left", left_on)
	_light(&"blinkers_right", right_on)
	_light(&"brake", braking)
	_light(&"reverse", reversing)
	_light(&"headlights", headlights)


## The mirror [param key] ([code]rear[/code], [code]left[/code], or [code]right[/code]) for an
## eye at [param from], in the car's space: [code]{transform, aim, size, glass, widen, width}[/code],
## the frame of its glass, the plane it reflects in, turned toward the eye and what it shows behind
## as a mirror's glass pivots in its housing, the glass's size, and the glass itself, the model's
## own face cut out with UVs across it; empty when the model has no glass there.
func mirror_spot(key: StringName, from: Vector3) -> Dictionary:
	var glass := mirror_glass.get(key) as MeshInstance3D
	if glass == null:
		return {}
	var spot: Dictionary = MIRRORS[key]
	var frame: Transform3D = glass.get_meta(&"frame")
	return {transform = frame, aim = _facing(frame.origin, CarMirror.aim(frame.origin, from,
		spot.target * fit)), size = glass.get_meta(&"size"), glass = glass, widen = spot.widen,
		width = spot.width}


static func _facing(at: Vector3, normal: Vector3) -> Transform3D:
	var up := (Vector3.UP - normal * Vector3.UP.dot(normal)).normalized()
	return Transform3D(Basis(up.cross(normal).normalized(), up, normal), at)


## The steering wheel's frame in the car's space, standing still: its origin the rim's centre, +Z
## the column pointing at the driver, +Y up across the rim.
func steering_frame() -> Transform3D:
	var z := steering_column
	var y := (Vector3.UP - z * Vector3.UP.dot(z)).normalized()
	return Transform3D(Basis(y.cross(z).normalized(), y, z), steering_centre)


## Leans the body for a step of [param delta] seconds with the car accelerating [param along] its
## length and [param across] it (to the left positive), metres per second squared: the nose dips
## under braking and the body rolls out of a turn. The whole car leans as one, its cockpit and
## [member cabin] included, on top of the body's own pitch and roll; the wheels stay on the road,
## and nothing simulated moves.
func lean(delta: float, along: float, across: float) -> void:
	if delta <= 0.0:
		return
	var target := Vector2(clampf(along * PITCH_PER, -LEAN_LIMIT, LEAN_LIMIT),
		clampf(across * ROLL_PER, -LEAN_LIMIT, LEAN_LIMIT))
	var pitch := Damped.step(lean_angles.x, _lean_velocity.x, target.x, LEAN_SPRING, delta)
	var roll := Damped.step(lean_angles.y, _lean_velocity.y, target.y, LEAN_SPRING, delta)
	lean_angles = Vector2(pitch.x, roll.x)
	_lean_velocity = Vector2(pitch.y, roll.y)
	# In the model, +X is ahead and +Z to the right: pitching turns about Z, rolling about X.
	var turn := Basis(Vector3.BACK, lean_angles.x) * Basis(Vector3.RIGHT, lean_angles.y)
	var about := Transform3D(Basis.IDENTITY, _lean_pivot) * Transform3D(turn, Vector3.ZERO) \
		* Transform3D(Basis.IDENTITY, -_lean_pivot)
	for part in _leaning:
		(part.node as Node3D).transform = about * (part.rest as Transform3D)
	cabin.transform = body.transform * about * body.transform.affine_inverse()


## Whether the light [param group] glows: [code]blinkers_left[/code], [code]blinkers_right[/code],
## [code]brake[/code], [code]reverse[/code], or [code]headlights[/code].
func is_lit(group: StringName) -> bool:
	var material := _lights.get(group) as StandardMaterial3D
	return material != null and material.emission_energy_multiplier > 0.0


## The car's front wheels' turn, radians, for tests.
func wheel_turn() -> float:
	for wheel in wheels:
		if wheel.front:
			var rest: Transform3D = wheel.rest
			var now := (wheel.node as Node3D).transform.basis
			var axle_rest := (rest.basis * Vector3.BACK).normalized()
			var axle_now := (now * Vector3.BACK).normalized()
			return axle_rest.signed_angle_to(axle_now, Vector3.UP)
	return 0.0


func _build(model: Node3D, wheelbase: float) -> void:
	body = model
	body.name = "Body"
	add_child(body)
	cabin = Node3D.new()
	cabin.name = "Cabin"
	add_child(cabin)
	var front := Vector3.ZERO
	var rear := Vector3.ZERO
	var found := {}
	# Outermost first: the steering wheel's node and its mesh share a name.
	for node: Node in body.find_children("kiri86_*", "", true, false):
		var key := String(node.name).trim_prefix("kiri86_")
		if not found.has(key):
			found[key] = node
	for key in ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"]:
		var wheel := found.get(key) as Node3D
		if wheel == null:
			continue
		var is_front: bool = key.ends_with("FL") or key.ends_with("FR")
		if is_front:
			front += wheel.position / 2.0
		else:
			rear += wheel.position / 2.0
		# Rolling forward (+X in the model) turns the wheel about -Z; its axle may point either way.
		var axle := (wheel.transform.basis * Vector3.BACK).normalized()
		wheels.append({node = wheel, rest = wheel.transform, front = is_front,
			sign = 1.0 if axle.dot(Vector3.FORWARD) > 0.0 else -1.0,
			index = ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR"].find(key), roll = 0.0})
	# The model faces +X; turned to face -Z, scaled to the wheelbase, its wheels' middle on the
	# origin, standing where it stands.
	var natural := maxf(front.x - rear.x, 0.01)
	var scale_by := wheelbase / natural
	fit = wheelbase / 2.6
	var turned := Basis(Vector3.UP, PI / 2.0).scaled(Vector3.ONE * scale_by)
	var middle := (front + rear) / 2.0
	middle.y = 0.0
	body.transform = Transform3D(turned, -(turned * middle))
	if not wheels.is_empty():
		var wheel_node: Node3D = wheels[0].node
		var mesh := wheel_node as MeshInstance3D
		var size := mesh.get_aabb().size * wheel_node.transform.basis.get_scale().abs() \
			if mesh else Vector3.ONE * 0.6
		radius = maxf(size.x, size.y) / 2.0 * scale_by
	var steering := found.get("Steering") as Node3D
	var steering_mesh := steering.get_child(0) as MeshInstance3D if steering \
		and steering.get_child_count() > 0 else null
	if steering_mesh:
		steering_wheel = steering_mesh
		_steering_rest = steering_mesh.transform
		steering_axis = plane_normal(steering_mesh.mesh)
		# The driver sits behind the wheel: -X in the model.
		var column := steering.transform.basis * _steering_rest.basis * steering_axis
		if column.dot(Vector3.LEFT) < 0.0:
			steering_axis = -steering_axis
		steering_centre = body.transform * steering.position
		steering_column = (body.transform.basis * steering.transform.basis * _steering_rest.basis
			* steering_axis).normalized()
		var span := steering_mesh.get_aabb().size * scale_by
		steering_radius = maxf(span.y, span.z) / 2.0 * 0.95
	_materials()
	for key: StringName in MIRRORS:
		_cut_glass(key, found.get(MIRRORS[key].part) as MeshInstance3D)
	cluster_face = _cut_face(found.get(CLUSTER.part) as MeshInstance3D, CLUSTER.box,
		CLUSTER.facing, "ClusterFace")
	_split_cabin(found.get("Interior") as MeshInstance3D)
	_dress_wheel(steering_wheel as MeshInstance3D)
	_split_blinkers(found.get("Blinkers") as MeshInstance3D)
	_glow(found.get("Brakelights001") as MeshInstance3D, &"brake", BRAKE)
	_glow(found.get("Reverse") as MeshInstance3D, &"reverse", REVERSE)
	_glow(found.get("Headlights") as MeshInstance3D, &"headlights", HEADLIGHT)
	_beams(found.get("Headlights") as MeshInstance3D)
	var steady := STEADY.map(func(key: String) -> Node: return found.get(key))
	for part: Node in body.get_children():
		if part is Node3D and not steady.has(part):
			_leaning.append({node = part, rest = (part as Node3D).transform})
	# The body leans about the middle of its wheels, at their axles.
	_lean_pivot = (front + rear) / 2.0
	drive(0.0, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), 0.0, false, false, false, false, false)


## The direction across the flattest extent of [param mesh]'s points: a disc's axis.
static func plane_normal(mesh: Mesh) -> Vector3:
	var points := PackedVector3Array()
	for surface in mesh.get_surface_count():
		points.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	if points.size() < 3:
		return Vector3.RIGHT
	var centre := Vector3.ZERO
	for p in points:
		centre += p
	centre /= points.size()
	# The covariance's two largest directions span the disc; the normal crosses them.
	var c := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for p in points:
		var d := p - centre
		for i in 3:
			for j in 3:
				c[i][j] += d[i] * d[j]
	var first := _largest(c, Vector3(0.3, 0.6, 0.7))
	var lambda := _apply(c, first).dot(first)
	for i in 3:
		for j in 3:
			c[i][j] -= lambda * first[i] * first[j]
	var second := _largest(c, first.cross(Vector3(0.1, 0.9, 0.4)).normalized())
	var normal := first.cross(second)
	return normal.normalized() if normal.length() > 0.0001 else Vector3.RIGHT


static func _largest(c: Array, start: Vector3) -> Vector3:
	var v := start.normalized()
	for i in 64:
		var next := _apply(c, v)
		if next.length() < 0.0000001:
			break
		v = next.normalized()
	return v


static func _apply(c: Array, v: Vector3) -> Vector3:
	return Vector3(c[0][0] * v.x + c[0][1] * v.y + c[0][2] * v.z,
		c[1][0] * v.x + c[1][1] * v.y + c[1][2] * v.z,
		c[2][0] * v.x + c[2][1] * v.y + c[2][2] * v.z)


## Gives each part a material made from the kit's textures, whose own paths point elsewhere.
func _materials() -> void:
	var made := {}
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(surface)
			var key := source.resource_name if source else ""
			if not made.has(key):
				made[key] = _material(key, source as StandardMaterial3D)
			mesh.set_surface_override_material(surface, made[key])


static func _material(key: String, source: StandardMaterial3D) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.resource_name = key
	match key:
		"kiri86_Bodymat":
			m.albedo_texture = _texture("Generic_bodymat_dif.jpeg")
			m.metallic = 0.35
			m.roughness = 0.35
			# A lacquer over the paint: its sharp highlight is what reads as a car's finish.
			m.clearcoat_enabled = true
			m.clearcoat = 0.6
			m.clearcoat_roughness = 0.1
		"UCB_BOTTOM_GT":
			m.albedo_texture = _texture("UCB_BOTTOM_GT_Dif.png")
			m.normal_enabled = true
			m.normal_texture = _texture("UCB_BOTTOM_GT_NRM.png")
			m.roughness_texture = _texture("UCB_BOTTOM_GT_Rough.png")
			m.metallic_texture = _texture("UCB_BOTTOM_GT_Met.png")
			m.metallic = 1.0
		"UCB_Interior_Trim":
			m.albedo_color = Color(0.2, 0.19, 0.18)
			m.roughness_texture = _texture("UCB_Interior_Trim_tile3_Rough.png")
		"UCB_Lights_and_Glass":
			m.albedo_texture = _texture("UCB_Lights_and_Glass_Dif.jpeg")
			m.roughness = 0.3
		"UCB_Lights_and_Glass_Transperent":
			m.albedo_color = Color(0.12, 0.15, 0.17, 0.22)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			m.metallic = 0.3
			m.roughness = 0.05
		"RB1c_Tire_1k":
			m.albedo_texture = _texture("RB1c_Tire_1k_Dif.jpeg")
			m.roughness_texture = _texture("RB1c_Tire_1k_Rough.jpeg")
			m.metallic_texture = _texture("RB1c_Tire_1k_Met.jpeg")
			m.metallic = 1.0
			m.normal_enabled = true
			m.normal_texture = _texture("RB1c_Tire_1k_normal.png")
		"Numberplates_Misk_U", "Carbadges_misc_U":
			m.albedo_texture = source.albedo_texture if source else null
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			# The letters and badges stand out of the plate, from the kit's height maps.
			m.normal_enabled = true
			m.normal_texture = _texture(key + "_normal.png")
		_:
			if source:
				m.albedo_color = source.albedo_color
				m.albedo_texture = source.albedo_texture
	return m


static func _texture(file: String) -> Texture2D:
	var path := TEXTURES + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Which part of the cabin a triangle of the interior is, at [param centre] facing [param normal]
## in the car's space for a 2.6 m wheelbase: the headliner overhead, the carpet underfoot, the door
## cards at the sides, the seats (their sides and edges the leather bolsters), or the dash and the
## rest.
static func cabin_zone(centre: Vector3, normal: Vector3) -> StringName:
	var side := absf(centre.x)
	if centre.y > 1.15 and normal.y < -0.3:
		return &"headliner"
	if side > 0.6 and centre.z > -0.55 and centre.z < 1.0 and centre.y < 1.15:
		return &"doors"
	if side > 0.08 and side < 0.6 and centre.z > -0.32 and centre.y > 0.42 and centre.y < 1.3:
		return &"bolsters" if absf(normal.x) > 0.65 else &"seats"
	if centre.y < 0.42 or (centre.y < 0.62 and normal.y > 0.25):
		return &"floor"
	return &"dash"


## Cuts the interior [param part] into the cabin's parts ([constant CABIN]), each with its own
## material and its texture laid across it in the car's space; the dash keeps the part itself.
func _split_cabin(part: MeshInstance3D) -> void:
	if part == null:
		return
	var to_car := body.transform * part.transform
	var normal_to_car := to_car.basis.inverse().transposed()
	var scale_back := 1.0 / fit
	for key: StringName in [&"headliner", &"floor", &"doors", &"seats", &"bolsters"]:
		var picks := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
			var centre := to_car * ((a + b + c) / 3.0) * scale_back
			var facing := (normal_to_car * (c - a).cross(b - a)).normalized()
			return cabin_zone(centre, facing) == key
		var mesh := cut_mesh(part.mesh, picks, true)
		if mesh.get_surface_count() == 0:
			continue
		_cut_away(part, picks)
		var zone := MeshInstance3D.new()
		zone.name = "Cabin" + String(key).to_pascal_case()
		zone.mesh = box_mapped(mesh, to_car, CABIN[key].tile)
		zone.material_override = _cabin_material(key)
		zone.transform = part.transform
		part.get_parent().add_child(zone)
		cabin_parts[key] = zone
	part.mesh = box_mapped(cut_mesh(part.mesh, func(_a, _b, _c) -> bool: return true, true),
		to_car, CABIN.dash.tile)
	part.material_override = _cabin_material(&"dash")
	cabin_parts[&"dash"] = part


## The steering wheel in leather, its texture laid across it in its own space, so it turns with it.
func _dress_wheel(wheel_mesh: MeshInstance3D) -> void:
	if wheel_mesh == null:
		return
	var to_car: Transform3D = body.transform * (wheel_mesh.get_parent() as Node3D).transform \
		* wheel_mesh.transform
	var scaled := Transform3D(Basis.from_scale(to_car.basis.get_scale()), Vector3.ZERO)
	wheel_mesh.mesh = box_mapped(cut_mesh(wheel_mesh.mesh, func(_a, _b, _c) -> bool: return true,
		true), scaled, CABIN.wheel.tile)
	wheel_mesh.material_override = _cabin_material(&"wheel")


## [param mesh] (unindexed triangles) with new texture coordinates laid across it: each triangle
## projected along the axis it most faces, in the space [param to_space] turns it into, one repeat
## each [param tile] metres; and tangents to match, for the normal maps.
static func box_mapped(mesh: ArrayMesh, to_space: Transform3D, tile: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	var normal_to := to_space.basis.inverse().transposed()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		arrays[Mesh.ARRAY_TEX_UV] = box_uvs(points, to_space, normal_to, tile)
		arrays[Mesh.ARRAY_TANGENT] = null
		var tool := SurfaceTool.new()
		tool.create_from_arrays(arrays)
		tool.generate_tangents()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tool.commit_to_arrays())
	return out


## The texture coordinates of the unindexed triangles [param points]: each corner of a triangle
## projected along the axis the triangle most faces, after [param to_space] (its normals turned by
## [param normal_to]), one unit each [param tile] metres.
static func box_uvs(points: PackedVector3Array, to_space: Transform3D, normal_to: Basis,
		tile: float) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	uvs.resize(points.size())
	for t in range(0, points.size() - 2, 3):
		var a := to_space * points[t]
		var b := to_space * points[t + 1]
		var c := to_space * points[t + 2]
		var n := (normal_to * (points[t + 2] - points[t]).cross(points[t + 1] - points[t])).abs()
		for i in 3:
			var p: Vector3 = [a, b, c][i]
			var uv := Vector2(p.z, p.y) if n.x >= n.y and n.x >= n.z \
				else (Vector2(p.x, p.z) if n.y >= n.z else Vector2(p.x, p.y))
			uvs[t + i] = uv / tile
	return uvs


## The material of the cabin's part [param key], from its set in [constant CABIN].
static func _cabin_material(key: StringName) -> StandardMaterial3D:
	var spec: Dictionary = CABIN[key]
	var folder: String = CABIN_FOLDER + spec.set + "/" + spec.set + "_1K-JPG_"
	var m := StandardMaterial3D.new()
	m.resource_name = "cabin_" + String(key)
	m.albedo_texture = _load(folder + spec.get("colour", "Color") + ".jpg")
	m.albedo_color = spec.tint
	m.normal_enabled = true
	m.normal_texture = _load(folder + "NormalGL.jpg")
	m.roughness_texture = _load(folder + "Roughness.jpg")
	m.metallic = 0.0
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


static func _load(path: String) -> Texture2D:
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## Takes the triangles [param picks] picks out of [param part], which keeps its materials.
static func _cut_away(part: MeshInstance3D, picks: Callable) -> void:
	var materials := _surface_materials(part)
	var sources := []
	part.mesh = cut_mesh(part.mesh, picks, false, sources)
	for surface in sources.size():
		part.set_surface_override_material(surface, materials[sources[surface]])


## Each surface's material as [param part] draws it: its override, else the mesh's own.
static func _surface_materials(part: MeshInstance3D) -> Array:
	var materials := []
	for surface in part.mesh.get_surface_count():
		var material := part.get_surface_override_material(surface)
		materials.append(material if material else part.mesh.surface_get_material(surface))
	return materials


## Cuts the housing of mirror [param key] out of [param part] (whose space [param to_car] turns
## into the car's), the rest of what lies in its shell box, into a mesh of its own on
## [constant Layers.MIRROR_HOUSING_VISUAL]: drawn for the driver, left out of the mirrors.
func _cut_housing(key: StringName, part: MeshInstance3D, to_car: Transform3D) -> void:
	var shell: AABB = MIRRORS[key].shell
	shell = AABB(shell.position * fit, shell.size * fit)
	var picks := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return shell.has_point(to_car * ((a + b + c) / 3.0))
	var materials := _surface_materials(part)
	var sources := []
	var mesh := cut_mesh(part.mesh, picks, true, sources)
	if mesh.get_surface_count() == 0:
		return
	_cut_away(part, picks)
	var housing := MeshInstance3D.new()
	housing.name = "MirrorHousing" + String(key).to_pascal_case()
	housing.mesh = mesh
	for surface in sources.size():
		housing.set_surface_override_material(surface, materials[sources[surface]])
	housing.transform = part.transform
	housing.layers = Layers.MIRROR_HOUSING_VISUAL
	part.get_parent().add_child(housing)
	mirror_housing[key] = housing


## Cuts the glass of mirror [param key] out of [param part]: the triangles in its box facing back,
## and the housing round it.
func _cut_glass(key: StringName, part: MeshInstance3D) -> void:
	var spot: Dictionary = MIRRORS[key]
	var glass := _cut_face(part, spot.box, spot.facing, "Mirror" + String(key).to_pascal_case())
	if glass == null:
		return
	_cut_housing(key, part, body.transform * part.transform)
	mirror_glass[key] = glass


## Cuts a face out of [param part]: the triangles whose centres lie in [param box] (in the car's
## space for a 2.6 m wheelbase) facing back toward the driver at least [param facing] (the dot of
## their normal with +Z). The part keeps the rest, so the face is not drawn twice, and the face gets
## UVs across it, U to the driver's right and V down, for a picture drawn on it. Returns it named
## [param title], with its frame (its centre, facing the way its triangles do on average, upright)
## and its size in the car's space as metadata; null when nothing is there.
func _cut_face(part: MeshInstance3D, box: AABB, facing: float, title: String) -> MeshInstance3D:
	if part == null:
		return null
	box = AABB(box.position * fit, box.size * fit)
	var to_car := body.transform * part.transform
	var normal_to_car := to_car.basis.inverse().transposed()
	var picks := func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		var centre := to_car * ((a + b + c) / 3.0)
		# Godot's front faces wind clockwise: their outward normal is (c - a) x (b - a).
		var normal := (normal_to_car * (c - a).cross(b - a)).normalized()
		return box.has_point(centre) and normal.z >= facing
	var face_mesh := cut_mesh(part.mesh, picks, true)
	if face_mesh.get_surface_count() == 0:
		return null
	_cut_away(part, picks)
	var arrays := face_mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normal_sum := Vector3.ZERO
	for t in range(0, points.size() - 2, 3):
		normal_sum += normal_to_car * (points[t + 2] - points[t]).cross(points[t + 1] - points[t])
	var in_car := PackedVector3Array()
	for p in points:
		in_car.append(to_car * p)
	var bounds := AABB(in_car[0], Vector3.ZERO)
	for p in in_car:
		bounds = bounds.expand(p)
	var frame := _facing(bounds.get_center(), normal_sum.normalized())
	var to_frame := frame.affine_inverse()
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for p in in_car:
		var local := to_frame * p
		low = Vector2(minf(low.x, local.x), minf(low.y, local.y))
		high = Vector2(maxf(high.x, local.x), maxf(high.y, local.y))
	var size := (high - low).max(Vector2(0.001, 0.001))
	var uvs := PackedVector2Array()
	for p in in_car:
		var local := to_frame * p
		uvs.append(Vector2((local.x - low.x) / size.x, 1.0 - (local.y - low.y) / size.y))
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var face := MeshInstance3D.new()
	face.name = title
	face.mesh = mesh
	face.transform = part.transform
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The centre of the face, not of the box round it: centred, the frame sits on the face.
	frame.origin += frame.basis * Vector3((low.x + high.x) / 2.0, (low.y + high.y) / 2.0, 0.0)
	face.set_meta(&"frame", frame)
	face.set_meta(&"size", size)
	part.get_parent().add_child(face)
	return face


## The triangles of [param mesh] that [param picks] picks (given their three corners), or with
## [param kept] false the ones it leaves, as a mesh of their own. A surface left with no triangles
## is dropped; [param sources] gets the source surface of each one made.
static func cut_mesh(mesh: Mesh, picks: Callable, kept: bool, sources: Array = []) -> ArrayMesh:
	var out := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var tool := SurfaceTool.new()
		tool.create_from(mesh, surface)
		tool.deindex()
		var arrays := tool.commit_to_arrays()
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var keep := PackedInt32Array()
		for t in range(0, points.size() - 2, 3):
			if picks.call(points[t], points[t + 1], points[t + 2]) == kept:
				keep.append_array([t, t + 1, t + 2])
		if keep.is_empty():
			continue
		if kept:
			# The glass on its own: only its own corners, unindexed.
			for column in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT,
					Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
				arrays[column] = _pick(arrays[column], keep, column == Mesh.ARRAY_TANGENT)
			arrays[Mesh.ARRAY_INDEX] = null
		else:
			arrays[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		sources.append(surface)
	return out


static func _pick(column: Variant, rows: PackedInt32Array, tangent: bool) -> Variant:
	if column == null:
		return null
	if tangent:
		var out := PackedFloat32Array()
		for r in rows:
			out.append_array((column as PackedFloat32Array).slice(r * 4, r * 4 + 4))
		return out
	var picked: Variant = column.duplicate()
	picked.resize(rows.size())
	for i in rows.size():
		picked[i] = column[rows[i]]
	return picked


## Splits the blinkers, one mesh for both sides, into the left and the right, each its own light.
func _split_blinkers(mesh: MeshInstance3D) -> void:
	if mesh == null:
		return
	# In the model, +X is ahead and +Z to the left (measured: the car's left is the model's +Z).
	for side: StringName in [&"blinkers_left", &"blinkers_right"]:
		var part := MeshInstance3D.new()
		part.name = String(side).to_pascal_case()
		part.mesh = split_mesh(mesh.mesh, func(centroid: Vector3) -> bool:
			return (centroid.z > 0.0) == (side == &"blinkers_left"))
		part.transform = mesh.transform
		mesh.get_parent().add_child(part)
		_glow(part, side, BLINKER)
	mesh.visible = false


## The triangles of [param mesh] whose centroid [param keep] keeps, as a mesh of their own.
static func split_mesh(mesh: Mesh, keep: Callable) -> ArrayMesh:
	var out := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var tool := SurfaceTool.new()
		tool.create_from(mesh, surface)
		tool.deindex()
		var arrays := tool.commit_to_arrays()
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var kept := PackedInt32Array()
		for t in range(0, points.size() - 2, 3):
			if keep.call((points[t] + points[t + 1] + points[t + 2]) / 3.0):
				kept.append_array([t, t + 1, t + 2])
		if kept.is_empty():
			continue
		arrays[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


func _glow(mesh: MeshInstance3D, group: StringName, colour: Color) -> void:
	if mesh == null:
		return
	var base := mesh.get_surface_override_material(0) as StandardMaterial3D
	var m := (base.duplicate() as StandardMaterial3D) if base else StandardMaterial3D.new()
	m.emission_enabled = true
	m.emission = colour
	m.emission_energy_multiplier = 0.0
	for surface in mesh.mesh.get_surface_count():
		mesh.set_surface_override_material(surface, m)
	_lights[group] = m


func _light(group: StringName, on: bool) -> void:
	var material := _lights.get(group) as StandardMaterial3D
	if material:
		material.emission_energy_multiplier = GLOW if on else 0.0
	if group == &"headlights":
		for beam in beams:
			beam.visible = on


## A dipped beam from each headlamp, ahead and a little down, without shadows; dark until the
## headlights are on.
func _beams(mesh: MeshInstance3D) -> void:
	if mesh == null:
		return
	# In the model, +Z is to the right: one lamp each side.
	for left in [true, false]:
		var half := split_mesh(mesh.mesh, func(centroid: Vector3) -> bool:
			return (centroid.z < 0.0) == left)
		if half.get_surface_count() == 0:
			continue
		var beam := SpotLight3D.new()
		beam.name = "BeamLeft" if left else "BeamRight"
		beam.light_color = HEADLIGHT
		beam.light_energy = BEAM_ENERGY
		beam.spot_range = BEAM_RANGE
		beam.spot_angle = BEAM_ANGLE
		beam.shadow_enabled = false
		beam.position = body.transform * mesh.transform * half.get_aabb().get_center()
		beam.rotation = Vector3(deg_to_rad(-BEAM_DIP), 0.0, 0.0)
		beam.visible = false
		cabin.add_child(beam)
		beams.append(beam)
