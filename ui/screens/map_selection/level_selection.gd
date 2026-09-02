extends Control


func _ready() -> void:
	$ScrollContainer/HBoxContainer/Button3.disabled = not Global.is_map_implemented(3)
	$ScrollContainer/HBoxContainer/Button4.disabled = not Global.is_map_implemented(4)
	$ScrollContainer/HBoxContainer/Button5.disabled = not Global.is_map_implemented(5)

func _on_back_button_pressed():
	# Nút Quay lại đưa về Start Screen
	get_tree().change_scene_to_file("res://ui/screens/calibration/calibration_screen.tscn")

func _on_button_pressed():
	Global.selected_action = 1
	get_tree().change_scene_to_file("res://ui/screens/level_selection/main_menu.tscn")

func _on_button_2_pressed():
	Global.selected_action = 2
	get_tree().change_scene_to_file("res://ui/screens/level_selection/main_menu.tscn")
	
func _on_button_3_pressed():
	if not Global.is_map_implemented(3):
		return
	Global.selected_action = 3
	get_tree().change_scene_to_file("res://ui/screens/level_selection/main_menu.tscn")

func _on_button_4_pressed():
	if not Global.is_map_implemented(4):
		return
	Global.selected_action = 4
	get_tree().change_scene_to_file("res://ui/screens/level_selection/main_menu.tscn")

func _on_button_5_pressed():
	if not Global.is_map_implemented(5):
		return
	Global.selected_action = 5
	get_tree().change_scene_to_file("res://ui/screens/level_selection/main_menu.tscn")
