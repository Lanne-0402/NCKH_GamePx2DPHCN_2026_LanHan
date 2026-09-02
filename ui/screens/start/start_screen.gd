extends Control

func _on_start_button_pressed():
	# Đổi từ level_selection sang calibration
	get_tree().change_scene_to_file("res://ui/screens/calibration/calibration_screen.tscn")

func _on_settings_button_pressed():
	# (Tạm thời in ra text, sau này bạn làm màn Settings thì gọi ở đây)
	print("Mở bảng Cài đặt (Độ nhạy Camera, Âm thanh...)")
