class_name PedestrianModel
extends Node3D
## A pedestrian as drawn: one of the survivors of Kenney's Animated Characters (Retro), a man or a
## woman, standing on its origin, facing -Z as the project's road users do, scaled to its body's
## height. It stands idle when still and runs when moving, the run slowed to the walking pace, as
## the kit has no walk. The [TrafficView] makes one per pedestrian road user; nothing here takes
## part in the simulation.

const FOLDER := "res://assets/kenney/animated_characters_retro/"
const MODEL := FOLDER + "characterMedium.fbx"
## The survivors' skins; a pedestrian's variant picks one.
const SKINS: PackedStringArray = ["humanMaleA", "humanFemaleA"]
## The model's height in its own units, from its soles to the top of its head.
const NATURAL_HEIGHT := 3.76
## The speed, metres per second, at which the run plays at its own pace for a 1.8 m pedestrian.
const RUN_PACE := 3.5
## Below this speed, metres per second, a pedestrian stands idle.
const STILL := 0.1
## The slowest the run plays, so a slow walk still moves the legs.
const SLOWEST := 0.3
const IDLE := &"survivor/idle"
const RUN := &"survivor/run"

static var _library: AnimationLibrary
static var _skins := {}

var _player: AnimationPlayer
var _height := 1.8


## A pedestrian [param height] metres tall in skin [param variant], wrapping round
## [constant SKINS]; null when the model does not load.
static func make(variant: int, height: float) -> PedestrianModel:
	var scene := load(MODEL) as PackedScene if ResourceLoader.exists(MODEL) else null
	if scene == null:
		return null
	var pedestrian := PedestrianModel.new()
	pedestrian.name = "Pedestrian"
	pedestrian._height = height
	var body := scene.instantiate() as Node3D
	body.name = "Body"
	# The model faces +Z; turned to face -Z, and scaled from its own units to the height.
	body.transform = Transform3D(Basis(Vector3.UP, PI).scaled(Vector3.ONE * height / NATURAL_HEIGHT),
		Vector3.ZERO)
	pedestrian.add_child(body)
	var skin := skin_material(variant)
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		mesh.material_override = skin
	pedestrian._player = AnimationPlayer.new()
	pedestrian._player.name = "AnimationPlayer"
	# Tracks name the model's skeleton from its root, the player's parent.
	body.add_child(pedestrian._player)
	pedestrian._player.add_animation_library(&"survivor", library())
	pedestrian._player.play(IDLE)
	return pedestrian


## The skin of [param variant] as a material, made once per skin.
static func skin_material(variant: int) -> StandardMaterial3D:
	var skin := SKINS[posmod(variant, SKINS.size())]
	if not _skins.has(skin):
		var material := StandardMaterial3D.new()
		material.albedo_texture = load(FOLDER.path_join("skins").path_join(skin + ".png"))
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_skins[skin] = material
	return _skins[skin]


## The idle and run animations from the kit's own files, looping, made once.
static func library() -> AnimationLibrary:
	if _library == null:
		_library = AnimationLibrary.new()
		_library.add_animation(&"idle", _looping("idle.fbx", "Root|Idle"))
		_library.add_animation(&"run", _looping("run.fbx", "Root|Run"))
	return _library


## Stands idle, or runs at the pace of [param speed], metres per second.
func set_speed(speed: float) -> void:
	if _player == null:
		return
	if speed < STILL:
		if _player.current_animation != String(IDLE):
			_player.play(IDLE, 0.2)
		_player.speed_scale = 1.0
		return
	if _player.current_animation != String(RUN):
		_player.play(RUN, 0.2)
	_player.speed_scale = maxf(speed / (RUN_PACE * _height / 1.8), SLOWEST)


## The animation playing, for tests: [constant IDLE] or [constant RUN].
func playing() -> StringName:
	return StringName(_player.current_animation) if _player else &""


static func _looping(file: String, animation_name: String) -> Animation:
	var source := load(FOLDER + file) as PackedScene
	var animation := Animation.new()
	if source:
		var root := source.instantiate()
		var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player and player.has_animation(animation_name):
			animation = player.get_animation(animation_name).duplicate(true)
		root.free()
	animation.loop_mode = Animation.LOOP_LINEAR
	return animation
