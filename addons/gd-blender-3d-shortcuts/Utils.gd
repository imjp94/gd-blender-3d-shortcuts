static func apply_transform(nodes, transform, cache_global_transforms):
	var i = 0
	for node in nodes:
		var cache_global_transform = cache_global_transforms[i]
		node.global_transform.origin = cache_global_transform.origin
		node.global_transform.origin += cache_global_transform.basis.get_rotation_quaternion() * transform.origin
		node.global_transform.basis.x = cache_global_transform.basis * transform.basis.x
		node.global_transform.basis.y = cache_global_transform.basis * transform.basis.y
		node.global_transform.basis.z = cache_global_transform.basis * transform.basis.z
		i += 1

static func apply_global_transform(nodes, transform, cache_transforms):
	var i = 0
	for node in nodes:
		node.global_transform = transform * cache_transforms[i]
		i += 1

static func revert_transform(nodes, cache_global_transforms):
	var i = 0
	for node in nodes:
		node.global_transform = cache_global_transforms[i]
		i += 1

static func reset_translation(nodes):
	for node in nodes:
		node.transform.origin = Vector3.ZERO

static func reset_rotation(nodes):
	for node in nodes:
		var scale = node.transform.basis.get_scale()
		node.transform.basis = Basis().scaled(scale)

static func reset_scale(nodes):
	for node in nodes:
		var quat = node.transform.basis.get_rotation_quaternion()
		node.transform.basis = Basis(quat)

static func hide_nodes(nodes, is_hide=true):
	for node in nodes:
		node.visible = !is_hide

static func recursive_get_children(node):
	var children = node.get_children()
	if children.size() == 0:
		return []
	else:
		for child in children:
			children += recursive_get_children(child)
		return children

static func get_spatial_editor(base_control):
	var children = recursive_get_children(base_control)
	for child in children:
		if child.get_class() == "Node3DEditor":
			return child

static func get_spatial_editor_viewport_container(spatial_editor):
	var children = recursive_get_children(spatial_editor)
	for child in children:
		if child.get_class() == "Node3DEditorViewportContainer":
			return child

static func get_spatial_editor_viewports(spatial_editor_viewport):
	var children = recursive_get_children(spatial_editor_viewport)
	var spatial_editor_viewports = []
	for child in children:
		if child.get_class() == "Node3DEditorViewport":
			spatial_editor_viewports.append(child)
	return spatial_editor_viewports

static func get_spatial_editor_viewport_viewport(spatial_editor_viewport):
	var children = recursive_get_children(spatial_editor_viewport)
	for child in children:
		if child.get_class() == "SubViewport":
			return child

static func get_spatial_editor_viewport_control(spatial_editor_viewport):
	var children = recursive_get_children(spatial_editor_viewport)
	for child in children:
		if child.get_class() == "Control":
			return child

static func get_focused_spatial_editor_viewport(spatial_editor_viewports):
	for viewport in spatial_editor_viewports:
		var viewport_control = get_spatial_editor_viewport_control(viewport)
		if viewport_control.get_rect().has_point(viewport_control.get_local_mouse_position()):
			return viewport

static func get_snap_dialog(spatial_editor):
	var children = recursive_get_children(spatial_editor)
	for child in children:
		if child.get_class() == "ConfirmationDialog":
			if child.title == "Snap Settings":
				return child

static func get_snap_dialog_line_edits(snap_dialog):
	var line_edits = []
	for child in recursive_get_children(snap_dialog):
		if child.get_class() == "LineEdit":
			line_edits.append(child)
	return line_edits

static func get_spatial_editor_local_space_button(spatial_editor):
	var children = recursive_get_children(spatial_editor)
	for child in children:
		if child.get_class() == "Button":
			if child.shortcut:
				if child.shortcut.get_as_text() == OS.get_keycode_string(KEY_T):# TODO: Check if user has custom shortcut
					return child

static func get_spatial_editor_snap_button(spatial_editor):
	var children = recursive_get_children(spatial_editor)
	for child in children:
		if child.get_class() == "Button":
			if child.shortcut:
				if child.shortcut.get_as_text() == OS.get_keycode_string(KEY_Y):# TODO: Check if user has custom shortcut
					return child

static func project_on_plane(camera, screen_point, plane):
	var from = camera.project_ray_origin(screen_point)
	var dir = camera.project_ray_normal(screen_point)
	var intersection = plane.intersects_ray(from, dir)
	return intersection if intersection else Vector3.ZERO

static func transform_to_plane(t):
	var a = t.basis.x
	var b = t.basis.z
	var c = a + b
	var o = t.origin
	return Plane(a + o, b + o, c + o)

# Return new position when out of bounds
static func infinite_rect(rect, from, to):
	# Clamp from position to rect first, so it won't hit current side
	from = Vector2(clamp(from.x, rect.position.x + 2, rect.size.x - 2), clamp(from.y, rect.position.y + 2, rect.size.y - 2))
	# Intersect with sides of rect
	var intersection
	# Top
	intersection = Geometry2D.segment_intersects_segment(rect.position, Vector2(rect.size.x, rect.position.y), from, to)
	if intersection:
		return intersection
	# Left
	intersection = Geometry2D.segment_intersects_segment(rect.position, Vector2(rect.position.x, rect.size.y), from, to)
	if intersection:
		return intersection
	# Right
	intersection = Geometry2D.segment_intersects_segment(rect.size, Vector2(rect.size.x, rect.position.y), from, to)
	if intersection:
		return intersection
	# Bottom
	intersection = Geometry2D.segment_intersects_segment(rect.size, Vector2(rect.position.x, rect.size.y), from, to)
	if intersection:
		return intersection
	return null

static func draw_axis(im, origin, axis, length, color):
	var from = origin + (-axis * length / 2)
	var to = origin + (axis * length / 2)
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(color)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()

static func draw_dashed_line(canvas_item, from, to, color, width, dash_length = 5, cap_end = false, antialiased = false):
	# See https://github.com/juddrgledhill/godot-dashed-line/blob/master/line_harness.gd
	var length = (to - from).length()
	var normal = (to - from).normalized()
	var dash_step = normal * dash_length
	
	if length < dash_length: #not long enough to dash
		canvas_item.draw_line(from, to, color, width, antialiased)
		return

	else:
		var draw_flag = true
		var segment_start = from
		var steps = length/dash_length
		for start_length in range(0, steps + 1):
			var segment_end = segment_start + dash_step
			if draw_flag:
				canvas_item.draw_line(segment_start, segment_end, color, width, antialiased)

			segment_start = segment_end
			draw_flag = !draw_flag
		
		if cap_end:
			canvas_item.draw_line(segment_start, to, color, width, antialiased)
