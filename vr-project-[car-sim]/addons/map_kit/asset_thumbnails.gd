@tool
class_name AssetThumbnails
extends Node
## Renders the Asset Library's thumbnails: each model alone, from the same three-quarter view and
## light, [constant SIZE] pixels square, so every pack looks alike and stays sharp at any size the
## pane shows. Models are rendered when the pane asks for them, one per frame, and kept as PNG
## files in the project's editor folder (under [code].godot/[/code], not in the repository),
## named after the model's path, the file's modified time, and its pack's scale, so a changed
## model is rendered again.

## Emitted when the thumbnail of the model at [param path] is ready.
signal thumbnail_ready(path: String, texture: Texture2D)

const SIZE := 128
## Degrees round from the front, and down from level, the camera looks from.
const YAW := 35.0
const PITCH := 30.0
const FOLDER := "map_kit_thumbnails"

var _viewport: SubViewport
var _model: MeshInstance3D
var _camera: Camera3D
var _queue := PackedStringArray()
var _textures := {}
var _busy := false
var _folder := ""


func _ready() -> void:
	_build()


## Sets up the folder and the scene the models are rendered in, once; the pane may ask for
## thumbnails before this node is ready.
func _build() -> void:
	if _viewport:
		return
	_folder = EditorInterface.get_editor_paths().get_project_settings_dir().path_join(FOLDER)
	DirAccess.make_dir_recursive_absolute(_folder)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.85)
	environment.ambient_light_energy = 0.6
	var world := WorldEnvironment.new()
	world.environment = environment
	_viewport.add_child(world)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -30, 0)
	key.light_energy = 1.1
	_viewport.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 150, 0)
	fill.light_energy = 0.35
	_viewport.add_child(fill)
	_model = MeshInstance3D.new()
	_viewport.add_child(_model)
	_camera = Camera3D.new()
	_camera.fov = 30.0
	_viewport.add_child(_camera)


## The rendered thumbnail of the model at [param path] if it is ready; null otherwise, after
## asking for it, and [signal thumbnail_ready] follows.
func get_thumbnail(path: String) -> Texture2D:
	_build()
	if _textures.has(path):
		return _textures[path]
	var file := _folder.path_join(cache_name(path, _modified(path), AssetPack.of_model(path).scale))
	if FileAccess.file_exists(file):
		var image := Image.load_from_file(file)
		if image:
			var texture := ImageTexture.create_from_image(image)
			_textures[path] = texture
			return texture
	if not _queue.has(path):
		_queue.append(path)
	if not _busy and is_inside_tree():
		_render_queue()
	return null


## Forgets the thumbnail of [param path] kept in memory, so the file is looked at again.
func forget(path: String) -> void:
	_textures.erase(path)


## Drops the models asked for but not rendered yet, when the pane shows others.
func clear_queue() -> void:
	_queue.clear()


## The file a thumbnail is kept in: the model's path, its file's modified time, and its pack's
## scale, hashed.
static func cache_name(path: String, modified: int, pack_scale: float) -> String:
	return "%s.png" % ("%s|%d|%s|%d" % [path, modified, pack_scale, SIZE]).md5_text()


## Where the camera stands to frame a model scaled to fit a one metre cube, standing on its
## origin.
static func camera_transform() -> Transform3D:
	var centre := Vector3(0, 0.5, 0)
	var direction := Vector3(0, 0, 1).rotated(Vector3.RIGHT, -deg_to_rad(PITCH)) \
		.rotated(Vector3.UP, deg_to_rad(YAW))
	var distance := 0.95 / tan(deg_to_rad(15.0))
	var from := centre + direction * distance
	return Transform3D.IDENTITY.looking_at(centre - from, Vector3.UP).translated(from)


## The scale and offset that fit a model of [param bounds] in a one metre cube standing on its
## origin, keeping its proportions.
static func fit_transform(bounds: AABB) -> Transform3D:
	var longest := maxf(bounds.size[bounds.size.max_axis_index()], 0.001)
	var base := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var fitted := Transform3D(Basis.from_scale(Vector3.ONE / longest), Vector3.ZERO)
	return fitted * Transform3D(Basis.IDENTITY, -base)


func _render_queue() -> void:
	_busy = true
	_camera.transform = camera_transform()
	while not _queue.is_empty() and is_inside_tree():
		var path := _queue[0]
		_queue.remove_at(0)
		var mesh := KitModels.mesh(path)
		if mesh == null:
			continue
		_model.mesh = mesh
		_model.transform = fit_transform(mesh.get_aabb())
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if not is_inside_tree():
			break
		var image := _viewport.get_texture().get_image()
		if image == null or image.is_empty():
			continue
		image.save_png(_folder.path_join(cache_name(path, _modified(path),
			AssetPack.of_model(path).scale)))
		var texture := ImageTexture.create_from_image(image)
		_textures[path] = texture
		thumbnail_ready.emit(path, texture)
	_busy = false


static func _modified(path: String) -> int:
	return FileAccess.get_modified_time(path)
