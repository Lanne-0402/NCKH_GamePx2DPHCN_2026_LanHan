extends Control

# Hàm chạy ngay khi mở Menu
func _ready():
	var highest_level := Global.get_highest_unlocked_level(Global.selected_action)
	Global.highest_unlocked_level = highest_level
	# Giả sử trong VBoxContainer, các nút của bạn tên là Button, Button2, Button3
	# Nếu cấp độ cao nhất < 2, khóa nút Mức 2 (1.5x)
	if highest_level < 2:
		$VBoxContainer/Button2.disabled = true
	else:
		$VBoxContainer/Button2.disabled = false
	# Nếu cấp độ cao nhất < 3, khóa nút Mức 3 (2.0x)
	if highest_level < 3:
		$VBoxContainer/Button3.disabled = true
	else:
		$VBoxContainer/Button3.disabled = false

func _on_button_pressed():
	Global.speed_multiplier = 1.0 
	_open_selected_map()

func _on_button_2_pressed():
	Global.speed_multiplier = 1.5
	_open_selected_map()
	
func _on_button_3_pressed():
	Global.speed_multiplier = 2.0
	_open_selected_map()


func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/screens/map_selection/level_selection.tscn")


func _open_selected_map() -> void:
	var map_scene := Global.get_selected_map_scene()
	if map_scene.is_empty():
		push_warning("Map %d chưa được triển khai." % Global.selected_action)
		return
	get_tree().change_scene_to_file(map_scene)
