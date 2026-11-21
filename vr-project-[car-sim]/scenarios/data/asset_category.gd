@tool
class_name AssetCategory
extends Resource
## One category of an [AssetPack]: which of the pack's models belong to it, by name pattern, and
## how a [MapAsset] made from one of them behaves: what kind of solid it is, or looks only, and
## its size.

enum Collider {
	## A box around [member solid_part] of the model: for anything standing up.
	BOX,
	## The model's own surface: for ground pieces with kerbs, such as road tiles.
	MESH,
}

## The name the Asset Library pane lists, such as "Cars"; categories of the same name in different
## packs are listed together.
@export var title := ""
## Model names that belong to it, without [code].glb[/code]; [code]*[/code] and [code]?[/code]
## match any text and any one character. A model goes to the first category it matches.
@export var models: PackedStringArray = []
## What kind of solid its models are ([BodyType]): an obstacle, a vehicle, a pavement; none for
## looks only, which nothing collides with or judges.
@export var body: BodyType
@export var collider := Collider.BOX
## The size every model of the category is stretched to, metres; zero on an axis keeps the
## pack's scale there. Cars of a kit are often wider and taller than real ones.
@export var fit := Vector3.ZERO
## A further scale on the pack's, for models the kit makes too small, such as trees.
@export var extra_scale := 1.0
## The part of the model's box that is solid, per axis: a tree's trunk is a thin column of it.
@export var solid_part := Vector3.ONE
## Where it sorts in the pane; lower first.
@export var order := 0


## Whether the model [param model_name] belongs to the category.
func has_model(model_name: String) -> bool:
	for pattern in models:
		if model_name.match(pattern):
			return true
	return false
