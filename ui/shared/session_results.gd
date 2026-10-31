extends Node
const Display = preload("res://ui/shared/session_display.gd")
var summary: Dictionary = {}
## Presentation only: the map controller still calculates and saves results.
var panel: PanelContainer
var source: Label
var content: VBoxContainer
var backdrop: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var level := get_parent()
	level.get_node("ExerciseSession").session_completed.connect(func(data: Dictionary):
		summary = data.duplicate(true)
		if panel.visible: _refresh())
	panel = level.get_node("UI/ResultPanel")
	source = level.get_node("UI/ResultPanel/MarginContainer/VBoxContainer/ResultLabel")
	panel.theme = preload("res://assets/shared/ui/game_theme.tres")
	panel.position = Vector2(166, 50)
	panel.size = Vector2(820, 548)
	source.hide()
	content = source.get_parent()
	content.add_theme_constant_override("separation", 8)
	var old_button: Button = content.get_node("ResultButton")
	old_button.text = "CHỌN MỨC ĐỘ"
	old_button.custom_minimum_size.y = 44
	backdrop = ColorRect.new()
	backdrop.color = Color(0.015, 0.035, 0.025, 0.8)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.get_parent().add_child(backdrop)
	panel.get_parent().move_child(backdrop, panel.get_index())
	backdrop.hide()
	panel.visibility_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	backdrop.visible = panel.visible
	if not panel.visible: return
	for child in content.get_children():
		if child.has_meta("result_generated"):
			content.remove_child(child)
			child.queue_free()
	var title := _label(Display.status(summary).to_upper() if summary.has("status") else "HOÀN THÀNH BUỔI TẬP", 28)
	_insert(title, 0)
	var map_id := int(get_parent().scene_file_path.get_slice("map_", 1).get_slice("/", 0))
	_insert(_label("Map %d  •  Tốc độ %.1fx" % [map_id, Global.speed_multiplier], 20), 1)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 8)
	_insert(grid, 2)
	var notes := PackedStringArray()
	for line in source.text.split("\n", false):
		if line.begins_with("HOÀN THÀNH"): continue
		if line.begins_with("Lần") or line.begins_with("Số hiệp") or line.begins_with("Điểm thưởng") or line.begins_with("Ổn định"):
			var card := PanelContainer.new()
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var style := StyleBoxFlat.new()
			style.bg_color = Color("e8dbad")
			style.content_margin_left = 14
			style.content_margin_right = 14
			style.content_margin_top = 10
			style.content_margin_bottom = 10
			card.add_theme_stylebox_override("panel", style)
			card.add_child(_label(line, 20))
			grid.add_child(card)
		else:
			notes.append(line)
	_insert(_label("\n".join(notes), 18), 3)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 64
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var information := _label(Display.compact_details(summary), 18)
	information.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(information)
	_insert(scroll, 4)
	scroll.hide()
	var detail_toggle := Button.new()
	detail_toggle.text = "XEM CHI TIẾT"
	detail_toggle.toggle_mode = true
	detail_toggle.toggled.connect(func(open: bool):
		scroll.visible = open
		detail_toggle.text = "THU GỌN" if open else "XEM CHI TIẾT")
	_insert(detail_toggle, 4)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_insert(spacer, 4)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	_insert(actions, content.get_child_count())
	for action in [["TẬP LẠI", ""], ["CHỌN MAP", "res://ui/screens/map_selection/level_selection.tscn"], ["LỊCH SỬ", "res://ui/screens/history/history_screen.tscn"]]:
		var button := Button.new()
		button.text = action[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 48
		var path: String = action[1]
		button.pressed.connect(func():
			get_tree().paused = false
			if path.is_empty(): get_tree().reload_current_scene()
			else: get_tree().change_scene_to_file(path))
		actions.add_child(button)
		if path.is_empty():
			button.text = "TẬP LẠI  ›"
			button.add_theme_font_size_override("font_size", 23)
			button.custom_minimum_size.x = 260
			button.grab_focus()
	var focus_items: Array[Control] = [detail_toggle, content.get_node("ResultButton")]
	for child in actions.get_children(): focus_items.append(child)
	for index in range(focus_items.size()):
		focus_items[index].focus_next = focus_items[index].get_path_to(focus_items[(index + 1) % focus_items.size()])
		focus_items[index].focus_previous = focus_items[index].get_path_to(focus_items[(index - 1 + focus_items.size()) % focus_items.size()])

func _insert(control: Control, index: int) -> void:
	control.set_meta("result_generated", true)
	content.add_child(control)
	content.move_child(control, index)

func _label(value: String, font_size: int) -> Label:
	var item := Label.new()
	item.text = value
	item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_size_override("font_size", font_size)
	return item
