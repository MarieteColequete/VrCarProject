@tool
class_name KitModels
extends RefCounted
## The models in [code]res://assets/[/code]: each model's parts merged into one mesh, standing on
## its origin at the centre of its base, its front towards -Z as the project's cars face, in
## metres, as its [AssetPack] scales and turns it. Meshes are built once and kept. Used on the
## main thread only, by props, map assets, parked cars, and the road users' view. The constants
## name the Kenney kits' models that the props and road users use.

const CAR_KIT := "res://assets/kenney/car_kit/"
const SUBURBAN := "res://assets/kenney/city_kit_suburban/"

## Cars for parked cars and road users, in the order a variant picks them.
const CARS: PackedStringArray = ["sedan", "suv", "hatchback-sports", "taxi", "sedan-sports",
	"suv-luxury", "police"]
## Vans and small lorries.
const VANS: PackedStringArray = ["van", "delivery", "truck", "delivery-flat", "truck-flat"]
## Long vehicles, for road users longer than a car.
const LONG: PackedStringArray = ["delivery", "truck", "garbage-truck", "firetruck", "ambulance"]
## The suburban kit's houses, a to u.
const BUILDINGS: PackedStringArray = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
	"m", "n", "o", "p", "q", "r", "s", "t", "u"]

static var _meshes := {}


## Forgets the meshes built, so models and packs changed on disk are read again.
static func forget() -> void:
	_meshes.clear()
	AssetPack.forget()
	RoadKit.forget()


## Forgets the meshes built from the model at [param model_path], so a reimport is read again.
static func forget_model(model_path: String) -> void:
	_meshes.erase(model_path)
	_meshes.erase(model_path + "#unit")


## The number of triangles in the model's mesh; zero when it does not load.
static func triangles(model_path: String) -> int:
	var built := mesh(model_path)
	if built == null:
		return 0
	var count := 0
	for surface in built.get_surface_count():
		var arrays := built.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		count += (indices.size() if not indices.is_empty()
			else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return count


## The path of the car kit's model [param model_name], such as [code]sedan[/code].
static func car_kit(model_name: String) -> String:
	return CAR_KIT + model_name + ".glb"


## The path of the suburban kit's model [param model_name], such as [code]tree-large[/code].
static func suburban(model_name: String) -> String:
	return SUBURBAN + model_name + ".glb"


## The path of the kit's preview image of the model at [param model_path].
static func preview(model_path: String) -> String:
	return model_path.get_base_dir().path_join("previews").path_join(
		model_path.get_file().get_basename() + ".png")


## The car for [param variant], wrapping round [constant CARS].
static func car(variant: int) -> String:
	return car_kit(CARS[posmod(variant, CARS.size())])


static func van(variant: int) -> String:
	return car_kit(VANS[posmod(variant, VANS.size())])


static func long_vehicle(variant: int) -> String:
	return car_kit(LONG[posmod(variant, LONG.size())])


static func building(variant: int) -> String:
	return suburban("building-type-" + BUILDINGS[posmod(variant, BUILDINGS.size())])


## The model at [param model_path] as one mesh, in metres; null when it does not load.
static func mesh(model_path: String) -> ArrayMesh:
	return _mesh(model_path, false)


## The model at [param model_path] as one mesh scaled into a one metre cube, standing on its
## origin, for drawing it at any size; null when it does not load.
static func unit_mesh(model_path: String) -> ArrayMesh:
	return _mesh(model_path, true)


## The model's size in metres; zero when it does not load.
static func size_of(model_path: String) -> Vector3:
	var built := mesh(model_path)
	return built.get_aabb().size if built else Vector3.ZERO


static func _mesh(model_path: String, unit: bool) -> ArrayMesh:
	var key := model_path + ("#unit" if unit else "")
	if _meshes.has(key):
		return _meshes[key]
	var scene := load(model_path) as PackedScene if ResourceLoader.exists(model_path) else null
	if scene == null:
		return null
	var root := scene.instantiate()
	var parts: Array = []
	_collect(root, Transform3D.IDENTITY, parts)
	root.free()
	if parts.is_empty():
		return null
	var placed := Transform3D(AssetPack.of_model(model_path).placement(), Vector3.ZERO)
	var bounds: AABB = placed * _bounds(parts)
	var base := Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z)
	var fitted := Transform3D(Basis.IDENTITY, -base) * placed
	if unit:
		var size := bounds.size.max(Vector3.ONE * 0.001)
		fitted = Transform3D(Basis.from_scale(Vector3.ONE / size), Vector3.ZERO) * fitted
	var tool := SurfaceTool.new()
	var material: Material = null
	for part: Array in parts:
		var part_mesh: Mesh = part[0]
		for surface in part_mesh.get_surface_count():
			tool.append_from(part_mesh, surface, fitted * (part[1] as Transform3D))
			if material == null:
				material = part_mesh.surface_get_material(surface)
	if material:
		tool.set_material(material)
	var built := tool.commit()
	_meshes[key] = built
	return built


## Every mesh under [param node], with its transform from the model's root.
static func _collect(node: Node, to_root: Transform3D, out: Array) -> void:
	var here := to_root
	if node is Node3D:
		here = to_root * (node as Node3D).transform if node.get_parent() else Transform3D.IDENTITY
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		out.append([(node as MeshInstance3D).mesh, here])
	for child in node.get_children():
		_collect(child, here, out)


static func _bounds(parts: Array) -> AABB:
	var out := AABB()
	for i in parts.size():
		var box: AABB = (parts[i][1] as Transform3D) * (parts[i][0] as Mesh).get_aabb()
		out = box if i == 0 else out.merge(box)
	return out
