extends Control

const CALIBRATION_EXERCISE_ID := "scapular_retraction"
const CALIBRATION_DURATION_MS := 5000

var is_calibrating := false
var _tracking_available := false
var _session_id := ""
var _using_mock := true
var _calibration_success := false
var _last_frame_ms := -10000
var _camera_view: TextureRect
var _camera_texture: ImageTexture

@onready var introduce: Label = $Introduce
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var start_button: Button = $StartCalibButton
@onready var next_button: Button = $NextButton
@onready var connection_label: Label = $PoseStatusPanel/MarginContainer/VBoxContainer/ConnectionLabel
@onready var tracking_label: Label = $PoseStatusPanel/MarginContainer/VBoxContainer/TrackingLabel
@onready var confidence_label: Label = $PoseStatusPanel/MarginContainer/VBoxContainer/ConfidenceLabel
@onready var feedback_label: Label = $PoseStatusPanel/MarginContainer/VBoxContainer/FeedbackLabel


func _ready() -> void:
	_using_mock = "mock" in str(PoseInput.get_script().resource_path).to_lower()
	_build_presentation()
	_setup_camera_preview()
	if PoseInput.has_signal("camera_frame_received"):
		PoseInput.connect("camera_frame_received", _on_camera_frame_received)
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


func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F3:
		$DebugPanel.visible = not $DebugPanel.visible
		$DebugToggle.text = "Ẩn thông tin" if $DebugPanel.visible else "Thông tin kỹ thuật"


func _on_start_calib_button_pressed() -> void:
	if not PoseInput.provider_connected:
		_show_warning("Không có kết nối với hệ thống nhận diện.")
		return
	if not _tracking_available:
		_show_warning("Camera chưa nhận diện đủ cơ thể người chơi.")
		return

	is_calibrating = true
	_calibration_success = false
	$RomLabel.text = "Chỉ số hiện tại: —"
	$ProgressCaption.text = "Thời gian thu mẫu: 0.0 / 5.0 giây"
	_session_id = "calibration-%d" % Time.get_ticks_msec()
	progress_bar.value = 0.0
	start_button.disabled = true
	next_button.disabled = true
	introduce.text = "Đang thu mẫu 5 giây: Hãy dang thẳng 2 tay sang 2 bên ngang bằng vai (90°)!"
	introduce.add_theme_color_override("font_color", Color(0.9, 0.15, 0.1))

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
		_calibration_success = false
		next_button.disabled = true
		is_calibrating = false
		_tracking_available = false
		tracking_label.text = "Nhận diện tạm thời không khả dụng"
		tracking_label.add_theme_color_override("font_color", Color(0.85, 0.2, 0.15))
		_show_warning("Mất kết nối với hệ thống nhận diện. Quá trình đo đã dừng.")
	_update_start_button()


func _on_tracking_status_changed(data: Dictionary) -> void:
	_tracking_available = bool(data.get("person_detected", false)) \
			and bool(data.get("required_body_visible", false))

	var status := str(data.get("status", "unknown"))
	var confidence := float(data.get("confidence", 0.0))
	var feedback_code := str(data.get("feedback_code", ""))

	tracking_label.text = _feedback_text(feedback_code) if feedback_code not in ["", "POSITION_OK"] else "Nhận diện: %s" % _tracking_text(status)
	tracking_label.add_theme_color_override("font_color", Color(0.12, 0.37, 0.18) if _tracking_available else Color(0.85, 0.2, 0.15))
	confidence_label.text = "Độ tin cậy: %d%%" % roundi(confidence * 100.0)
	feedback_label.text = "Phản hồi: %s" % _feedback_text(feedback_code)

	if is_calibrating and not _tracking_available:
		introduce.text = "Giả lập đang tạm dừng thu mẫu." if _using_mock else "Mất nhận diện: BE vẫn đếm thời gian thu mẫu. Có thể cần đo lại."
		introduce.add_theme_color_override("font_color", Color(0.9, 0.45, 0.05))
	elif is_calibrating:
		introduce.text = "Đang nhận diện. Tiếp tục giữ tư thế dang thẳng 2 tay ngang vai (90°)."
		introduce.add_theme_color_override("font_color", Color(0.9, 0.15, 0.1))

	_update_start_button()


func _on_calibration_progressed(data: Dictionary) -> void:
	if not is_calibrating:
		return
	if str(data.get("exercise_id", "")) != CALIBRATION_EXERCISE_ID:
		return

	var progress := clampf(float(data.get("progress", 0.0)), 0.0, 1.0)
	progress_bar.value = progress * 100.0
	var duration := maxi(1, int(data.get("duration_ms", CALIBRATION_DURATION_MS)))
	var elapsed := clampi(int(data.get("elapsed_ms", progress * duration)), 0, duration)
	$ProgressCaption.text = "Thời gian thu mẫu: %.1f / %.1f giây" % [elapsed / 1000.0, duration / 1000.0]
	var valid := bool(data.get("tracking_valid", _tracking_available))
	if data.has("current_rom_value") and valid:
		$RomLabel.text = "Góc biên độ hiện tại: %.1f° / 90.0°" % float(data.current_rom_value)
	else:
		$RomLabel.text = "Chỉ số hiện tại: —"
	if not valid:
		_show_warning("Mẫu hiện tại chưa hợp lệ. BE vẫn đếm thời gian; có thể cần đo lại.")
	feedback_label.text = "Phản hồi: %s" % _feedback_text(str(data.get("feedback_code", "")))


func _on_calibration_finished(data: Dictionary) -> void:
	if str(data.get("exercise_id", "")) != CALIBRATION_EXERCISE_ID:
		return

	is_calibrating = false
	if not bool(data.get("success", false)):
		_calibration_success = false
		progress_bar.value = 0.0
		_show_warning("Hiệu chỉnh thất bại. Hãy kiểm tra vị trí và thử lại.")
		_update_start_button()
		return

	var max_rom: Dictionary = data.get("max_rom", {})
	if not is_finite(float(max_rom.get("combined", 0.0))) or float(max_rom.get("combined", 0.0)) <= 0:
		_calibration_success = false
		_show_warning("Kết quả chưa hợp lệ. Hãy đo lại.")
		_update_start_button()
		return
	_calibration_success = true
	Global.max_rom_angle = float(max_rom.get("combined", 0.0))
	Global.record_calibration_rom(Global.max_rom_angle)
	progress_bar.value = 100.0
	introduce.text = "Hoàn tất! Biên độ tối đa: %.1f° / 90.0° (Đã lưu vào hồ sơ %s)." % [Global.max_rom_angle, Global.current_patient_id]
	$ProgressCaption.text = "Đã kết thúc thu mẫu"
	introduce.add_theme_color_override("font_color", Color(0.12, 0.37, 0.18))
	feedback_label.text = "Phản hồi: %s" % _feedback_text(str(data.get("feedback_code", "")))
	_update_start_button()
	start_button.text = "ĐO LẠI"
	next_button.grab_focus()


func _on_provider_error_received(data: Dictionary) -> void:
	var error_code := str(data.get("code", "INTERNAL_ERROR"))
	feedback_label.text = "Lỗi: %s" % error_code
	_show_warning("Hệ thống nhận diện gặp lỗi: %s" % error_code)

	if str(data.get("severity", "warning")) == "fatal":
		_calibration_success = false
		next_button.disabled = true
		is_calibrating = false
		_update_start_button()


func _on_next_button_pressed() -> void:
	PoseInput.stop_exercise("scene_changed")
	get_tree().change_scene_to_file("res://ui/screens/map_selection/level_selection.tscn")


func _on_back_button_pressed() -> void:
	PoseInput.stop_exercise("scene_changed")
	get_tree().change_scene_to_file("res://ui/screens/start/start_screen.tscn")


func _update_connection_ui(connected: bool, details := {}) -> void:
	if details.has("pose_engine"):
		_using_mock = str(details.pose_engine).to_lower() == "mock"
	if connected:
		connection_label.text = "GIẢ LẬP · Không phải số đo camera thật" if _using_mock else "BE đã kết nối · Chờ ảnh camera"
		connection_label.add_theme_color_override("font_color", Color(0.12, 0.37, 0.18))
	else:
		connection_label.text = "Mất kết nối hệ thống nhận diện"
		_last_frame_ms = -10000
		if is_instance_valid(_camera_view):
			_camera_view.texture = null
		connection_label.add_theme_color_override("font_color", Color(0.85, 0.2, 0.15))


func _update_start_button() -> void:
	next_button.disabled = not _calibration_success or not PoseInput.provider_connected or not _tracking_available or (not _using_mock and not _fresh_camera())
	start_button.disabled = is_calibrating \
			or not PoseInput.provider_connected \
			or not _tracking_available \
			or (not _using_mock and not _fresh_camera())


func _show_warning(message: String) -> void:
	introduce.text = message
	introduce.add_theme_color_override("font_color", Color(0.9, 0.25, 0.1))


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
		"OPEN_ARMS": "Hãy dang thẳng 2 tay sang 2 bên ngang vai (90°)",
		"KEEP_POSITION": "Hãy giữ nguyên tư thế dang tay ngang vai",
		"TRACKING_LOST": "Không nhìn thấy người chơi",
		"SHOULDERS_NOT_VISIBLE": "Camera chưa thấy rõ hai vai",
		"LEFT_ARM_NOT_VISIBLE": "Camera chưa thấy rõ tay trái",
		"RIGHT_ARM_NOT_VISIBLE": "Camera chưa thấy rõ tay phải",
		"LIGHTING_TOO_LOW": "Kiểm tra camera và ánh sáng",
		"CALIBRATION_LOW_CONFIDENCE": "Mẫu chưa đủ tin cậy, hãy đo lại",
		"CALIBRATION_COMPLETED": "Hiệu chỉnh hoàn tất",
	}
	return FEEDBACK_TEXT.get(code, code if not code.is_empty() else "Chờ dữ liệu")


func _build_presentation() -> void:
	var backdrop := preload("res://ui/screens/map_selection/map_preview.gd").new()
	backdrop.map_id = 1
	backdrop.scenery_only = true
	add_child(backdrop)
	move_child(backdrop, 0)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$DebugToggle.pressed.connect(func():
		$DebugPanel.visible = not $DebugPanel.visible
		$DebugToggle.text = "Ẩn thông tin" if $DebugPanel.visible else "Thông tin kỹ thuật")
	start_button.grab_focus()


func _process(_delta: float) -> void:
	if not _using_mock:
		var fresh := _fresh_camera()
		$CameraHint.visible = not fresh
		$ColorRect2.show_body = not fresh
		$ColorRect2.queue_redraw()
		if not fresh:
			_camera_view.texture = null
			next_button.disabled = true
		if PoseInput.provider_connected:
			connection_label.text = "BE đã kết nối · Camera đang có hình" if fresh else "BE đã kết nối · Chưa có ảnh camera mới"
		_update_start_button()
	if $DebugPanel.visible:
		$DebugPanel/Text.text = confidence_label.text + "\n" + feedback_label.text + "\n\nGiả lập: T nhận diện · K kết nối · C đo\nR/F lượt đúng/sai (trong màn chơi)"


func _fresh_camera() -> bool:
	return Time.get_ticks_msec() - _last_frame_ms < 3000


func _setup_camera_preview() -> void:
	_camera_view = TextureRect.new()
	_camera_view.name = "CalibrationCameraRect"
	_camera_view.position = Vector2(40, 184)
	_camera_view.size = Vector2(624, 296)
	_camera_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_camera_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_camera_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_camera_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_camera_view)
	move_child(_camera_view, $ColorRect2.get_index() + 1)


func _on_camera_frame_received(image: Image) -> void:
	if image == null or image.is_empty():
		return
	# Reference backend already mirrors and draws joints. Preserve its aspect ratio.
	if _camera_texture != null and _camera_texture.get_width() == image.get_width() and _camera_texture.get_height() == image.get_height() and _camera_texture.get_format() == image.get_format():
		_camera_texture.update(image)
	else:
		_camera_texture = ImageTexture.create_from_image(image)
	_camera_view.texture = _camera_texture
	_last_frame_ms = Time.get_ticks_msec()
	_update_start_button()
