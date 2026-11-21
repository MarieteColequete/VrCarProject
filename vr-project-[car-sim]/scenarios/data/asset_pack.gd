@tool
class_name AssetPack
extends Resource
## A folder of models in [code]res://assets/[/code], described by the [code]pack.tres[/code] in
## it: its name and credit, how its models are scaled and turned to the project's metres and
## facing (-Z ahead), and its [AssetCategory]s. Adding a pack is adding its folder with its models
## ([code].glb[/code]), an optional [code]previews/<model>.png[/code] per model, and a
## [code]pack.tres[/code]; the [AssetCatalogue] finds it. A folder of models without one is listed
## under [constant OTHER] at the models' own size.

const FILE := "pack.tres"
const OTHER := "Other"

@export var title := ""
## Who made it and under which licence.
@export var credit := ""
## Metres per unit of the models.
@export var scale := 1.0
## How far the models are turned about the vertical, degrees, for their front to face -Z.
@export var turn_degrees := 0.0
@export var categories: Array[AssetCategory] = []

static var _packs := {}


## The pack of the folder [param folder]: its [code]pack.tres[/code], or a plain pack when it has
## none. Kept once loaded.
static func of_folder(folder: String) -> AssetPack:
	var key := folder.trim_suffix("/")
	if _packs.has(key):
		return _packs[key]
	var path := key.path_join(FILE)
	var pack: AssetPack = load(path) if ResourceLoader.exists(path) else null
	if pack == null:
		pack = AssetPack.new()
		pack.title = key.get_file().capitalize()
	_packs[key] = pack
	return pack


## The pack of the model at [param model_path].
static func of_model(model_path: String) -> AssetPack:
	return of_folder(model_path.get_base_dir())


## Forgets the packs loaded, so edited pack files are read again.
static func forget() -> void:
	_packs.clear()


## The category of the model [param model_name]; null when none matches.
func category_of(model_name: String) -> AssetCategory:
	for category in categories:
		if category and category.has_model(model_name):
			return category
	return null


## The basis turning a model to face -Z, scaled to metres.
func placement() -> Basis:
	return Basis(Vector3.UP, deg_to_rad(turn_degrees)).scaled(Vector3.ONE * scale)
