tool
extends EditorPlugin

const Utils = preload("Utils.gd")

const DEFAULT_LINE_COLOR = Color.white

enum SESSION {
	TRANSLATE,
	ROTATE,
	SCALE,
	NONE
}

var translate_snap_line_edit
var rotate_snap_line_edit
var scale_snap_line_edit
var local_space_button
var snap_button
var overlay_control
var spatial_editor_viewports


var overlay_label = Label.new()
var axis_ig
var axis_ig_material = SpatialMaterial.new()

var current_session = SESSION.NONE
var pivot_point = Vector3.ZERO
var constraint_axis = Vector3.ONE
var translate_snap = 1.0
var rotate_snap = deg2rad(15.0)
var scale_snap = 0.1
var is_snapping = false
var is_global = true
var axis_length = 1000
var precision_mode = false
var precision_factor = 0.1

var _is_editing = false
var _camera
var _editing_transform = Transform.IDENTITY
var _applying_transform = Transform.IDENTITY
var _last_world_pos = Vector3.ZERO
var _init_angle = NAN
var _last_angle = 0
var _last_center_offset = 0
var _cummulative_center_offset = 0
var _max_x = 0
var _min_x = 0
var _cache_global_transforms = []
var _cache_transforms = [] # Nodes' local transform relative to pivot_point
var _input_string = ""
var _is_global_on_session = false
var _is_warping_mouse = false


func _init():
	axis_ig_material.flags_unshaded = true
	axis_ig_material.vertex_color_use_as_albedo = true

	overlay_label.set("custom_colors/font_color_shadow", Color.black)

func _ready():
	var spatial_editor = Utils.get_spatial_editor(get_editor_interface().get_base_control())
	var snap_dialog = Utils.get_snap_dialog(spatial_editor)
	var snap_dialog_line_edits = Utils.get_snap_dialog_line_edits(snap_dialog)
	translate_snap_line_edit = snap_dialog_line_edits[0]
	rotate_snap_line_edit = snap_dialog_line_edits[1]
	scale_snap_line_edit = snap_dialog_line_edits[2]
	translate_snap_line_edit.connect("text_changed", self, "_on_snap_value_changed", [SESSION.TRANSLATE])
	rotate_snap_line_edit.connect("text_changed", self, "_on_snap_value_changed", [SESSION.ROTATE])
	scale_snap_line_edit.connect("text_changed", self, "_on_snap_value_changed", [SESSION.SCALE])
	local_space_button = Utils.get_spatial_editor_local_space_button(spatial_editor)
	local_space_button.connect("toggled", self, "_on_local_space_button_toggled")
	snap_button = Utils.get_spatial_editor_snap_button(spatial_editor)
	snap_button.connect("toggled", self, "_on_snap_button_toggled")
	var spatial_editor_viewport_container = Utils.get_spatial_editor_viewport_container(spatial_editor)
	if spatial_editor_viewport_container:
		spatial_editor_viewports = Utils.get_spatial_editor_viewports(spatial_editor_viewport_container)
	sync_settings()

func _input(event):
	if event is InputEventKey:
		if event.pressed:
			match event.scancode:
				KEY_Z:
					if not (event.control or event.alt or event.shift) and current_session == SESSION.NONE:
						switch_display_mode()
			# Hacky way to intercept default shortcut behavior when in session
			if current_session != SESSION.NONE:
				var event_text = event.as_text()
				if event_text.begins_with("Kp"):
					append_input_string(event_text.replace("Kp ", ""))
					get_tree().set_input_as_handled()
				match event.scancode:
					KEY_Y:
						if event.shift:
							toggle_constraint_axis(Vector3.RIGHT + Vector3.BACK)
						else:
							toggle_constraint_axis(Vector3.UP)
						get_tree().set_input_as_handled()
	
	if event is InputEventMouseMotion:
		if current_session != SESSION.NONE and overlay_control:
			# Infinite mouse movement
			var rect = overlay_control.get_rect()
			var local_mouse_pos = overlay_control.get_local_mouse_position()
			if not rect.has_point(local_mouse_pos):
				var warp_pos = Utils.infinite_rect(rect, local_mouse_pos, -event.speed.normalized() * rect.size.length())
				if warp_pos:
					Input.warp_mouse_position(overlay_control.rect_global_position + warp_pos)
					_is_warping_mouse = true

func _on_snap_value_changed(text, session):
	match session:
		SESSION.TRANSLATE:
			translate_snap = float(text)
		SESSION.ROTATE:
			rotate_snap = deg2rad(float(text))
		SESSION.SCALE:
			scale_snap = float(text) / 100.0

func _on_local_space_button_toggled(pressed):
	is_global = !pressed

func _on_snap_button_toggled(pressed):
	is_snapping = pressed

func handles(object):
	if object is Spatial:
		_is_editing = get_editor_interface().get_selection().get_selected_nodes().size()
		return _is_editing
	else:
		_is_editing = get_editor_interface().get_selection().get_transformable_selected_nodes().size() > 0
		return _is_editing
	return false

func edit(object):
	var scene_root = get_editor_interface().get_edited_scene_root()
	if scene_root:
		# Let editor free ImmediateGeometry as the scene closed,
		# then create new instance whenever needed
		if not is_instance_valid(axis_ig):
			axis_ig = ImmediateGeometry.new()
			axis_ig.material_override = axis_ig_material
		if axis_ig.get_parent() == null:
			scene_root.get_parent().add_child(axis_ig)
		else:
			if axis_ig.get_parent() != scene_root:
				axis_ig.get_parent().remove_child(axis_ig)
				scene_root.get_parent().add_child(axis_ig)

func forward_spatial_gui_input(camera, event):
	var forward = false
	if current_session == SESSION.NONE:
		if _is_editing:
			if event is InputEventKey:
				if event.pressed:
					match event.scancode:
						KEY_G:
							start_session(SESSION.TRANSLATE, camera, event)
							forward = true
						KEY_R:
							start_session(SESSION.ROTATE, camera, event)
							forward = true
						KEY_S:
							if not event.control:
								start_session(SESSION.SCALE, camera, event)
								forward = true
						KEY_H:
							commit_hide_nodes()
	else:
		if event is InputEventKey:
			# Not sure why event.pressed always return false for numpad keys
			match event.scancode:
				KEY_KP_SUBTRACT:
					toggle_input_string_sign()
					return true
				KEY_KP_ENTER:
					commit_session()
					end_session()
					return true
			
			if event.scancode == KEY_SHIFT:
				precision_mode = event.pressed
				forward = true

			if event.pressed:
				var event_text = event.as_text()
				if append_input_string(event_text):
					return true
				match event.scancode:
					KEY_G:
						if current_session != SESSION.TRANSLATE:
							revert()
							clear_session()
							start_session(SESSION.TRANSLATE, camera, event)
							return true
					KEY_R:
						if current_session != SESSION.ROTATE:
							revert()
							clear_session()
							start_session(SESSION.ROTATE, camera, event)
							return true
					KEY_S:
						if not event.control:
							if current_session != SESSION.SCALE:
								revert()
								clear_session()
								start_session(SESSION.SCALE, camera, event)
								return true
					KEY_X:
						if event.shift:
							toggle_constraint_axis(Vector3.UP + Vector3.BACK)
						else:
							toggle_constraint_axis(Vector3.RIGHT)
						return true
					KEY_Y:
						if event.shift:
							toggle_constraint_axis(Vector3.RIGHT + Vector3.BACK)
						else:
							toggle_constraint_axis(Vector3.UP)
						return true
					KEY_Z:
						if event.shift:
							toggle_constraint_axis(Vector3.RIGHT + Vector3.UP)
						else:
							toggle_constraint_axis(Vector3.BACK)
						return true
					KEY_MINUS:
						toggle_input_string_sign()
						return true
					KEY_BACKSPACE:
						trim_input_string()
						return true
					KEY_ENTER:
						commit_session()
						end_session()
						return true
					KEY_ESCAPE:
						revert()
						end_session()
						return true
		
		if event is InputEventMouseButton:
			if event.pressed:
				commit_session()
				end_session()
				forward = true

		if event is InputEventMouseMotion:
			match current_session:
				SESSION.TRANSLATE, SESSION.ROTATE, SESSION.SCALE:
					mouse_transform(event)
					update_overlays()
					forward = true

	return forward
	
func forward_spatial_draw_over_viewport(overlay):
	if current_session == SESSION.NONE:
		if overlay_label.get_parent() != null:
			overlay_label.get_parent().remove_child(overlay_label)
		return

	var editor_settings = get_editor_interface().get_editor_settings()
	var line_color = DEFAULT_LINE_COLOR
	if editor_settings.has_setting("editors/3d/selection_box_color"):
		line_color = editor_settings.get_setting("editors/3d/selection_box_color")
	var snapped = "snapped" if is_snapping else ""
	var global_or_local = "global" if is_global else "local"
	var along_axis = ""
	if not constraint_axis.is_equal_approx(Vector3.ONE):
		if constraint_axis.x > 0:
			along_axis = "X"
		if constraint_axis.y > 0:
			along_axis += ", Y" if along_axis.length() else "Y"
		if constraint_axis.z > 0:
			along_axis += ", Z" if along_axis.length() else "Z"
	if along_axis.length():
		along_axis = "along " + along_axis

	if overlay_label.get_parent() == null:
		overlay_control.add_child(overlay_label)
		overlay_label.set_anchors_and_margins_preset(Control.PRESET_BOTTOM_LEFT)
		overlay_label.rect_position += Vector2(8, -8)
	match current_session:
		SESSION.TRANSLATE:
			var translation = _applying_transform.origin
			overlay_label.text = ("Translate (%.3f, %.3f, %.3f) %s %s %s" % [translation.x, translation.y, translation.z, global_or_local, along_axis, snapped])
		SESSION.ROTATE:
			var rotation = _applying_transform.basis.get_euler()
			overlay_label.text = ("Rotate (%.3f, %.3f, %.3f) %s %s %s" % [rad2deg(rotation.x), rad2deg(rotation.y), rad2deg(rotation.z), global_or_local, along_axis, snapped])
		SESSION.SCALE:
			var scale = _applying_transform.basis.get_scale()
			overlay_label.text = ("Scale (%.3f, %.3f, %.3f) %s %s %s" % [scale.x, scale.y, scale.z, global_or_local, along_axis, snapped])
	if _input_string:
		overlay_label.text += "(%s)" % _input_string
	var is_pivot_point_behind_camera = _camera.is_position_behind(pivot_point)
	var screen_origin = overlay.rect_size / 2.0 if is_pivot_point_behind_camera else _camera.unproject_position(pivot_point)
	Utils.draw_dashed_line(overlay, screen_origin, overlay.get_local_mouse_position(), line_color, 1, 5, true, true)

func text_transform(text):
	var input_value = float(text)
	match current_session:
		SESSION.TRANSLATE:
			_applying_transform.origin = constraint_axis * input_value
		SESSION.ROTATE:
			_applying_transform.basis = Basis().rotated((-_camera.global_transform.basis.z * constraint_axis).normalized(), deg2rad(input_value))
		SESSION.SCALE:
			if constraint_axis.x:
				_applying_transform.basis.x = Vector3.RIGHT * input_value
			if constraint_axis.y:
				_applying_transform.basis.y = Vector3.UP * input_value
			if constraint_axis.z:
				_applying_transform.basis.z = Vector3.BACK * input_value
	var nodes = get_editor_interface().get_selection().get_transformable_selected_nodes()
	var t = _applying_transform
	if is_global or (constraint_axis.is_equal_approx(Vector3.ONE) and current_session == SESSION.TRANSLATE):
		t.origin += pivot_point
		Utils.apply_global_transform(nodes, t, _cache_transforms)
	else:
		Utils.apply_transform(nodes, t, _cache_global_transforms)

func mouse_transform(event):
	var nodes = get_editor_interface().get_selection().get_transformable_selected_nodes()
	var is_single_node = nodes.size() == 1
	var node1 = nodes[0]
	var is_pivot_point_behind_camera = _camera.is_position_behind(pivot_point)
	if is_nan(_init_angle):
		var screen_origin = _camera.unproject_position(pivot_point)
		_init_angle = event.position.angle_to_point(screen_origin)
	# Translation offset
	var plane_transform = _camera.global_transform
	plane_transform.origin = pivot_point
	plane_transform.basis = plane_transform.basis.rotated(plane_transform.basis.xform(Vector3.LEFT), deg2rad(90))
	if is_pivot_point_behind_camera:
		plane_transform.origin = _camera.global_transform.origin + -_camera.global_transform.basis.z * 10.0
	var plane = Utils.transform_to_plane(plane_transform)
	var axis_count = get_constraint_axis_count()
	if axis_count == 2:
		var normal = (Vector3.ONE - constraint_axis).normalized()
		if is_single_node and not is_global:
			normal = node1.global_transform.basis.xform(normal)
		var plane_dist = normal * plane_transform.origin
		plane = Plane(normal, plane_dist.x + plane_dist.y + plane_dist.z)
	var world_pos = Utils.project_on_plane(_camera, event.position, plane)
	if not is_global and is_single_node and axis_count < 3:
		var normalized_node1_basis = node1.global_transform.basis.scaled(Vector3.ONE / node1.global_transform.basis.get_scale())
		world_pos = normalized_node1_basis.xform_inv(world_pos)
	if not _last_world_pos:
		_last_world_pos = world_pos
	var offset = world_pos - _last_world_pos
	offset *= constraint_axis
	offset = offset.snapped(Vector3.ONE * 0.001)
	if _is_warping_mouse:
		offset = Vector3.ZERO
	# Rotation offset
	var screen_origin = _camera.unproject_position(pivot_point)
	if is_pivot_point_behind_camera:
		screen_origin = overlay_control.rect_size / 2.0
	var angle = event.position.angle_to_point(screen_origin) - _init_angle
	var angle_offset = angle - _last_angle
	angle_offset = stepify(angle_offset, 0.001)
	# Scale offset
	if _max_x == 0:
		_max_x = event.position.x
		_min_x = _max_x - (_max_x - screen_origin.x) * 2
	var center_value = 2 * ((event.position.x - _min_x) / (_max_x - _min_x)) - 1
	if _last_center_offset == 0:
		_last_center_offset = center_value
	var center_offset = center_value - _last_center_offset
	center_offset = stepify(center_offset, 0.001)
	if _is_warping_mouse:
		center_offset = 0
	_cummulative_center_offset += center_offset
	if not _input_string:
		match current_session:
			SESSION.TRANSLATE:
				_editing_transform = _editing_transform.translated(offset)
				_applying_transform.origin = _editing_transform.origin
				if is_snapping:
					var snap = Vector3.ONE * (translate_snap if not precision_mode else translate_snap * precision_factor)
					_applying_transform.origin = _applying_transform.origin.snapped(snap)
			SESSION.ROTATE:
				var rotation_axis = (-_camera.global_transform.basis.z * constraint_axis).normalized()
				if not rotation_axis.is_equal_approx(Vector3.ZERO):
					_editing_transform.basis = _editing_transform.basis.rotated(rotation_axis, angle_offset)
					var quat = _editing_transform.basis.get_rotation_quat()
					if is_snapping:
						var snap = Vector3.ONE * (rotate_snap if not precision_mode else rotate_snap * precision_factor)
						quat.set_euler(quat.get_euler().snapped(snap))
					_applying_transform.basis = Basis(quat)
			SESSION.SCALE:
				if constraint_axis.x:
					_editing_transform.basis.x = Vector3.RIGHT * (1 + _cummulative_center_offset)
				if constraint_axis.y:
					_editing_transform.basis.y = Vector3.UP * (1 + _cummulative_center_offset)
				if constraint_axis.z:
					_editing_transform.basis.z = Vector3.BACK * (1 + _cummulative_center_offset)
				_applying_transform.basis = _editing_transform.basis
				if is_snapping:
					var snap = Vector3.ONE * (scale_snap if not precision_mode else scale_snap * precision_factor)
					_applying_transform.basis.x = _applying_transform.basis.x.snapped(snap)
					_applying_transform.basis.y = _applying_transform.basis.y.snapped(snap)
					_applying_transform.basis.z = _applying_transform.basis.z.snapped(snap)

	var t = _applying_transform
	if is_global or (constraint_axis.is_equal_approx(Vector3.ONE) and current_session == SESSION.TRANSLATE):
		t.origin += pivot_point
		Utils.apply_global_transform(nodes, t, _cache_transforms)
	else:
		Utils.apply_transform(nodes, t, _cache_global_transforms)
	_last_world_pos = world_pos
	_last_center_offset = center_value
	_last_angle = angle
	_is_warping_mouse = false

func cache_selected_nodes_transforms():
	var nodes = get_editor_interface().get_selection().get_transformable_selected_nodes()
	var inversed_pivot_transform = Transform().translated(pivot_point).affine_inverse()
	for i in nodes.size():
		var node = nodes[i]
		_cache_global_transforms.append(node.global_transform)
		_cache_transforms.append(inversed_pivot_transform * node.global_transform)

func update_pivot_point():
	var nodes = get_editor_interface().get_selection().get_transformable_selected_nodes()
	var aabb = AABB()
	for i in nodes.size():
		var node = nodes[i]
		if i == 0:
			aabb.position = node.global_transform.origin
		aabb = aabb.expand(node.global_transform.origin)
	pivot_point = aabb.position + aabb.size / 2.0

func start_session(session, camera, event):
	if get_editor_interface().get_selection().get_transformable_selected_nodes().size() == 0:
		return
	current_session = session
	_camera = camera
	_is_global_on_session = is_global
	update_pivot_point()
	cache_selected_nodes_transforms()

	if event.alt:
		commit_reset_transform()
		end_session()
		return

	update_overlays()
	var spatial_editor_viewport = Utils.get_focused_spatial_editor_viewport(spatial_editor_viewports)
	overlay_control = Utils.get_spatial_editor_viewport_control(spatial_editor_viewport) if spatial_editor_viewport else null

func end_session():
	_is_editing = get_editor_interface().get_selection().get_transformable_selected_nodes().size() > 0
	# Manually set is_global to avoid triggering revert()
	if is_instance_valid(local_space_button):
		local_space_button.pressed = !_is_global_on_session
	is_global = _is_global_on_session
	clear_session()
	update_overlays()

func commit_session():
	var undo_redo = get_undo_redo()
	var nodes = get_editor_interface().get_selection().get_transformable_selected_nodes()
	Utils.revert_transform(nodes, _cache_global_transforms)
	undo_redo.create_action(SESSION.keys()[current_session].to_lower().capitalize())
	var t = _applying_transform
	if is_global or (constraint_axis.is_equal_approx(Vector3.ONE) and current_session == SESSION.TRANSLATE):
		t.origin += pivot_point
		undo_redo.add_do_method(Utils, "apply_global_transform", nodes, t, _cache_transforms)
	else:
		undo_redo.add_do_method(Utils, "apply_transform", nodes, t, _cache_global_transforms)
	undo_redo.add_undo_method(Utils, "revert_transform", nodes, _cache_global_transforms)
	undo_redo.commit_action()

func commit_reset_transform():
	var undo_redo = get_undo_redo()
	var nodes = get_editor_interface().get_selection().get_transformable_selected_nodes()
	match current_session:
		SESSION.TRANSLATE:
			undo_redo.create_action("Reset Translation")
			undo_redo.add_do_method(Utils, "reset_translation", nodes)
			undo_redo.add_undo_method(Utils, "revert_transform", nodes, _cache_global_transforms)
			undo_redo.commit_action()
		SESSION.ROTATE:
			undo_redo.create_action("Reset Rotation")
			undo_redo.add_do_method(Utils, "reset_rotation", nodes)
			undo_redo.add_undo_method(Utils, "revert_transform", nodes, _cache_global_transforms)
			undo_redo.commit_action()
		SESSION.SCALE:
			undo_redo.create_action("Reset Scale")
			undo_redo.add_do_method(Utils, "reset_scale", nodes)
			undo_redo.add_undo_method(Utils, "revert_transform", nodes, _cache_global_transforms)
			undo_redo.commit_action()
	current_session = SESSION.NONE

func commit_hide_nodes():
	var undo_redo = get_undo_redo()
	var nodes = get_editor_interface().get_selection().get_transformable_selected_nodes()
	undo_redo.create_action("Hide Nodes")
	undo_redo.add_do_method(Utils, "hide_nodes", nodes, true)
	undo_redo.add_undo_method(Utils, "hide_nodes", nodes, false)
	undo_redo.commit_action()

func revert():
	var nodes = get_editor_interface().get_selection().get_transformable_selected_nodes()
	Utils.revert_transform(nodes, _cache_global_transforms)
	_editing_transform = Transform.IDENTITY
	_applying_transform = Transform.IDENTITY
	_last_world_pos = Vector3.ZERO
	axis_ig.clear()

func clear_session():
	current_session = SESSION.NONE
	constraint_axis = Vector3.ONE
	pivot_point = Vector3.ZERO
	precision_mode = false
	_editing_transform = Transform.IDENTITY
	_applying_transform = Transform.IDENTITY
	_last_world_pos = Vector3.ZERO
	_init_angle = NAN
	_last_angle = 0
	_last_center_offset = 0
	_cummulative_center_offset = 0
	_max_x = 0
	_min_x = 0
	_cache_global_transforms = []
	_cache_transforms = []
	_input_string = ""
	_is_warping_mouse = false
	axis_ig.clear()

func sync_settings():
	if translate_snap_line_edit:
		translate_snap = float(translate_snap_line_edit.text)
	if rotate_snap_line_edit:
		rotate_snap = deg2rad(float(rotate_snap_line_edit.text))
	if scale_snap_line_edit:
		scale_snap = float(scale_snap_line_edit.text) / 100.0
	if local_space_button:
		is_global = !local_space_button.pressed
	if snap_button:
		is_snapping = snap_button.pressed

func switch_display_mode():
	var spatial_editor_viewport = Utils.get_focused_spatial_editor_viewport(spatial_editor_viewports)
	if spatial_editor_viewport:
		var viewport = Utils.get_spatial_editor_viewport_viewport(spatial_editor_viewport)
		if viewport.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME:
			viewport.debug_draw = 0
		else:
			viewport.debug_draw += 1

# Repeatedly applying same axis will results in toggling is_global, just like pressing xx, yy or zz in blender
func toggle_constraint_axis(axis):
	# Following order as below:
	# 1) Apply constraint on current mode
	# 2) Toggle mode
	# 3) Toggle mode again, and remove constraint
	if is_global == _is_global_on_session:
		if not constraint_axis.is_equal_approx(axis):
			# 1
			set_constraint_axis(axis)
		else:
			# 2
			set_is_global(!_is_global_on_session)
	else:
		if constraint_axis.is_equal_approx(axis):
			# 3
			set_is_global(_is_global_on_session)
			set_constraint_axis(Vector3.ONE)
		else:
			# Others situation
			set_constraint_axis(axis)

func toggle_input_string_sign():
	if _input_string.begins_with("-"):
		_input_string = _input_string.trim_prefix("-")
	else:
		_input_string = "-" + _input_string
	input_string_changed()

func trim_input_string():
	_input_string = _input_string.substr(0, _input_string.length() - 1)
	input_string_changed()

func append_input_string(text):
	text = "." if text == "Period" else text
	if text.is_valid_integer() or text == ".":
		_input_string += text
		input_string_changed()
		return true

func input_string_changed():
	if _input_string:
		text_transform(_input_string)
	else:
		_applying_transform = Transform.IDENTITY
		var nodes = get_editor_interface().get_selection().get_transformable_selected_nodes()
		Utils.revert_transform(nodes, _cache_global_transforms)
	update_overlays()

func get_constraint_axis_count():
	var axis_count = 3
	if constraint_axis.x == 0:
		axis_count -= 1
	if constraint_axis.y == 0:
		axis_count -= 1
	if constraint_axis.z == 0:
		axis_count -= 1
	return axis_count

func set_constraint_axis(v):
	revert()
	if constraint_axis != v:
		constraint_axis = v
		draw_axises()
	else:
		constraint_axis = Vector3.ONE
	if _input_string:
		text_transform(_input_string)
	update_overlays()

func set_is_global(v):
	if is_global != v:
		if is_instance_valid(local_space_button):
			local_space_button.pressed = !v
		revert()
		is_global = v
		draw_axises()
		if _input_string:
			text_transform(_input_string)
		update_overlays()

func draw_axises():
	if not constraint_axis.is_equal_approx(Vector3.ONE):
		var nodes = get_editor_interface().get_selection().get_transformable_selected_nodes()
		var axis_lines = []
		if constraint_axis.x > 0:
			axis_lines.append({"axis": Vector3.RIGHT, "color": Color.red})
		if constraint_axis.y > 0:
			axis_lines.append({"axis": Vector3.UP, "color": Color.green})
		if constraint_axis.z > 0:
			axis_lines.append({"axis": Vector3.BACK, "color": Color.blue})

		for axis_line in axis_lines:
			var axis = axis_line.get("axis")
			var color = axis_line.get("color")
			if is_global:
				var is_pivot_point_behind_camera = _camera.is_position_behind(pivot_point)
				var axis_origin = _camera.global_transform.origin + -_camera.global_transform.basis.z * 10.0 if is_pivot_point_behind_camera else pivot_point
				Utils.draw_axis(axis_ig, axis_origin, axis, axis_length, color)
			else:
				for node in nodes:
					Utils.draw_axis(axis_ig, node.global_transform.origin, node.global_transform.basis.xform(axis), axis_length, color)
