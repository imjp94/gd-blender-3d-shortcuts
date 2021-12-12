extends "res://addons/gd-blender-3d-shortcuts/actions/Action.gd"

const Utils = preload("../Utils.gd")

var spatial_editor_viewport


func _init(p_editor_plugin).(p_editor_plugin):
	pass

func _ready():
	var spatial_editor = Utils.get_spatial_editor(editor_plugin.get_editor_interface().get_base_control())
	var spatial_editor_viewport_container = Utils.get_spatial_editor_viewport_container(spatial_editor)
	if spatial_editor_viewport_container:
		spatial_editor_viewport = Utils.get_spatial_editor_viewport(spatial_editor_viewport_container)

func _input(event):
	if event is InputEventKey:
		if event.pressed:
			match event.scancode:
				KEY_Z:
					if not (event.control or event.alt or event.shift) and not editor_plugin.focus_action:
						switch_display_mode()

func switch_display_mode():
	if spatial_editor_viewport:
		if spatial_editor_viewport.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME:
			spatial_editor_viewport.debug_draw = 0
		else:
			spatial_editor_viewport.debug_draw += 1
