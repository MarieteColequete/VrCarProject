class_name CarMirror
extends Node3D
## One of the car's mirrors: a pane of glass showing what a mirror there would show the driver.
## A camera stands at the driver's eye reflected across the glass and looks back through it, its
## view cut to the glass's edges (an off-axis frustum whose near plane is the glass), so the
## picture moves as the driver's head does, as a real mirror's would. The picture is rendered into
## a small screen of its own, flipped as a reflection is, and only when [method render] asks for
## it, so the car can spread its mirrors over the frames. The picture is shown on the model's own
## glass, or on a pane of its own when the model has none. Its glass faces +Z and reflects in the
## plane [member pivot], turned within it; the driver tilts that plane ([member tilt]) as the glass
## of a real mirror is set. Nothing here takes part in the simulation.

## How much of the light a mirror gives back.
const REFLECTANCE := 0.85
## How far the mirror's view reaches, metres.
const FAR := 150.0
## The most the driver tilts a mirror from where it was set up, either way, radians.
const TILT_LIMIT := deg_to_rad(20.0)
## The section of the settings file the tilts are kept in.
const TILT_SECTION := "mirrors"
## The visual layers a mirror does not show: the hands, what only the spectator sees, the mirrors'
## glass, and their housings.
static var hidden_layers := Layers.HANDS_VISUAL | Layers.SPECTATOR_VISUAL | Layers.MIRROR_VISUAL \
	| Layers.MIRROR_HOUSING_VISUAL

## The glass's size, metres.
var size := Vector2(0.1, 0.08)
## The plane the mirror reflects in, in the glass's own space: the glass sits flat on its housing,
## and the plane is turned within it as the glass of a real mirror pivots.
var pivot := Transform3D()
## The plane as the mirror was set up for the driver's seat, before the driver tilted it.
var rest_pivot := Transform3D():
	set(value):
		rest_pivot = value
		pivot = tilted(rest_pivot, tilt)
## How far the driver has tilted the glass from [member rest_pivot], radians: x turns the view to
## the driver's right, y turns it up. Within [constant TILT_LIMIT].
var tilt := Vector2.ZERO:
	set(value):
		tilt = value.clamp(-Vector2.ONE * TILT_LIMIT, Vector2.ONE * TILT_LIMIT)
		pivot = tilted(rest_pivot, tilt)
## Whether the driver is adjusting this mirror: its glass is lit a little brighter.
var selected := false:
	set(value):
		selected = value
		if glass and glass.material_override is StandardMaterial3D:
			var lit := 1.0 if selected else REFLECTANCE
			(glass.material_override as StandardMaterial3D).albedo_color = \
				Color(lit, lit, lit * (0.85 if selected else 1.0))
## How much wider than flat glass the mirror sees, as a convex mirror does; 1 is flat.
var widen := 1.0
## Where the driver's eye is; the mirror shows nothing while it is unset.
var eye: Node3D
var viewport: SubViewport
var camera: Camera3D
var glass: MeshInstance3D


## A mirror named [param p_name] of [param p_size] metres, rendering [param width] pixels across,
## its picture shown on [param on_glass], the model's own glass with UVs across its face; with
## none, on a pane of its own.
static func make(p_name: String, p_size: Vector2, width: int,
		on_glass: MeshInstance3D = null) -> CarMirror:
	var mirror := CarMirror.new()
	mirror.name = p_name
	mirror.size = p_size
	mirror._build(width, on_glass)
	return mirror


## The glass's normal for a mirror at [param centre] that shows [param target] to an eye at
## [param from]: halfway between the directions to each, as a mirror set up for that driver is.
static func aim(centre: Vector3, from: Vector3, target: Vector3) -> Vector3:
	return ((from - centre).normalized() + (target - centre).normalized()).normalized()


## The reflecting plane [param rest] tilted by [param by] (see [member tilt]): turned about its
## own up to swing the view sideways, and about its own right to swing it up or down. A plane turned
## by an angle turns what it shows by twice as much.
static func tilted(rest: Transform3D, by: Vector2) -> Transform3D:
	var up := rest.basis.y.normalized()
	var right := rest.basis.x.normalized()
	var turn := Basis(right, -by.y) * Basis(up, by.x)
	return Transform3D(turn * rest.basis, rest.origin)


## Tilts the mirror by [param by] more, within [constant TILT_LIMIT].
func nudge(by: Vector2) -> void:
	tilt += by


## The mirrors' tilts saved in the settings file at [param path], by mirror name; empty when there
## is none.
static func load_tilts(path: String) -> Dictionary:
	var file := ConfigFile.new()
	var tilts := {}
	if file.load(path) != OK or not file.has_section(TILT_SECTION):
		return tilts
	for key in file.get_section_keys(TILT_SECTION):
		var value: Variant = file.get_value(TILT_SECTION, key)
		if value is Vector2:
			tilts[StringName(key)] = value
	return tilts


## Saves the mirrors' tilts [param tilts] (by mirror name) in the settings file at [param path],
## keeping the rest of the file.
static func save_tilts(path: String, tilts: Dictionary) -> void:
	var file := ConfigFile.new()
	file.load(path)
	for key: StringName in tilts:
		file.set_value(TILT_SECTION, String(key), tilts[key])
	file.save(path)


## [param point] reflected across the plane through [param centre] facing [param normal].
static func reflect(point: Vector3, centre: Vector3, normal: Vector3) -> Vector3:
	return point - 2.0 * (point - centre).dot(normal) * normal


## The mirror's camera for an eye at [param from], for glass at [param glass_transform] (facing
## its +Z) of [param glass_size]: [code]{transform, near, offset, height}[/code], the camera at the
## reflected eye looking through the glass, its near plane on the glass and its view offset to the
## glass's centre; empty when the eye is behind the glass. When the plane is turned from the
## housing's own glass at [param housing] of [param housing_size], the near plane moves back past
## every corner of that glass, with the view's edges where they were: nothing behind the glass, the
## housing it sits in, comes into the picture.
static func view(from: Vector3, glass_transform: Transform3D, glass_size: Vector2,
		housing := Transform3D(), housing_size := Vector2.ZERO) -> Dictionary:
	var normal := glass_transform.basis.z.normalized()
	var centre := glass_transform.origin
	var distance := (from - centre).dot(normal)
	if distance <= 0.001:
		return {}
	var at := reflect(from, centre, normal)
	var up := glass_transform.basis.y.normalized()
	var back := -normal
	var basis := Basis(up.cross(back).normalized(), up, back)
	var local := basis.inverse() * (centre - at)
	var near := distance
	if housing_size != Vector2.ZERO:
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			var point := housing * Vector3(corner.x * housing_size.x / 2.0,
				corner.y * housing_size.y / 2.0, 0.0)
			near = maxf(near, (point - at).dot(normal) + 0.002)
	# The frustum's size and offset are on its near plane: moved back, they grow with it.
	var grow := near / distance
	return {transform = Transform3D(basis, at), near = near,
		offset = Vector2(local.x, local.y) * grow, height = glass_size.y * grow}


## The size of the reflecting plane [param plane] that looks from [param from] as large as glass
## of [param glass_size] at [param glass]: each is seen foreshortened by its turn from the eye.
static func aim_size(from: Vector3, glass: Transform3D, plane: Transform3D,
		glass_size: Vector2) -> Vector2:
	var to_eye := (from - glass.origin).normalized()
	var seen_glass := maxf(glass.basis.z.normalized().dot(to_eye), 0.05)
	var seen_plane := maxf(plane.basis.z.normalized().dot(to_eye), 0.05)
	return glass_size * (seen_glass / seen_plane)


## Places the camera for where the eye is now and draws the mirror's picture on the next frame.
func render() -> void:
	if eye == null or not is_instance_valid(eye):
		return
	# Where the glass and the eye are drawn this frame, between the physics ticks: placed from the
	# ticks' own poses, a moving car's mirror would look out from inside its housing.
	var from := eye.get_global_transform_interpolated().origin
	var at := get_global_transform_interpolated()
	var plane := at * pivot
	var v := view(from, plane, aim_size(from, at, plane, size) * widen, at, size)
	if v.is_empty():
		return
	camera.global_transform = v.transform
	camera.set_frustum(v.height, v.offset, v.near, FAR)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _build(width: int, on_glass: MeshInstance3D) -> void:
	viewport = SubViewport.new()
	viewport.name = "View"
	viewport.size = Vector2i(width, maxi(roundi(width * size.y / size.x), 8))
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.positional_shadow_atlas_size = 0
	viewport.mesh_lod_threshold = 4.0
	viewport.use_debanding = false
	add_child(viewport)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_FRUSTUM
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.cull_mask = 0xFFFFF & ~hidden_layers
	camera.current = true
	# Placed every frame it renders, from the eye as it is: not interpolated.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	viewport.add_child(camera)
	if on_glass:
		glass = on_glass
	else:
		glass = MeshInstance3D.new()
		glass.name = "Glass"
		var quad := QuadMesh.new()
		quad.size = size
		glass.mesh = quad
		add_child(glass)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	material.albedo_color = Color(REFLECTANCE, REFLECTANCE, REFLECTANCE)
	# A reflection is the picture flipped left to right.
	material.uv1_scale = Vector3(-1.0, 1.0, 1.0)
	material.uv1_offset = Vector3(1.0, 0.0, 0.0)
	glass.material_override = material
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glass.layers = Layers.MIRROR_VISUAL
