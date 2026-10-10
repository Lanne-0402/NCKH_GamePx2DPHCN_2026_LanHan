extends Control

func _on_history_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/screens/history/history_screen.tscn")

func _on_start_button_pressed():
	# Đổi từ level_selection sang calibration
	get_tree().change_scene_to_file("res://ui/screens/calibration/calibration_screen.tscn")
