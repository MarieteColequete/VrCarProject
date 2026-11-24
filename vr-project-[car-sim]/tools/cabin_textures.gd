extends SceneTree
## Makes the grey carpet's colour map from the ambientCG carpet's blue one, once, so the cabin's
## carpet takes its tint from the car. Run from the project folder:
## godot --headless --path . -s res://tools/cabin_textures.gd

const SET := "res://assets/ambientcg/Carpet012/Carpet012_1K-JPG_"


func _init() -> void:
	var image := Image.load_from_file(ProjectSettings.globalize_path(SET + "Color.jpg"))
	image.convert(Image.FORMAT_RGB8)
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			var grey := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
			# Brightened back to the blue's own lightness, so the tint sets the shade.
			grey = clampf(grey * 1.6, 0.0, 1.0)
			image.set_pixel(x, y, Color(grey, grey, grey))
	image.save_jpg(ProjectSettings.globalize_path(SET + "Grey.jpg"), 0.92)
	print("made Carpet012_1K-JPG_Grey.jpg")
	quit()
