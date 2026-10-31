extends Node
func _ready() -> void:
	call_deferred("_run")
func _run() -> void:
	Global.session_history = []
	var history = load("res://ui/screens/history/history_screen.tscn").instantiate()
	add_child(history)
	await get_tree().process_frame
	assert(history.get_node("Margin/Column/Scroll/List").get_child_count() == 1)
	history.queue_free()
	await get_tree().process_frame
	for i in range(12):
		Global.session_history.append({"map_id": i % 5 + 1, "difficulty": 2, "completed_at_utc": "2026-10-23T08:30:00", "valid_reps": 10, "rejected_reps": 2, "phase_count": 2, "evaluation": "HOÀN THÀNH"})
	history = load("res://ui/screens/history/history_screen.tscn").instantiate()
	add_child(history)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(history.get_node("Margin/Column/Scroll/List").get_child_count() == 12)
	if not DisplayServer.get_name() == "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://history_ui.png")
	history.queue_free()
	await get_tree().process_frame
	for id in range(1, 6):
		var level = load("res://maps/map_%d/main_level.tscn" % id).instantiate()
		add_child(level)
		await get_tree().process_frame
		await get_tree().process_frame
		level.instruction_panel.hide()
		level.result_label.text = "HOÀN THÀNH\nLần hợp lệ: 10\nLần chưa hợp lệ: 2\nSố hiệp: 2\nĐánh giá: HOÀN THÀNH\nCấp độ tiếp theo đã sẵn sàng."
		level.result_panel.show()
		await get_tree().process_frame
		await get_tree().process_frame
		assert(level.result_panel.size.x <= 900)
		assert(level.result_panel.position.y + level.result_panel.size.y <= 648)
		if id == 2 and not DisplayServer.get_name() == "headless":
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("user://results_ui.png")
		level.queue_free()
		await get_tree().process_frame
	print("RESULTS_HISTORY_UI_PASS")
	get_tree().quit()
