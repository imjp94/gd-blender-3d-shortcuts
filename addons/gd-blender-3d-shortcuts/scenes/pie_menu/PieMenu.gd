tool
extends Control

signal item_selected(index)
signal item_focused(index)
signal item_cancelled()

const button_margin = 6

export(Array, String) var items = [] setget set_items
export var selected_index = -1 setget set_selected_index
export var radius = 100.0 setget set_radius

var buttons = []
var pie_menus = []

var focused_index = -1
var theme_source_node = self setget set_theme_source_node
var grow_with_max_button_width = false


func _ready():
	set_items(items)
	set_selected_index(selected_index)
	set_radius(radius)
	hide()
	connect("visibility_changed", self, "_on_visiblity_changed")

func _input(event):
	if visible:
		if event is InputEventKey:
			if event.pressed:
				match event.scancode:
					KEY_ESCAPE:
						cancel()
		if event is InputEventMouseMotion:
			focus_item()
			get_tree().set_input_as_handled()
		if event is InputEventMouseButton:
			if event.pressed:
				match event.button_index:
					BUTTON_LEFT:
						select_item(focused_index)
						get_tree().set_input_as_handled()
					BUTTON_RIGHT:
						cancel()
						get_tree().set_input_as_handled()

func _on_visiblity_changed():
	if not visible:
		if selected_index != focused_index: # Cancellation
			focused_index = selected_index

func cancel():
	hide()
	get_tree().set_input_as_handled()
	emit_signal("item_cancelled")

func select_item(index):
	set_button_style(selected_index, "normal", "normal")
	selected_index = index
	focused_index = selected_index
	hide()
	emit_signal("item_selected", selected_index)

func focus_item():
	var pos = get_global_mouse_position()
	var count = max(buttons.size(), 1)
	var angle_offset = 2 * PI / count
	var angle = rect_global_position.angle_to_point(pos) + PI / 2 # -90 deg initial offset
	if angle < 0:
		angle += 2 * PI
	
	var index = (angle / angle_offset)
	var decimal = index - floor(index)
	index = floor(index)
	if decimal >= 0.5:
		index += 1
	if index > buttons.size()-1:
		index = 0
	
	set_button_style(focused_index, "normal", "normal")
	focused_index = index
	set_button_style(focused_index, "normal", "hover")
	set_button_style(selected_index, "normal", "focus")
	emit_signal("item_focused", focused_index)

func popup(pos):
	rect_global_position = pos
	show()

func populate_menu():
	clear_menu()
	buttons = []
	for i in items.size():
		var item = items[i]
		var is_array = item is Array
		var name = item if not is_array else item[0]
		var value = null if not is_array else item[1]
		var button = Button.new()
		button.grow_horizontal = Control.GROW_DIRECTION_BOTH
		button.text = name
		if value != null:
			button.set_meta("value", value)
		button.margin_right += button_margin
		button.margin_bottom += button_margin
		buttons.append(button)
		set_button_style(i, "hover", "hover")
		set_button_style(i, "pressed", "pressed")
		set_button_style(i, "focus", "focus")
		set_button_style(i, "disabled", "disabled")
		set_button_style(i, "normal", "normal")
		add_child(button)
	align()

	set_button_style(selected_index, "normal", "focus")

func align():
	var final_radius = radius
	if grow_with_max_button_width:
		var max_button_width = 0.0
		for button in buttons:
			max_button_width = max(max_button_width, button.rect_size.x)
		final_radius = max(radius, max_button_width)
	var count = max(buttons.size(), 1)
	var angle_offset = 2 * PI / count
	var angle = PI / 2 # 90 deg initial offset
	for button in buttons:
		button.rect_position = Vector2(final_radius, 0.0).rotated(angle) - (button.rect_size / 2.0)
		angle += angle_offset

func clear_menu():
	for button in buttons:
		button.queue_free()

func set_button_style(index, name, source):
	if index < 0 or index > buttons.size() - 1:
		return

	buttons[index].set("custom_styles/%s" % name, theme_source_node.get_stylebox(source, "Button"))

func set_items(v):
	items = v
	if is_inside_tree():
		populate_menu()

func set_selected_index(v):
	set_button_style(selected_index, "normal", "normal")
	selected_index = v
	set_button_style(selected_index, "normal", "focus")

func set_radius(v):
	radius = v
	align()

func set_theme_source_node(v):
	theme_source_node = v
	for pie_menu in pie_menus:
		if pie_menu:
			pie_menu.theme_source_node = theme_source_node
