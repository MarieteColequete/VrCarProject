@tool
extends EditorPlugin
## The Map Kit: a dock for building maps in the editor. See [MapKitDock].

var _dock: MapKitDock


func _enter_tree() -> void:
	_dock = MapKitDock.new()
	_dock.plugin = self
	add_dock(_dock)


func _exit_tree() -> void:
	if _dock:
		remove_dock(_dock)
		_dock.queue_free()
		_dock = null
