@tool
class_name AssetDropTarget
extends Control
## Laid over a 3D view while a model is dragged from the Asset Library: it takes the drag, shows
## the placer's ghost where the model would stand, and places it on drop, with undo. The plugin
## adds one per 3D view when the drag starts, beside the view's container and over it, and
## removes them when it ends.

var plugin: MapKitPlugin
## The 3D view this one covers.
var viewport: SubViewport


func _init(p_plugin: MapKitPlugin, p_viewport: SubViewport) -> void:
	plugin = p_plugin
	viewport = p_viewport
	name = "MapKitDropTarget"
	mouse_filter = Control.MOUSE_FILTER_PASS


## Lies over [param container], from its parent.
func cover(container: Control) -> void:
	position = container.position
	size = container.size


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary and data.get("type") == AssetLibraryDock.DRAG_TYPE):
		return false
	var camera := viewport.get_camera_3d()
	if camera == null or plugin.edited_map() == null or not plugin.placer.is_armed():
		return false
	plugin.placer.follow(camera, _in_viewport(at))
	plugin.update_overlays()
	return true


func _drop_data(at: Vector2, _data: Variant) -> void:
	var camera := viewport.get_camera_3d()
	var road_map := plugin.edited_map()
	if camera == null or road_map == null:
		return
	plugin.placer.follow(camera, _in_viewport(at))
	plugin.placer.place_here(road_map)
	plugin.placer.disarm()


## [param at], over this control, in the 3D view's own pixels.
func _in_viewport(at: Vector2) -> Vector2:
	return at * Vector2(viewport.size) / size.max(Vector2.ONE)
