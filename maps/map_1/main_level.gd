extends Node2D

@export var countdown_step_seconds := 1.0
@export var tracking_loss_grace_seconds := 3.0

const EXERCISE_CONFIGS := {
	1: {"exercise_id": "scapular_retraction", "repetitions_per_phase": 10, "phase_count": 2, "hold_duration_ms": 0},
	2: {"exercise_id": "wall_abduction_external_rotation", "repetitions_per_phase": 5, "phase_count": 2, "hold_duration_ms": 5000},
	3: {"exercise_id": "horizontal_shoulder_adduction", "repetitions_per_phase": 5, "phase_count": 2, "hold_duration_ms": 5000},
	4: {"exercise_id": "hands_behind_head", "repetitions_per_phase": 5, "phase_count": 2, "hold_duration_ms": 5000},
	5: {"exercise_id": "cross_body_shoulder_stretch", "repetitions_per_phase": 1, "phase_count": 2, "hold_duration_ms": 30000},
}

var obstacle_scene = preload("res://maps/map_1/obstacle.tscn")
var star_scene = preload("res://shared/collectibles/star/star.tscn")

var score = 0.0 
var star_score = 0 
var _session_config: Dictionary = {}
var _session_attempt := 0
var _intro_running := false

@onready var exercise_session: ExerciseSession = $ExerciseSession
@onready var map1_controller: Map1Controller = $Map1Controller
@onready var tracking_stability: Node = $TrackingStability
@onready var state_label: Label = $UI/ScoreLabel
@onready var phase_label: Label = $UI/LivesLabel
@onready var rep_label: Label = $UI/StarScoreLabel
@onready var feedback_label: Label = $UI/FeedbackLabel
@onready var rest_label: Label = $UI/RestLabel
@onready var result_panel: PanelContainer = $UI/ResultPanel
@onready var result_label: Label = $UI/ResultPanel/MarginContainer/VBoxContainer/ResultLabel
@onready var rock_progress_label: Label = $UI/RockProgressLabel
@onready var hearts_label: Label = $UI/HeartsLabel
@onready var instruction_panel: PanelContainer = $UI/InstructionPanel
@onready var instruction_start_button: Button = $UI/InstructionPanel/MarginContainer/VBoxContainer/StartExerciseButton
@onready var countdown_label: Label = $UI/CountdownLabel

func _ready() -> void:
	score = 0.0
	star_score = 0
	# Sprint 2: runner spawners remain available but session progression must
	# come only from PoseProvider repetition events.
	$SpawnTimer.stop()
	$StarTimer.stop()
	result_panel.hide()
	rest_label.hide()
	instruction_panel.hide()
	countdown_label.hide()
	rock_progress_label.visible = Global.selected_action == 1
	hearts_label.visible = Global.selected_action == 1

	exercise_session.state_changed.connect(_on_session_state_changed)
	exercise_session.progress_changed.connect(_on_session_progress_changed)
	exercise_session.feedback_changed.connect(_on_session_feedback_changed)
	exercise_session.repetition_accepted.connect(_on_repetition_accepted)
	exercise_session.repetition_rejected.connect(_on_repetition_rejected)
	exercise_session.rest_time_changed.connect(_on_rest_time_changed)
	exercise_session.session_completed.connect(_on_session_completed)
	tracking_stability.grace_seconds = tracking_loss_grace_seconds
	tracking_stability.setup(exercise_session, PoseInput)
	tracking_stability.stability_changed.connect(_on_stability_changed)
	tracking_stability.tracking_penalty_applied.connect(_on_tracking_penalty_applied)

	_session_config = EXERCISE_CONFIGS.get(Global.selected_action, EXERCISE_CONFIGS[1]).duplicate(true)
	_session_config["difficulty"] = _difficulty_name()
	_session_config["target_rom_ratio"] = _target_rom_ratio()
	_session_config["minimum_movement_duration_ms"] = 2000
	_session_config["maximum_movement_duration_ms"] = 5000
	_session_config["rest_duration_seconds"] = 30.0
	_session_config["calibrated_max_rom"] = Global.max_rom_angle
	_session_config["target_rom_value"] = 0.0
	if Global.max_rom_angle > 0.0:
		_session_config["target_rom_value"] = Global.max_rom_angle * float(_session_config["target_rom_ratio"])

	if Global.selected_action == 1:
		map1_controller.rock_progress_changed.connect(_on_rock_progress_changed)
		map1_controller.action_window_changed.connect(_on_action_window_changed)
		var total_required_reps := int(_session_config["repetitions_per_phase"]) * int(_session_config["phase_count"])
		map1_controller.setup_map(total_required_reps)
		tracking_stability.reset()
		_show_map1_intro()
	else:
		_start_new_session_attempt()


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_N:
		exercise_session.debug_skip_rest()


func _on_session_state_changed(current: ExerciseSession.State, previous: ExerciseSession.State) -> void:
	state_label.text = "TRẠNG THÁI: %s" % _state_text(current)
	rest_label.visible = current == ExerciseSession.State.RESTING
	var gameplay_active := current == ExerciseSession.State.ACTIVE
	$ScrollingBackground.set_scrolling(gameplay_active)
	if Global.selected_action == 1:
		map1_controller.set_session_active(gameplay_active)
		if gameplay_active:
			exercise_session.set_repetition_input_enabled(map1_controller.is_action_window_open())


func _on_session_progress_changed(rep: int, reps_required: int, phase: int, phases: int) -> void:
	rep_label.text = "LẦN: %d/%d" % [rep, reps_required]
	phase_label.text = "PHASE: %d/%d" % [phase, phases]


func _on_session_feedback_changed(code: String) -> void:
	var display_code := code
	if Global.selected_action == 1 and code == "SESSION_READY" and not map1_controller.is_action_window_open():
		display_code = "ROCK_APPROACHING"
	feedback_label.text = _feedback_text(display_code)
	match display_code:
		"REP_VALID", "TRACKING_RESTORED", "ACTION_ZONE_READY":
			feedback_label.modulate = Color(0.1, 0.75, 0.2)
		"MOVEMENT_TOO_FAST", "REP_REJECTED", "TRACKING_LOST", "BACKEND_DISCONNECTED":
			feedback_label.modulate = Color(0.9, 0.2, 0.1)
		_:
			feedback_label.modulate = Color.WHITE


func _on_repetition_accepted(data: Dictionary) -> void:
	feedback_label.modulate = Color(0.1, 0.75, 0.2)
	if Global.selected_action == 1:
		map1_controller.handle_valid_repetition(data)


func _on_repetition_rejected(_data: Dictionary) -> void:
	feedback_label.modulate = Color(0.9, 0.2, 0.1)


func _on_rest_time_changed(seconds_remaining: float) -> void:
	rest_label.text = "NGHỈ: %d GIÂY\nNhấn N để bỏ qua khi debug" % ceili(seconds_remaining)


func _on_session_completed(summary: Dictionary) -> void:
	if Global.selected_action == 1:
		await map1_controller.play_finish_sequence()
	var stability: int = tracking_stability.stability
	var evaluation := _stability_evaluation(stability)
	_unlock_next_difficulty(stability)
	var unlock_text := "Chưa mở cấp độ tiếp theo."
	if _difficulty_level() >= 3:
		unlock_text = "Đã hoàn thành cấp độ cao nhất."
	elif stability >= 2:
		unlock_text = "Cấp độ tiếp theo đã sẵn sàng."
	result_label.text = "HOÀN THÀNH BUỔI TẬP\n\nLần hợp lệ: %d\nLần chưa hợp lệ: %d\nSố phase: %d\nỔn định còn lại: %d/3\nĐánh giá: %s\n%s" % [
		int(summary.get("valid_reps", 0)),
		int(summary.get("rejected_reps", 0)),
		int(summary.get("phase_count", 0)),
		stability,
		evaluation,
		unlock_text,
	]
	result_panel.show()


func _on_rock_progress_changed(destroyed: int, total: int) -> void:
	rock_progress_label.text = "ĐÁ ĐÃ PHÁ: %d/%d" % [destroyed, total]


func _on_stability_changed(current: int, maximum: int) -> void:
	var hearts := ""
	for index in range(maximum):
		hearts += "♥ " if index < current else "♡ "
	hearts_label.text = "ỔN ĐỊNH: %s" % hearts.strip_edges()


func _on_tracking_penalty_applied(_current: int, grace_seconds: float) -> void:
	feedback_label.modulate = Color(0.9, 0.2, 0.1)
	feedback_label.text = "Tracking gián đoạn quá %d giây: giảm 1 điểm Ổn định." % ceili(grace_seconds)


func _on_action_window_changed(is_open: bool) -> void:
	exercise_session.set_repetition_input_enabled(is_open)


func _show_map1_intro() -> void:
	$ScrollingBackground.set_scrolling(false)
	state_label.text = "TRẠNG THÁI: HƯỚNG DẪN"
	feedback_label.modulate = Color.WHITE
	feedback_label.text = "Đọc hướng dẫn và nhấn SẴN SÀNG để bắt đầu."
	instruction_start_button.disabled = false
	instruction_panel.show()


func _on_start_exercise_button_pressed() -> void:
	if _intro_running or exercise_session.state != ExerciseSession.State.IDLE:
		return
	_intro_running = true
	instruction_start_button.disabled = true
	instruction_panel.hide()
	countdown_label.show()
	for value in [3, 2, 1]:
		countdown_label.text = str(value)
		await get_tree().create_timer(countdown_step_seconds).timeout
	countdown_label.text = "BẮT ĐẦU"
	await get_tree().create_timer(countdown_step_seconds).timeout
	countdown_label.hide()
	_start_new_session_attempt()
	_intro_running = false


func _start_new_session_attempt() -> void:
	_session_attempt += 1
	_session_config["session_id"] = "game-session-%d-%d" % [Time.get_ticks_msec(), _session_attempt]
	exercise_session.start_session(_session_config)


func _on_result_button_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/screens/level_selection/main_menu.tscn")


func _exit_tree() -> void:
	if is_instance_valid(exercise_session):
		exercise_session.stop_session("scene_changed")


func _difficulty_name() -> String:
	if Global.speed_multiplier >= 2.0:
		return "advanced"
	if Global.speed_multiplier >= 1.5:
		return "standard"
	return "gentle"


func _target_rom_ratio() -> float:
	if Global.speed_multiplier >= 2.0:
		return 0.90
	if Global.speed_multiplier >= 1.5:
		return 0.80
	return 0.70


func _unlock_next_difficulty(stability: int) -> bool:
	if stability < 2:
		return false
	var current_level := _difficulty_level()
	if current_level >= 3:
		return false
	var previous_highest := Global.get_highest_unlocked_level(Global.selected_action)
	Global.unlock_level_for_action(Global.selected_action, current_level + 1)
	return Global.get_highest_unlocked_level(Global.selected_action) > previous_highest


func _difficulty_level() -> int:
	if Global.speed_multiplier >= 2.0:
		return 3
	if Global.speed_multiplier >= 1.5:
		return 2
	return 1


func _stability_evaluation(stability: int) -> String:
	if stability >= 3:
		return "HOÀN HẢO"
	if stability == 2:
		return "HOÀN THÀNH"
	return "CẦN CẢI THIỆN ĐỘ ỔN ĐỊNH"


func _state_text(value: ExerciseSession.State) -> String:
	match value:
		ExerciseSession.State.READY: return "CHUẨN BỊ"
		ExerciseSession.State.ACTIVE: return "ĐANG TẬP"
		ExerciseSession.State.RESTING: return "ĐANG NGHỈ"
		ExerciseSession.State.PAUSED: return "TẠM DỪNG"
		ExerciseSession.State.TRACKING_LOST: return "MẤT NHẬN DIỆN"
		ExerciseSession.State.COMPLETED: return "HOÀN THÀNH"
		_: return "CHỜ"


func _feedback_text(code: String) -> String:
	const TEXTS := {
		"SESSION_READY": "Sẵn sàng. Hãy thực hiện động tác chậm rãi.",
		"SESSION_PAUSED": "Buổi tập đang tạm dừng.",
		"SESSION_RESUMED": "Đã sẵn sàng. Tiếp tục buổi tập.",
		"ROCK_APPROACHING": "Chướng ngại vật đang tới. Hãy chuẩn bị đúng tư thế.",
		"ACTION_ZONE_READY": "Đá đã vào vị trí. Hãy ép hai bả vai ra sau chậm rãi.",
		"MOVEMENT_STARTED": "Đã bắt đầu chuyển động...",
		"TARGET_REACHED": "Đã đạt ngưỡng mục tiêu.",
		"REP_VALID": "Tốt lắm! Một lần tập hợp lệ.",
		"MOVEMENT_TOO_FAST": "Cử động quá nhanh. Hãy thực hiện chậm hơn.",
		"REP_REJECTED": "Lần tập chưa hợp lệ.",
		"PHASE_REST": "Hoàn thành phase. Hãy nghỉ 30 giây.",
		"NEXT_PHASE": "Bắt đầu phase tiếp theo.",
		"TRACKING_LOST": "Không nhìn thấy người chơi. Buổi tập đã tạm dừng.",
		"TRACKING_RESTORED": "Đã nhận diện lại. Tiếp tục buổi tập.",
		"BACKEND_DISCONNECTED": "Mất kết nối với hệ thống nhận diện.",
		"SESSION_COMPLETED": "Hoàn thành buổi tập!",
	}
	return TEXTS.get(code, code)

func _on_spawn_timer_timeout():
	var new_obstacle = obstacle_scene.instantiate()
	new_obstacle.position = $SpawnPosition.position
	add_child(new_obstacle)
	$SpawnTimer.wait_time = randf_range(1.0, 2.5)
	
func _on_star_timer_timeout():
	var new_star = star_scene.instantiate()
	
	# Random một số nguyên từ 1 đến 3 (1: Dễ, 2: Vừa, 3: Khó)
	var random_type = randi_range(1, 3) 
	var y_offset = 0 # Biến để chỉnh độ cao (nhớ là trục Y hướng lên trên là số ÂM)
	
	if random_type == 1:
		# LOẠI 1 (DỄ): To, thấp, 10 điểm
		new_star.scale = Vector2(1.5, 1.5) # Phóng to gấp rưỡi
		y_offset = 0 # Thấp (ngang với điểm xuất phát gốc)
		new_star.point_value = 10
		
	elif random_type == 2:
		# LOẠI 2 (VỪA): Kích thước bình thường, cao vừa, 20 điểm
		new_star.scale = Vector2(1.0, 1.0) # Giữ nguyên
		y_offset = -60 # Dịch lên cao một chút (có thể tùy chỉnh số 60 này)
		new_star.point_value = 20
		
	else:
		# LOẠI 3 (KHÓ): Nhỏ, rất cao, 50 điểm
		new_star.scale = Vector2(0.6, 0.6) # Thu nhỏ lại
		y_offset = -130 # Dịch lên rất cao, đòi hỏi nhảy thật chuẩn
		new_star.point_value = 50

	# Thiết lập vị trí mới: X giữ nguyên, Y cộng thêm khoảng bù (y_offset)
	var spawn_x = $StarSpawnPosition.position.x
	var spawn_y = $StarSpawnPosition.position.y + y_offset
	new_star.position = Vector2(spawn_x, spawn_y)
	
	# Đưa ra màn hình
	add_child(new_star)
	
	# Random thời gian đẻ sao tiếp theo
	$StarTimer.wait_time = randf_range(3.0, 5.0)
