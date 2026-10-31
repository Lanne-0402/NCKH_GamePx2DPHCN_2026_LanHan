extends Control

const Display := preload("res://ui/shared/session_display.gd")
const RomLineChartScript := preload("res://ui/screens/history/rom_line_chart.gd")

const MAP_NAMES := [
	"Phá cản mở đường (Khép bả vai)",
	"Nâng đá (Dạng xoay ngoài)",
	"Đẩy lùi tường (Khép ngang vai)",
	"Leo vách đá cao (Hai tay ôm đầu)",
	"Thiền định (Kéo căng qua ngực)",
]

var _patient_id_edit: LineEdit
var _patient_name_edit: LineEdit
var _preset_patient_option: OptionButton
var _doctor_section_container: HBoxContainer
var _toolbar_row2: HBoxContainer
var _mode_toggle_btn: Button
var _patient_mode: bool = false

var _cloud_status_label: Label
var _weekly_stats_label: Label
var _map_progress_label: Label
var _rom_chart: Control

var _cloud_modal: ColorRect
var _cloud_enable_check: CheckBox
var _cloud_provider_option: OptionButton
var _cloud_url_edit: LineEdit
var _cloud_key_edit: LineEdit


func _ready() -> void:
	theme = preload("res://assets/shared/ui/game_theme.tres")
	$Background.hide()
	var forest := preload("res://ui/screens/map_selection/map_preview.gd").new()
	forest.scenery_only = true
	add_child(forest)
	move_child(forest, 0)
	forest.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# An nut BackButton goc de tich hop gon gang vao hang Header tren cung
	if has_node("BackButton"):
		$BackButton.visible = false

	$Margin/Column/Scroll.follow_focus = true

	_build_dashboard_ui()
	_build_cloud_config_modal()

	Global.cloud_sync_status_changed.connect(_on_cloud_sync_status_changed)
	Global.patient_profile_changed.connect(func(_pid: String): _refresh_all())

	_refresh_all()


func _build_dashboard_ui() -> void:
	var column: VBoxContainer = $Margin/Column

	# 1. Header Row (Gom Back Button, Title va Cloud Status tren 1 hang ngan nap)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 12)
	column.add_child(header_row)
	column.move_child(header_row, 0)

	var back_btn := Button.new()
	back_btn.text = "‹ VỀ TRANG CHỦ"
	back_btn.custom_minimum_size = Vector2(150, 36)
	back_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://ui/screens/start/start_screen.tscn")
	)
	header_row.add_child(back_btn)

	# Chuyen Title co san vao giua header_row
	var title_node: Label = $Margin/Column/Title
	title_node.reparent(header_row)
	title_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_node.add_theme_font_size_override("font_size", 22)
	title_node.add_theme_color_override("font_color", Color("f5e9c7"))
	title_node.add_theme_color_override("font_outline_color", Color("14251e"))
	title_node.add_theme_constant_override("outline_size", 4)

	_cloud_status_label = _plain_label(_initial_cloud_status_text(), 13)
	_cloud_status_label.custom_minimum_size = Vector2(250, 36)
	_cloud_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cloud_status_label.add_theme_color_override(
		"font_color",
		Color("8ef5a5") if Global.cloud_db_enabled else Color("f5e9c7")
	)
	header_row.add_child(_cloud_status_label)

	# 2. Patient ID & Actions Toolbar (Chia thanh 2 hang ngang gon gang, chong tran)
	var toolbar_panel := PanelContainer.new()
	column.add_child(toolbar_panel)
	column.move_child(toolbar_panel, 1)

	var toolbar_vbox := VBoxContainer.new()
	toolbar_vbox.add_theme_constant_override("separation", 8)
	toolbar_panel.add_child(toolbar_vbox)

	# --- HANG 1: Thong tin nguoi benh & Chon ho so ---
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 10)
	toolbar_vbox.add_child(row1)

	row1.add_child(_plain_label("Mã ID:", 14))

	_patient_id_edit = LineEdit.new()
	_patient_id_edit.custom_minimum_size = Vector2(85, 32)
	_patient_id_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_patient_id_edit.placeholder_text = "BN001"
	_patient_id_edit.text = Global.current_patient_id
	row1.add_child(_patient_id_edit)

	row1.add_child(_plain_label("Họ và tên:", 14))

	_patient_name_edit = LineEdit.new()
	_patient_name_edit.custom_minimum_size = Vector2(160, 32)
	_patient_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_patient_name_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_patient_name_edit.placeholder_text = "Họ tên người bệnh"
	_patient_name_edit.text = Global.current_patient_name
	row1.add_child(_patient_name_edit)

	var switch_btn := Button.new()
	switch_btn.text = "Lưu / Đổi Tên"
	switch_btn.custom_minimum_size = Vector2(110, 32)
	switch_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	switch_btn.pressed.connect(_on_switch_patient_pressed)
	row1.add_child(switch_btn)

	# Khung chon ho so (se an khi o Che do Nguoi benh)
	_doctor_section_container = HBoxContainer.new()
	_doctor_section_container.add_theme_constant_override("separation", 10)
	row1.add_child(_doctor_section_container)

	_doctor_section_container.add_child(_plain_label("Hồ sơ:", 14))

	_preset_patient_option = OptionButton.new()
	_preset_patient_option.custom_minimum_size = Vector2(125, 32)
	_preset_patient_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for pid in Global.PRESET_PATIENT_IDS:
		_preset_patient_option.add_item("Hồ sơ " + pid)
	for i in range(Global.PRESET_PATIENT_IDS.size()):
		if Global.PRESET_PATIENT_IDS[i] == Global.current_patient_id:
			_preset_patient_option.selected = i
			break
	_doctor_section_container.add_child(_preset_patient_option)
	_preset_patient_option.item_selected.connect(func(idx: int):
		if idx >= 0 and idx < Global.PRESET_PATIENT_IDS.size():
			var selected_pid: String = Global.PRESET_PATIENT_IDS[idx]
			_patient_id_edit.text = selected_pid
			var p_name: String = str(Global.patient_profiles.get(selected_pid, {}).get("patient_name", "Bệnh nhân " + selected_pid))
			_patient_name_edit.text = p_name
			Global.switch_patient(selected_pid, p_name)
			_refresh_all()
	)

	_mode_toggle_btn = Button.new()
	_mode_toggle_btn.text = "Chế độ: Bác sĩ / NCKH"
	_mode_toggle_btn.custom_minimum_size = Vector2(170, 32)
	_mode_toggle_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mode_toggle_btn.tooltip_text = "Bật Chế độ Người bệnh: Khóa bảo mật, ẩn danh sách hồ sơ khác và các nút cấu hình DB."
	_mode_toggle_btn.pressed.connect(func():
		_patient_mode = not _patient_mode
		_mode_toggle_btn.text = "Chế độ: Người bệnh (Khóa)" if _patient_mode else "Chế độ: Bác sĩ / NCKH"
		_apply_patient_mode_visibility()
	)
	row1.add_child(_mode_toggle_btn)

	# --- HANG 2: Cong cu thao tac Database & Dong bo Online ---
	_toolbar_row2 = HBoxContainer.new()
	_toolbar_row2.add_theme_constant_override("separation", 10)
	_toolbar_row2.alignment = BoxContainer.ALIGNMENT_END
	toolbar_vbox.add_child(_toolbar_row2)

	var reset_btn := Button.new()
	reset_btn.text = "Làm mới ID này"
	reset_btn.custom_minimum_size = Vector2(125, 30)
	reset_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	reset_btn.tooltip_text = "Xóa trắng dữ liệu của ID đang chọn để người bệnh mới bắt đầu đo và tập lại từ đầu"
	reset_btn.pressed.connect(_on_reset_patient_pressed)
	_toolbar_row2.add_child(reset_btn)

	var sync_btn := Button.new()
	sync_btn.text = "Đồng bộ Cloud ngay"
	sync_btn.custom_minimum_size = Vector2(145, 30)
	sync_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sync_btn.pressed.connect(_on_sync_cloud_pressed)
	_toolbar_row2.add_child(sync_btn)

	var config_btn := Button.new()
	config_btn.text = "Cấu hình DB Online"
	config_btn.custom_minimum_size = Vector2(150, 30)
	config_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	config_btn.pressed.connect(func(): _cloud_modal.visible = true)
	_toolbar_row2.add_child(config_btn)

	# 3. Weekly Summary & Map Unlock Progress Cards (2 columns)
	var summary_row := HBoxContainer.new()
	summary_row.add_theme_constant_override("separation", 10)
	column.add_child(summary_row)
	column.move_child(summary_row, 2)

	var stats_card := PanelContainer.new()
	stats_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_row.add_child(stats_card)

	_weekly_stats_label = _label("", 14)
	stats_card.add_child(_weekly_stats_label)

	var progress_card := PanelContainer.new()
	progress_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary_row.add_child(progress_card)

	_map_progress_label = _label("", 14)
	progress_card.add_child(_map_progress_label)

	# 4. Visual ROM Progression Line Chart
	_rom_chart = RomLineChartScript.new()
	_rom_chart.name = "RomLineChart"
	_rom_chart.custom_minimum_size = Vector2(0, 175)
	column.add_child(_rom_chart)
	column.move_child(_rom_chart, 3)

	_apply_patient_mode_visibility()


func _apply_patient_mode_visibility() -> void:
	if _doctor_section_container != null:
		_doctor_section_container.visible = not _patient_mode
	if _toolbar_row2 != null:
		_toolbar_row2.visible = not _patient_mode
	if _patient_id_edit != null:
		_patient_id_edit.editable = not _patient_mode


func _build_cloud_config_modal() -> void:
	_cloud_modal = ColorRect.new()
	_cloud_modal.name = "CloudConfigModal"
	_cloud_modal.visible = false
	_cloud_modal.color = Color(0.0, 0.0, 0.0, 0.72)
	_cloud_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_cloud_modal)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cloud_modal.add_child(center)

	var dialog := PanelContainer.new()
	dialog.custom_minimum_size = Vector2(620, 440)
	center.add_child(dialog)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	dialog.add_child(root_vbox)

	# 1. Header (Co dinh o tren)
	var title := _plain_label("CẤU HÌNH DATABASE ONLINE (MONGODB / CLOUD)", 17)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title)

	# 2. Body trong ScrollContainer (Tu dong co cuon, KHONG BAO GIO TRAN RA NGOAI)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 300
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var desc := _label(
		"Hệ thống tự động lưu Offline trên máy và đồng bộ lên MongoDB Atlas Cloud qua cổng 8766. Cấu hình này chỉ cần thiết lập 1 lần cho đề tài.",
		13
	)
	vbox.add_child(desc)

	_cloud_enable_check = CheckBox.new()
	_cloud_enable_check.text = "Bật tự động đồng bộ dữ liệu lên Database Online (MongoDB Atlas / Cloud)"
	_cloud_enable_check.button_pressed = Global.cloud_db_enabled
	vbox.add_child(_cloud_enable_check)

	var provider_row := HBoxContainer.new()
	provider_row.add_theme_constant_override("separation", 10)
	vbox.add_child(provider_row)
	provider_row.add_child(_plain_label("Hệ quản trị CSDL:", 14))

	_cloud_provider_option = OptionButton.new()
	_cloud_provider_option.add_item("MongoDB (MongoDB Atlas Cloud / Compass)", 0)
	_cloud_provider_option.add_item("Supabase (PostgreSQL REST API)", 1)
	_cloud_provider_option.add_item("Firebase Realtime Database (JSON REST API)", 2)
	if Global.cloud_db_provider == "supabase":
		_cloud_provider_option.selected = 1
	elif Global.cloud_db_provider == "firebase":
		_cloud_provider_option.selected = 2
	else:
		_cloud_provider_option.selected = 0
	_cloud_provider_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	provider_row.add_child(_cloud_provider_option)

	vbox.add_child(_plain_label("Chuỗi kết nối MongoDB URI (hoặc Project URL):", 14))
	_cloud_url_edit = LineEdit.new()
	_cloud_url_edit.custom_minimum_size.y = 34
	_cloud_url_edit.placeholder_text = "mongodb+srv://<db_username>:<db_password>@clustergamephcn2d.6doylym.mongodb.net/"
	_cloud_url_edit.text = Global.cloud_db_url
	vbox.add_child(_cloud_url_edit)

	vbox.add_child(_plain_label("Tên Database MongoDB (Mặc định: rehab_pixel_game) hoặc API Key:", 14))
	_cloud_key_edit = LineEdit.new()
	_cloud_key_edit.custom_minimum_size.y = 34
	_cloud_key_edit.placeholder_text = "VD: rehab_pixel_game"
	_cloud_key_edit.secret = (Global.cloud_db_provider != "mongodb")
	_cloud_key_edit.text = Global.cloud_db_api_key
	vbox.add_child(_cloud_key_edit)

	_cloud_provider_option.item_selected.connect(func(idx: int):
		if idx == 0:
			_cloud_key_edit.secret = false
			if _cloud_url_edit.text.is_empty():
				_cloud_url_edit.text = "mongodb://localhost:27017"
			if _cloud_key_edit.text.is_empty():
				_cloud_key_edit.text = "rehab_pixel_game"
		else:
			_cloud_key_edit.secret = true
	)

	var sql_note := _label(
		"Lưu ý: Khi chạy game kèm 'python main.py' (hoặc 'python mongodb_service.py'), cầu nối MongoDB (cổng 8766) sẽ tự động chạy ngầm để lưu trực tiếp vào MongoDB Atlas Cloud.",
		12
	)
	vbox.add_child(sql_note)

	# 3. Footer ghim co dinh o day dialog (LUON LUON NHIN THAY VA BAM DUOC)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_END
	btn_row.add_theme_constant_override("separation", 12)
	root_vbox.add_child(btn_row)

	var save_btn := Button.new()
	save_btn.text = "Lưu cấu hình & Đồng bộ ngay"
	save_btn.custom_minimum_size = Vector2(210, 36)
	save_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	save_btn.pressed.connect(_on_save_cloud_config_pressed)
	btn_row.add_child(save_btn)

	var close_btn := Button.new()
	close_btn.text = "Đóng"
	close_btn.custom_minimum_size = Vector2(95, 36)
	close_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(func(): _cloud_modal.visible = false)
	btn_row.add_child(close_btn)


func _refresh_all() -> void:
	if _patient_id_edit != null:
		_patient_id_edit.text = Global.current_patient_id
	if _patient_name_edit != null:
		_patient_name_edit.text = Global.current_patient_name
	if _preset_patient_option != null:
		for i in range(Global.PRESET_PATIENT_IDS.size()):
			if Global.PRESET_PATIENT_IDS[i] == Global.current_patient_id:
				_preset_patient_option.selected = i
				break

	var sessions: Array = Global.get_patient_sessions(Global.current_patient_id)
	var rom_points: Array = Global.get_patient_rom_history(Global.current_patient_id)

	_update_weekly_summary_cards(sessions, rom_points)
	if _rom_chart != null and _rom_chart.has_method("set_rom_points"):
		_rom_chart.call("set_rom_points", rom_points)
	_populate_session_list(sessions)


func _update_weekly_summary_cards(sessions: Array, rom_points: Array) -> void:
	var total_sessions := sessions.size()
	var total_valid := 0
	var total_rejected := 0
	for entry in sessions:
		if entry is Dictionary:
			total_valid += int(entry.get("valid_reps", 0))
			total_rejected += int(entry.get("rejected_reps", 0))

	var total_attempts := total_valid + total_rejected
	var accuracy_pct := 100.0 if total_attempts == 0 else (float(total_valid) * 100.0 / float(total_attempts))

	var latest_rom: float = float(Global.max_rom_angle)
	var first_rom: float = latest_rom
	if not rom_points.is_empty():
		first_rom = float(rom_points[0].get("rom_angle", latest_rom))
		latest_rom = float(rom_points[rom_points.size() - 1].get("rom_angle", latest_rom))
	var delta_rom: float = latest_rom - first_rom
	var delta_sign: String = "+" if delta_rom >= 0.0 else ""
	var eval_status: String = "Đang tiến triển tốt" if delta_rom > 2.0 else ("Duy trì ổn định" if latest_rom > 0.0 else "Chưa đo ROM")

	_weekly_stats_label.text = (
		"TỔNG KẾT HỒ SƠ: %s (%s)\n" % [Global.current_patient_name, Global.current_patient_id]
		+ "• Số buổi hoàn thành: %d buổi  |  Số ngày đo ROM: %d ngày\n" % [total_sessions, rom_points.size()]
		+ "• Động tác chuẩn: %d lần  |  Chưa đạt: %d lần  |  Chính xác: %.1f%%\n" % [total_valid, total_rejected, accuracy_pct]
		+ "• Góc ROM hiện tại: %.1f° / 90.0° (%s%.1f° so với ngày đầu) — %s" % [latest_rom, delta_sign, delta_rom, eval_status]
	)

	var map_lines: Array[String] = ["TIẾN ĐỘ LUYỆN TẬP 5 MAP:"]
	var unlocked_total := 0
	for map_id in range(1, 6):
		var lvl := Global.get_unlocked_level_for_action(map_id)
		unlocked_total += lvl
		var stars := "★".repeat(lvl) + "☆".repeat(max(0, 3 - lvl))
		map_lines.append("• Map %d (%s): Mức %d/3 %s" % [map_id, MAP_NAMES[map_id - 1].get_slice(" (", 0), lvl, stars])
	var completion_pct := float(unlocked_total) * 100.0 / 15.0
	map_lines[0] = "TIẾN ĐỘ 5 MAP (Hoàn thành %.0f%% - %d/15 Mức):" % [completion_pct, unlocked_total]
	_map_progress_label.text = "\n".join(map_lines)


func _populate_session_list(sessions: Array) -> void:
	var list: VBoxContainer = $Margin/Column/Scroll/List
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()

	if sessions.is_empty():
		var box := _card(list)
		box.add_child(_label("CHƯA CÓ LỊCH SỬ BUỔI TẬP CHO HỒ SƠ %s" % Global.current_patient_id, 20))
		box.add_child(_label("Hãy thực hiện Hiệu chuẩn (Calibration) hoặc chọn Map để bắt đầu thu thập số liệu tập luyện thực tế.", 16))
		var start := Button.new()
		start.text = "CHỌN MAP ĐỂ BẮT ĐẦU"
		start.custom_minimum_size.y = 42
		start.pressed.connect(func():
			get_tree().change_scene_to_file("res://ui/screens/map_selection/level_selection.tscn")
		)
		box.add_child(start)
		return

	for index in range(sessions.size() - 1, -1, -1):
		var entry: Dictionary = sessions[index]
		var box := _card(list)
		var map_id := int(entry.get("map_id", 1))
		var map_name: String = MAP_NAMES[map_id - 1] if map_id >= 1 and map_id <= 5 else "Buổi tập"
		var rom_val: float = float(entry.get("rom_angle", Global.max_rom_angle))
		var rom_str := "  •  Góc ROM: %.1f°" % rom_val if rom_val > 0.0 else ""
		box.add_child(_label("Map %d · %s  —  Mức %d%s" % [map_id, map_name, int(entry.get("difficulty", 1)), rom_str], 19))
		box.add_child(_label("%s  •  ID: %s" % [
			_local_time(str(entry.get("ended_at_utc", entry.get("completed_at_utc", "")))),
			str(entry.get("patient_id", Global.current_patient_id)),
		], 15))
		if entry.has("status"):
			box.add_child(_label(Display.status(entry), 16))
		var stats := "Hợp lệ: %d lần     •     Chưa hợp lệ: %d lần" % [int(entry.get("valid_reps", 0)), int(entry.get("rejected_reps", 0))]
		if entry.has("bonus_points"):
			stats += "     •     Điểm thưởng: %d" % int(entry.bonus_points)
		box.add_child(_label(stats, 17))
		if TrackingStability.ENABLED and bool(entry.get("stability_enabled", true)):
			box.add_child(_label("Ổn định: %d/3" % int(entry.get("stability", 0)), 16))
		var evaluation := str(entry.get("evaluation", ""))
		if not evaluation.is_empty():
			box.add_child(_label("Đánh giá trong game: " + evaluation, 16))
		var detail := _label(Display.compact_details(entry), 16)
		detail.hide()
		var toggle := Button.new()
		toggle.text = "XEM CHI TIẾT"
		toggle.toggle_mode = true
		toggle.custom_minimum_size.y = 38
		toggle.toggled.connect(func(open: bool):
			detail.visible = open
			toggle.text = "THU GỌN" if open else "XEM CHI TIẾT"
		)
		box.add_child(toggle)
		box.add_child(detail)


func _card(list: VBoxContainer) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	return box


func _plain_label(value: String, font_size: int) -> Label:
	var item := Label.new()
	item.text = value
	item.autowrap_mode = TextServer.AUTOWRAP_OFF
	item.add_theme_font_size_override("font_size", font_size)
	item.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return item


func _label(value: String, font_size: int) -> Label:
	var item := Label.new()
	item.text = value
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_theme_font_size_override("font_size", font_size)
	return item


func _local_time(utc: String) -> String:
	if utc.is_empty():
		return "Chưa có thông tin thời gian"
	var timestamp := Time.get_unix_time_from_datetime_string(utc)
	var local := Time.get_datetime_dict_from_unix_time(timestamp + int(Time.get_time_zone_from_system().bias) * 60)
	return "%02d/%02d/%04d  ·  %02d:%02d" % [local.day, local.month, local.year, local.hour, local.minute]


func _on_switch_patient_pressed() -> void:
	var new_id := _patient_id_edit.text.strip_edges()
	var new_name := _patient_name_edit.text.strip_edges()
	if new_id.is_empty():
		new_id = "BN001"
	Global.switch_patient(new_id, new_name)
	_refresh_all()


func _on_reset_patient_pressed() -> void:
	Global.reset_patient(Global.current_patient_id)
	_refresh_all()


func _on_sync_cloud_pressed() -> void:
	if not Global.cloud_db_enabled or Global.cloud_db_url.is_empty():
		_cloud_modal.visible = true
		return
	Global.sync_patient_to_cloud(Global.current_patient_id)
	Global.fetch_patient_from_cloud(Global.current_patient_id)


func _on_save_cloud_config_pressed() -> void:
	var enabled := _cloud_enable_check.button_pressed
	var provider := "mongodb"
	if _cloud_provider_option.selected == 1:
		provider = "supabase"
	elif _cloud_provider_option.selected == 2:
		provider = "firebase"
	var url := _cloud_url_edit.text.strip_edges()
	var key := _cloud_key_edit.text.strip_edges()
	Global.save_cloud_config(enabled, provider, url, key)
	_cloud_modal.visible = false
	if enabled:
		Global.sync_patient_to_cloud(Global.current_patient_id)


func _on_cloud_sync_status_changed(status_text: String, success: bool) -> void:
	if _cloud_status_label == null:
		return
	_cloud_status_label.text = status_text
	_cloud_status_label.add_theme_color_override(
		"font_color",
		Color("8ef5a5") if success else Color("ff9e9e")
	)


func _initial_cloud_status_text() -> String:
	if Global.cloud_db_enabled and not Global.cloud_db_url.is_empty():
		return "Cloud DB (%s): Đã bật tự động đồng bộ" % Global.cloud_db_provider.to_upper()
	return "Cloud DB: Đang lưu Offline (Nhấn 'Cấu hình DB Online' để nối MongoDB)"
