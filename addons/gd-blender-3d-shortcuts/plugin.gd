tool
extends EditorPlugin

const REGISTERED_ACTIONS = [preload("actions/VisibilityAction.gd"), 
preload("actions/TransformAction.gd"), preload("actions/DisplayModeAction.gd")]

var actions = []
var focus_action # Reference to hint which action in control over a long period of time


func _init():
	for action_class in REGISTERED_ACTIONS:
		actions.append(action_class.new(self))

func _ready():
	for action in actions:
		if action.has_method("_ready"):
			action.call("_ready")

func _input(event):
	for action in actions:
		if action.has_method("_input"):
			action.call("_input", event)

func handles(object):
	if object is Spatial:
		return !!get_editor_interface().get_selection().get_selected_nodes().size()
	else:
		return get_editor_interface().get_selection().get_transformable_selected_nodes().size() > 0
	for action in actions:
		if action.has_method("handles"):
			action.call("handles", object)
	return false

func edit(object):
	for action in actions:
		if action.has_method("edit"):
			action.call("edit", object)

func forward_spatial_gui_input(camera, event):
	var forward = false
	for action in actions:
		if action.has_method("forward_spatial_gui_input"):
			forward = action.call("forward_spatial_gui_input", camera, event)
	return forward
	
func forward_spatial_draw_over_viewport(overlay):
	for action in actions:
		if action.has_method("forward_spatial_draw_over_viewport"):
			action.call("forward_spatial_draw_over_viewport", overlay)

func get_action_by_class(cls):
	for action in actions:
		if action.get_class() == cls:
			return action
