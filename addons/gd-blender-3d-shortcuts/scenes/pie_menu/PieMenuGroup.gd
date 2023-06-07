@tool
extends Control
const PieMenuScn = preload("PieMenu.tscn")

signal item_focused(menu, index)
signal item_selected(menu, index)
signal item_cancelled(menu)

const item4 = [
	["Normal", 0], ["Unshaded", 1], ["Lighting", 2], ["Overdraw", 3], ["Wireframe", 4],
	[
		"Others",
		[
			["Shadows", 
				[
					["Shadow Atlas", 9], ["Directional Shadow Atlas", 10]
				]
			],
			["SDFGI", 
				[
					["SDFGI", 16], ["SDFGI Probes", 17], ["GI Buffer", 18]
				]
			],
			["Environment", 
				[
					["SSAO", 12], ["SSIL", 13]
				]
			],
			["Misc", 
				[
					["Scene Luminance", 11], ["Disable LOD", 19], ["Cluster Reflection Probes", 23]
				]
			],
		]
	],
	[
		"Others2",
		[
			["Shadows", 
				[
					["Shadow Atlas", 9], ["Directional Shadow Atlas", 10]
				]
			],
			["SDFGI", 
				[
					["SDFGI", 16], ["SDFGI Probes", 17], ["GI Buffer", 18]
				]
			],
			["Environment", 
				[
					["SSAO", 12], ["SSIL", 13]
				]
			],
			["Misc", 
				[
					["Scene Luminance", 11], ["Disable LOD", 19], ["Cluster Reflection Probes", 23]
				]
			],
		]
	]
]

var root
var page_index = [0]
var theme_source_node = self : set = set_theme_source_node


func _ready():
	hide()
	# TODO: REMOVE!!!
	populate_menu(item4, PieMenuScn.instantiate())

# TODO: REMOVE!!!
func _unhandled_key_input(event):
	if event.is_action_pressed("ui_accept"):
		popup(get_global_mouse_position())

func _on_item_cancelled(pie_menu):
	back()
	emit_signal("item_cancelled", pie_menu)

func _on_item_focused(index, pie_menu):
	var current_menu = get_current_menu()
	if current_menu == pie_menu:
		emit_signal("item_focused", current_menu, index)

func _on_item_selected(index):
	var last_menu = get_current_menu()
	page_index.append(index)
	var current_menu = get_current_menu()
	if current_menu:
		current_menu.selected_index = -1
		if current_menu.pie_menus.size() > 0: # Has next page
			current_menu.popup(global_position)
	else:
		# Final selection, revert page index
		if page_index.size() > 1:
			page_index.pop_back()
		last_menu = get_current_menu()
		page_index = [0]
		hide()
		emit_signal("item_selected", last_menu, index)

func popup(pos):
	global_position = pos
	var pie_menu = get_current_menu()
	pie_menu.popup(global_position)
	show()

func populate_menu(items, pie_menu):
	add_child(pie_menu)
	if not root:
		root = pie_menu
		root.connect("item_focused", _on_item_focused.bind(pie_menu))
		root.connect("item_selected", _on_item_selected)
		root.connect("item_cancelled", _on_item_cancelled.bind(pie_menu))

	pie_menu.items = items

	for i in items.size():
		var item = items[i]
		var is_array = item is Array
		# var name = item if not is_array else item[0]
		var value = null if not is_array else item[1]
		if value is Array:
			var new_pie_menu = PieMenuScn.instantiate()
			new_pie_menu.connect("item_focused", _on_item_focused.bind(new_pie_menu))
			new_pie_menu.connect("item_selected", _on_item_selected)
			new_pie_menu.connect("item_cancelled", _on_item_cancelled.bind(new_pie_menu))
			
			populate_menu(value, new_pie_menu)
			pie_menu.pie_menus.append(new_pie_menu)
		else:
			pie_menu.pie_menus.append(null)
	return pie_menu

func clear_menu():
	if root:
		root.queue_free()

func back():
	var last_menu = get_current_menu()
	last_menu.hide()
	page_index.pop_back()
	if page_index.size() == 0:
		page_index = [0]
		hide()
		return
	else:
		var current_menu = get_current_menu()
		if current_menu:
			current_menu.popup(global_position)

func get_menu(indexes=[0]):
	var pie_menu = root
	for i in indexes.size():
		if i == 0:
			continue # root
		
		var page = indexes[i]
		pie_menu = pie_menu.pie_menus[page]
	return pie_menu

func get_current_menu():
	return get_menu(page_index)

func set_theme_source_node(v):
	theme_source_node = v
	if not root:
		return
	
	for pie_menu in root.pie_menus:
		if pie_menu:
			pie_menu.theme_source_node = theme_source_node
