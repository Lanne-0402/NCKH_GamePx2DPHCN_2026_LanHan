extends Control

const CALIBRATION_EXERCISE_ID := "scapular_retraction"
const CALIBRATION_DURATION_MS := 5000

var is_calibrating := false
var _tracking_available := false
var _session_id := ""

@onready var introduce: Label = $Introduce
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var start_button: Button = $StartCalibButton
@onready var next_button: Button = $NextButton
@onready var connection_label: Label = $PoseStatusPanel/MarginContainer/VBoxContainer/ConnectionLabel
@onready var tracking_label: Label = $PoseStatusPanel/MarginContainer/VBoxContainer/TrackingLabel
@onready var confidence_label: Label = $PoseStatusPanel/MarginContainer/VBoxContainer/ConfidenceLabel
@onready var feedback_label: Label = $PoseStatusPanel/MarginContainer/VBoxContainer/FeedbackLabel


func _ready() -> void:
	PoseInput.connection_changed.connect(_on_connection_changed)
	PoseInput.tracking_status_changed.connect(_on_tracking_status_changed)
	PoseInput.calibration_progressed.connect(_on_calibration_progressed)
	PoseInput.calibration_finished.connect(_on_calibration_finished)
	PoseInput.provider_error_received.connect(_on_provider_error_received)

	progress_bar.value = 0.0
	next_button.disabled = true
	_update_connection_ui(PoseInput.provider_connected)

	if not PoseInput.last_tracking_status.is_empty():
		_on_tracking_status_changed(PoseInput.last_tracking_status)
	else:
		_update_start_button()


func _on_start_calib_button_pressed() -> void:
	if not PoseInput.provider_connected:
		_show_warning("Không có kết nối với hệ thống nhận diện.")
		return
	if not _tracking_available:
		_show_warning("Camera chưa nhận diện đủ cơ thể người chơi.")
		return

	is_calibrating = true
	_session_id = "calibration-%d" % Time.get_ticks_msec()
	progress_bar.value = 0.0
	start_button.disabled = true
	next_button.disabled = true
	introduce.text = "Hệ thống đang đo lường... Hãy giữ nguyên tư thế tối đa!"
	introduce.modulate = Color(0.9, 0.15, 0.1)

	PoseInput.start_calibration({
		"session_id": _session_id,
		"exercise_id": CALIBRATION_EXERCISE_ID,
		"duration_ms": CALIBRATION_DURATION_MS,
		"target_side": "both",
		"camera_view": "front",
	})


func _on_connection_changed(connected: bool, details: Dictionary) -> void:
	_update_connection_ui(connected, details)
	if not connected:
		is_calibrating = false
		_tracking_available = false
		tracking_label.text = "Tracking: Không khả dụng"
		tracking_label.modulate = Color(0.85, 0.2, 0.15)
		_show_warning("Mất kết nối với hệ thống nhận diện. Quá trình đo đã dừng.")
	_update_start_button()


func _on_tracking_status_changed(data: Dictionary) -> void:
	_tracking_available = bool(data.get("person_detected", false)) \
			and bool(data.get("required_body_visible", false))

	var status := str(data.get("status", "unknown"))
	var confidence := float(data.get("confidence", 0.0))
	var feedback_code := str(data.get("feedback_code", ""))

	tracking_label.text = "Tracking: %s" % _tracking_text(status)
	tracking_label.modulate = Color(0.1, 0.65, 0.2) if _tracking_available else Color(0.85, 0.2, 0.15)
	confidence_label.text = "Độ tin cậy: %d%%" % roundi(confidence * 100.0)
	feedback_label.text = "Phản hồi: %s" % _feedback_text(feedback_code)

	if is_calibrating and not _tracking_available:
		introduce.text = "Tạm dừng đo: Camera không nhìn thấy đủ cơ thể. Hãy trở lại đúng vị trí."
		introduce.modulate = Color(0.9, 0.45, 0.05)
	elif is_calibrating:
		introduce.text = "Đã nhận diện lại người chơi. Hãy tiếp tục giữ tư thế tối đa!"
		introduce.modulate = Color(0.9, 0.15, 0.1)

	_update_start_button()


func _on_calibration_progressed(data: Dictionary) -> void:
	if not is_calibrating:
		return
	if str(data.get("exercise_id", "")) != CALIBRATION_EXERCISE_ID:
		return

	var progress := clampf(float(data.get("progress", 0.0)), 0.0, 1.0)
	progress_bar.value = progress * 100.0
	feedback_label.text = "Phản hồi: %s" % _feedback_text(str(data.get("feedback_code", "")))


func _on_calibration_finished(data: Dictionary) -> void:
	if str(data.get("exercise_id", "")) != CALIBRATION_EXERCISE_ID:
		return

	is_calibrating = false
	if not bool(data.get("success", false)):
		progress_bar.value = 0.0
		_show_warning("Hiệu chỉnh thất bại. Hãy kiểm tra vị trí và thử lại.")
		_update_start_button()
		return

	var max_rom: Dictionary = data.get("max_rom", {})
	Global.max_rom_angle = float(max_rom.get("combined", 0.0))
	progress_bar.value = 100.0
	introduce.text = "Hoàn tất! Biên độ tối đa của bạn là: %.1f°" % Global.max_rom_angle
	introduce.modulate = Color(0.05, 0.65, 0.15)
	feedback_label.text = "Phản hồi: %s" % _feedback_text(str(data.get("feedback_code", "")))
	_update_start_button()
	next_button.disabled = false


func _on_provider_error_received(data: Dictionary) -> void:
	var error_code := str(data.get("code", "INTERNAL_ERROR"))
	feedback_label.text = "Lỗi: %s" % error_code
	_show_warning("Hệ thống nhận diện gặp lỗi: %s" % error_code)

	if str(data.get("severity", "warning")) == "fatal":
		is_calibrating = false
		_update_start_button()


func _on_next_button_pressed() -> void:
	PoseInput.stop_exercise("scene_changed")
	get_tree().change_scene_to_file("res://ui/screens/map_selection/level_selection.tscn")


func _on_back_button_pressed() -> void:
	PoseInput.stop_exercise("scene_changed")
	get_tree().change_scene_to_file("res://ui/screens/start/start_screen.tscn")


func _update_connection_ui(connected: bool, details := {}) -> void:
	if connected:
		var engine_name := str(details.get("pose_engine", "mock"))
		connection_label.text = "Backend: Đã kết nối (%s)" % engine_name.to_upper()
		connection_label.modulate = Color(0.1, 0.65, 0.2)
	else:
		connection_label.text = "Backend: Mất kết nối"
		connection_label.modulate = Color(0.85, 0.2, 0.15)


func _update_start_button() -> void:
	start_button.disabled = is_calibrating \
			or not PoseInput.provider_connected \
			or not _tracking_available


func _show_warning(message: String) -> void:
	introduce.text = message
	introduce.modulate = Color(0.9, 0.25, 0.1)


func _tracking_text(status: String) -> String:
	match status:
		"tracking":
			return "Đã nhận diện người"
		"no_person":
			return "Không tìm thấy người"
		"partial_person":
			return "Chưa thấy đủ cơ thể"
		"low_confidence":
			return "Độ tin cậy thấp"
		"no_camera":
			return "Không tìm thấy camera"
		_:
			return status


func _feedback_text(code: String) -> String:
	const FEEDBACK_TEXT := {
		"POSITION_OK": "Vị trí phù hợp",
		"MOVE_BACK": "Hãy lùi lại một chút",
		"MOVE_CLOSER": "Hãy tiến gần camera hơn",
		"CENTER_YOUR_BODY": "Hãy đứng giữa khung hình",
		"KEEP_POSITION": "Hãy giữ nguyên tư thế",
		"TRACKING_LOST": "Không nhìn thấy người chơi",
		"CALIBRATION_COMPLETED": "Hiệu chỉnh hoàn tất",
	}
	return FEEDBACK_TEXT.get(code, code if not code.is_empty() else "Chờ dữ liệu")
