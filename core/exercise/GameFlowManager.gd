# GameFlowManager.gd
extends Node

@export var ui_feedback_label: Label
@export var ui_rom_bar: TextureProgressBar
@export var ui_hold_bar: TextureProgressBar
@export var ui_rest_overlay: Control
@export var ui_rest_timer_label: Label

var current_map := 1
var rep_count := 0
var current_phase := 1

const MAP_EXERCISE_MAP := {
	1: "scapular_retraction",
	2: "wall_abduction_external_rotation",
	3: "horizontal_shoulder_adduction",
	4: "hands_behind_head",
	5: "cross_body_shoulder_stretch"
}

func _ready() -> void:
	AIConnector.pose_frame_updated.connect(_on_pose_frame)
	AIConnector.rep_completed.connect(_on_rep_count)
	AIConnector.rep_rejected.connect(_on_rep_failed)
	start_level(1)

func start_level(map_idx: int) -> void:
	current_map = map_idx
	rep_count = 0
	current_phase = 1
	var ex_id = MAP_EXERCISE_MAP[map_idx]
	AIConnector.request_start_exercise(ex_id)
	ui_rest_overlay.visible = false

func _on_pose_frame(rom: float, hold: float, feedback_code: String) -> void:
	ui_rom_bar.value = rom * 100.0
	ui_hold_bar.value = hold * 100.0
	ui_feedback_label.text = AIConnector.FEEDBACK_DICT.get(feedback_code, "")

func _on_rep_count(_ex_id: String, _rep_id: String) -> void:
	rep_count += 1
	
	# Kiểm tra điều kiện hoàn thành Phase / Map theo Kịch bản
	match current_map:
		1:
			# Map 1: 10 lần x 2 Phase = 20 lần
			if rep_count == 10 and current_phase == 1:
				current_phase = 2
				trigger_safe_zone_rest(30)
			elif rep_count >= 20:
				advance_to_next_map()
		2, 3, 4:
			# Map 2, 3, 4: Hoàn thành từ 5 đến 10 lần
			if rep_count >= 8:
				advance_to_next_map()
		5:
			# Map 5: Kéo căng 30s trái -> Nghỉ 30s -> Kéo căng 30s phải
			if rep_count == 1:
				trigger_safe_zone_rest(30)
			elif rep_count >= 2:
				ui_feedback_label.text = "Hoàn thành buổi tập phục hồi chức năng!"
				AIConnector.request_stop_exercise("session_completed")

func _on_rep_failed(feedback_code: String) -> void:
	ui_feedback_label.text = AIConnector.FEEDBACK_DICT.get(feedback_code, "Thực hiện lại!")

func trigger_safe_zone_rest(duration: int) -> void:
	AIConnector.request_stop_exercise("safe_zone_rest")
	ui_rest_overlay.visible = true
	var time_left = duration
	
	while time_left > 0:
		ui_rest_timer_label.text = "Thời gian nghỉ y khoa: %d giây" % time_left
		await get_tree().create_timer(1.0).timeout
		time_left -= 1
		
	ui_rest_overlay.visible = false
	# Tiếp tục phase sau khi cơ bắp đã ổn định nhịp tim
	var ex_id = MAP_EXERCISE_MAP[current_map]
	AIConnector.request_start_exercise(ex_id)

func advance_to_next_map() -> void:
	AIConnector.request_stop_exercise("map_completed")
	trigger_safe_zone_rest(30)
	await get_tree().create_timer(30.0).timeout
	current_map += 1
	if current_map <= 5:
		start_level(current_map)
