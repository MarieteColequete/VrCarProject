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
## The parts that never lean: the wheels, the suspension, and the cockpit the driver sits in, so the
## driver's view of the cabin stays steady.
const STEADY: Array[String] = ["Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR", "Suspension_front",
	"Interior", "Steering"]

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
var radius := 0.3

## The body's lean now, radians: x pitches the nose up, y rolls to the right.
var lean_angles := Vector2.ZERO

var _steering_rest := Transform3D()
var _lean_velocity := Vector2.ZERO
## The parts that lean: [code]{node, rest}[/code] each, in the model's own space.
var _leaning: Array[Dictionary] = []
var _lean_pivot := Vector3.ZERO
var _roll := 0.0
var _lights := {}
## The headlamps' beams, lit with the headlights.
var beams: Array[SpotLight3D] = []


## The car fitted to [param wheelbase] metres; null when the model does not load.
static func make(wheelbase: float) -> PlayerCarModel:
	var scene := load(MODEL) as PackedScene if ResourceLoader.exists(MODEL) else null
	if scene == null:
		return null
	var car := PlayerCarModel.new()
	car.name = "Model"
	car._build(scene.instantiate() as Node3D, wheelbase)
	return car


## Moves the live parts for a step of [param delta] seconds at [param speed] metres per second
## and [param steer] (-1 full right to 1 full left), with the lights as given; the blinkers
## [param left_on] and [param right_on] are lit or dark at this moment of their blink.
func drive(delta: float, speed: float, steer: float, left_on: bool, right_on: bool,
		braking: bool, reversing: bool, headlights: bool) -> void:
	_roll = fmod(_roll + speed * delta / radius, TAU)
	var lock := clampf(steer, -1.0, 1.0)
	for wheel in wheels:
		var rest: Transform3D = wheel.rest
		var turn := Basis(Vector3.UP, lock * WHEEL_LOCK) if wheel.front else Basis.IDENTITY
		var spin := Basis(Vector3.BACK, _roll * float(wheel.sign))
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


## Leans the body for a step of [param delta] seconds with the car accelerating [param along] its
## length and [param across] it (to the left positive), metres per second squared: the nose dips
## under braking and the body rolls out of a turn. Only the bodywork leans; the cockpit and the
## wheels stay as they are, and nothing simulated moves.
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
			sign = 1.0 if axle.dot(Vector3.FORWARD) > 0.0 else -1.0})
	# The model faces +X; turned to face -Z, scaled to the wheelbase, its wheels' middle on the
	# origin, standing where it stands.
	var natural := maxf(front.x - rear.x, 0.01)
	var scale_by := wheelbase / natural
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
	_materials()
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
	drive(0.0, 0.0, 0.0, false, false, false, false, false)


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


## Splits the blinkers, one mesh for both sides, into the left and the right, each its own light.
func _split_blinkers(mesh: MeshInstance3D) -> void:
	if mesh == null:
		return
	# In the model, +X is ahead and +Z to the right.
	for side: StringName in [&"blinkers_left", &"blinkers_right"]:
		var part := MeshInstance3D.new()
		part.name = String(side).to_pascal_case()
		part.mesh = split_mesh(mesh.mesh, func(centroid: Vector3) -> bool:
			return (centroid.z < 0.0) == (side == &"blinkers_left"))
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
		add_child(beam)
		beams.append(beam)
