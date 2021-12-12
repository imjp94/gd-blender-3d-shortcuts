extends "res://addons/gd-blender-3d-shortcuts/actions/Action.gd"


func _init(p_editor_plugin).(p_editor_plugin):
	pass

func forward_spatial_gui_input(camera, event):
	if not editor_plugin.focus_action:
		if editor_plugin.get_editor_interface().get_selection().get_transformable_selected_nodes().size() > 0:
			if event is InputEventKey:
				if event.pressed:
					match event.scancode:
						KEY_H:
							commit_hide_nodes()
							return true
	return false

func commit_hide_nodes():
	var undo_redo = editor_plugin.get_undo_redo()
	var nodes = editor_plugin.get_editor_interface().get_selection().get_transformable_selected_nodes()
	undo_redo.create_action("Hide Nodes")
	undo_redo.add_do_method(self, "hide_nodes", nodes, true)
	undo_redo.add_undo_method(self, "hide_nodes", nodes, false)
	undo_redo.commit_action()

static func hide_nodes(nodes, is_hide=true):
	for node in nodes:
		node.visible = !is_hide
