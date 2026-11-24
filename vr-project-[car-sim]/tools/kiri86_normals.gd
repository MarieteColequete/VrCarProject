extends SceneTree
## Makes the Kiri '86's normal maps from the height maps it ships with, once, so the game does not
## convert them at load. Run from the project folder:
## godot --headless --path . -s res://tools/kiri86_normals.gd

const TEXTURES := "res://assets/sketchfab/kiri86/textures/"
## Each height map, the normal map made from it, and how strongly the height bumps.
const MAPS := [
	["Carbadges_misc_U_height.jpeg", "Carbadges_misc_U_normal.png", 4.0],
	["Numberplates_Misk_U_Height.png", "Numberplates_Misk_U_normal.png", 4.0],
	["RB1c_Tire_1k_Height.jpeg", "RB1c_Tire_1k_normal.png", 6.0],
]


func _init() -> void:
	for map: Array in MAPS:
		var image := Image.load_from_file(ProjectSettings.globalize_path(TEXTURES + map[0]))
		image.convert(Image.FORMAT_RGBA8)
		image.bump_map_to_normal_map(map[2])
		image.save_png(ProjectSettings.globalize_path(TEXTURES + map[1]))
		print("made ", map[1])
	quit()
