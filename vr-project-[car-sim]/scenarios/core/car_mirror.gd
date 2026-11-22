class_name CarMirror
extends Node3D
## One of the car's mirrors: a pane of glass showing what a mirror there would show the driver.
## A camera stands at the driver's eye reflected across the glass and looks back through it, its
## view cut to the glass's edges (an off-axis frustum whose near plane is the glass), so the
## picture moves as the driver's head does, as a real mirror's would. The picture is rendered into
## a small screen of its own, flipped as a reflection is, and only when [method render] asks for
## it, so the car can spread its mirrors over the frames. Its glass faces +Z and reflects in the
## plane [member pivot], turned within it; nothing here takes part in the simulation.

## How much of the light a mirror gives back.
const REFLECTANCE := 0.85
## How far the mirror's view reaches, metres.
const FAR := 150.0
## The visual layers a mirror does not show: what only the headset or only the spectator sees.
static var hidden_layers := 0

## The glass's size, metres.
var size := Vector2(0.1, 0.08)
## The plane the mirror reflects in, in the glass's own space: the glass sits flat on its housing,
## and the plane is turned within it as the glass of a real mirror pivots.
var pivot := Transform3D()
## How much wider than flat glass the mirror sees, as a convex mirror does; 1 is flat.
var widen := 1.0
## Where the driver's eye is; the mirror shows nothing while it is unset.
var eye: Node3D
var viewport: SubViewport
var camera: Camera3D
var glass: MeshInstance3D


## A mirror named [param p_name] of [param p_size] metres, rendering [param width] pixels across.
static func make(p_name: String, p_size: Vector2, width: int) -> CarMirror:
	var mirror := CarMirror.new()
	mirror.name = p_name
	mirror.size = p_size
	mirror._build(width)
	return mirror


## The glass's normal for a mirror at [param centre] that shows [param target] to an eye at
## [param from]: halfway between the directions to each, as a mirror set up for that driver is.
static func aim(centre: Vector3, from: Vector3, target: Vector3) -> Vector3:
	return ((from - centre).normalized() + (target - centre).normalized()).normalized()


## [param point] reflected across the plane through [param centre] facing [param normal].
static func reflect(point: Vector3, centre: Vector3, normal: Vector3) -> Vector3:
	return point - 2.0 * (point - centre).dot(normal) * normal


## The mirror's camera for an eye at [param from], for glass at [param glass_transform] (facing
## its +Z) of [param glass_size]: [code]{transform, near, offset}[/code], the camera at the
## reflected eye looking through the glass, its near plane on the glass and its view offset to the
## glass's centre; empty when the eye is behind the glass.
static func view(from: Vector3, glass_transform: Transform3D, glass_size: Vector2) -> Dictionary:
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
	return {transform = Transform3D(basis, at), near = distance,
		offset = Vector2(local.x, local.y), height = glass_size.y}


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
	var from := eye.global_position
	var plane := global_transform * pivot
	var v := view(from, plane, aim_size(from, global_transform, plane, size) * widen)
	if v.is_empty():
		return
	camera.global_transform = v.transform
	camera.set_frustum(v.height, v.offset, v.near, FAR)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _build(width: int) -> void:
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
	viewport.add_child(camera)
	glass = MeshInstance3D.new()
	glass.name = "Glass"
	var quad := QuadMesh.new()
	quad.size = size
	glass.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = viewport.get_texture()
	material.albedo_color = Color(REFLECTANCE, REFLECTANCE, REFLECTANCE)
	# A reflection is the picture flipped left to right.
	material.uv1_scale = Vector3(-1.0, 1.0, 1.0)
	material.uv1_offset = Vector3(1.0, 0.0, 0.0)
	glass.material_override = material
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glass)
