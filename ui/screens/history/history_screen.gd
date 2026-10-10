extends Control


func _ready() -> void:
	$Margin/Column/Back.pressed.connect(func(): get_tree().change_scene_to_file("res://ui/screens/start/start_screen.tscn"))
	var list: VBoxContainer = $Margin/Column/Scroll/List
	if Global.session_history.is_empty():
		_add_entry(list, "Chưa có buổi tập hoàn thành. Kết quả sẽ được lưu tự động khi bạn hoàn thành một map.")
	for index in range(Global.session_history.size() - 1, -1, -1):
		var entry: Dictionary = Global.session_history[index]
		var text := "%s UTC  |  Map %d — Mức %d\nLần hợp lệ: %d  •  Chưa hợp lệ: %d  •  Ổn định: %d/3\n%s" % [
			str(entry.get("completed_at_utc", "")).replace("T", " "), int(entry.get("map_id", 1)),
			int(entry.get("difficulty", 1)), int(entry.get("valid_reps", 0)), int(entry.get("rejected_reps", 0)),
			int(entry.get("stability", 0)), str(entry.get("evaluation", ""))]
		if entry.has("bonus_points"):
			text += "  •  Điểm thưởng: %d" % int(entry.bonus_points)
		_add_entry(list, text)


func _add_entry(list: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 20)
	list.add_child(label)
	list.add_child(HSeparator.new())
