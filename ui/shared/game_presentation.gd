extends Node
const Guide = preload("res://ui/shared/exercise_guide.gd")
var level: Node
var ui: CanvasLayer
var map_id := 1
var session: Node
var replay: Control
var replay_guide: Control
var resuming := -1.0
var owns_pause := false
var was_paused := false
var replay_label: Label
var intro_guide: Control
var status_display: RichTextLabel
var last_status := ""
var last_subtitle := ""
const STATUS_COLORS := {
	"ĐANG TẬP": "75e889", "TẠM DỪNG": "ffdc69",
	"ĐANG NGHỈ": "80caff", "CHUẨN BỊ": "ffd28a",
	"MẤT NHẬN DIỆN": "ff8585", "HOÀN THÀNH": "75e8cb",
	"HƯỚNG DẪN": "c7d8ef", "CHỜ": "c7d8ef"
}
const SHOW_ROM_DEBUG_WINDOW := true
var rom_panel: PanelContainer
var camera_bg: ColorRect
var camera_rect: TextureRect
var camera_tex: ImageTexture
var camera_title: Label
var camera_placeholder: Label
var camera_toggle_btn: Button
var is_camera_focused := false

func place(item: Control, rect: Rect2) -> void:
	item.set_anchors_preset(Control.PRESET_TOP_LEFT)
	item.position = rect.position
	item.size = rect.size
	if item is Label:
		item.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		item.add_theme_font_size_override("font_size",18)
		item.add_theme_color_override("font_color",Color("f3f2de"))
		item.add_theme_color_override("font_outline_color",Color("14251e"))
		item.add_theme_constant_override("outline_size",4)

func label(value: String, rect: Rect2, parent: Node) -> Label:
	var item := Label.new()
	item.text = value
	parent.add_child(item)
	place(item,rect)
	return item

func button(value: String, rect: Rect2, callback: Callable) -> Button:
	var item := Button.new()
	item.text = value
	ui.add_child(item)
	place(item,rect)
	item.add_theme_font_size_override("font_size",17)
	item.pressed.connect(callback)
	return item

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	level = get_parent()
	map_id = int(level.scene_file_path.get_slice("map_",1).get_slice("/",0))
	session = level.get_node("ExerciseSession")
	AudioManager.attach_level.call_deferred(level, map_id)
	ui = level.get_node("UI")
	if map_id == 4: level.get_node("Player/FollowCamera").position.y = -20
	# Gameplay actor now renders animated pixel steam instead of static diamonds.
	if map_id == 5: level.get_node("Map5RestZone/Steam").hide()
	for name in ["HudBacking","HudLeftBacking","HudRightBacking","DebugHelp","BonusPanel"]:
		var node := ui.get_node_or_null(name)
		if node != null: node.hide()
	var bottom := ColorRect.new()
	bottom.position = Vector2(0,366)
	bottom.size = Vector2(1152,282)
	bottom.color = Color(0.04,0.075,0.05,0.91)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bottom)
	ui.move_child(bottom,0)
	label("MAP %d · BUỔI TẬP" % map_id,Rect2(24,378,250,26),ui)
	# Preserve the controller's Label as the source of truth, render only value in color.
	place(level.state_label,Rect2(290,378,294,26))
	level.state_label.hide()
	status_display = RichTextLabel.new()
	status_display.name = "ColoredStatus"
	status_display.bbcode_enabled = true
	status_display.scroll_active = false
	status_display.autowrap_mode = TextServer.AUTOWRAP_OFF
	status_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_display.add_theme_font_size_override("normal_font_size",16)
	status_display.add_theme_color_override("default_color",Color("f3f2de"))
	ui.add_child(status_display)
	place(status_display,Rect2(290,380,294,28))
	_sync_status()
	place(level.phase_label,Rect2(24,441,230,26))
	place(level.rep_label,Rect2(290,441,250,26))
	place(level.feedback_label,Rect2(328,24,558,95))
	level.feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level.feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	level.feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	level.feedback_label.add_theme_font_size_override("font_size",28)
	level.hearts_label.visible = TrackingStability.ENABLED
	place(level.hearts_label,Rect2(940,24,200,32))
	level.hearts_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	level.hearts_label.add_theme_font_size_override("font_size",20)
	level.hearts_label.add_theme_color_override("font_color",Color("ff7171"))
	for name in ["RockProgressLabel","LiftProgressLabel","PushProgressLabel","ClimbProgressLabel","StretchProgressLabel"]:
		var node := ui.get_node_or_null(name)
		if node != null: place(node,Rect2(24,474,510,26))
	for name in ["DirectionLabel","SideLabel"]:
		var node := ui.get_node_or_null(name)
		if node != null: place(node,Rect2(24,505,510,26))
	var bonus := ui.get_node_or_null("BonusLabel")
	if bonus != null: place(bonus,Rect2(284,505,260,26))
	var hold := ui.get_node_or_null("HoldPanel")
	if hold != null:
		place(hold,Rect2(24,539,516,44))
		hold.get_node("Backing").hide()
		place(hold.get_node("HoldLabel"),Rect2(0,0,516,24))
		place(hold.get_node("HoldBar"),Rect2(0,28,516,12))
	place(level.rest_label,Rect2(280,122,592,86))
	level.rest_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button("Xem hướng dẫn [U]",Rect2(24,596,516,44),_review)

	camera_bg = ColorRect.new()
	camera_bg.color = Color("172b24")
	camera_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(camera_bg)

	camera_rect = TextureRect.new()
	camera_rect.name = "CameraStreamRect"
	camera_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	camera_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	camera_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	camera_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(camera_rect)

	camera_title = label("CAMERA NGƯỜI TẬP [C]", Rect2(0, 0, 100, 22), ui)
	camera_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	camera_title.add_theme_color_override("font_color", Color("00e676"))

	camera_toggle_btn = Button.new()
	camera_toggle_btn.text = "⛶ Toàn cảnh"
	camera_toggle_btn.add_theme_font_size_override("font_size", 12)
	camera_toggle_btn.pressed.connect(_toggle_camera_focus)
	ui.add_child(camera_toggle_btn)

	camera_placeholder = label("Chưa kết nối camera\n\nKhung camera trực quan\ntheo dõi tư thế tập luyện.", Rect2(0, 0, 100, 60), ui)
	camera_placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	if PoseInput.has_signal("camera_frame_received"):
		PoseInput.connect("camera_frame_received", func(img: Image):
			if img == null or img.is_empty() or not is_instance_valid(camera_rect):
				return
			if camera_tex != null and camera_tex.get_width() == img.get_width() and camera_tex.get_height() == img.get_height() and camera_tex.get_format() == img.get_format():
				camera_tex.update(img)
			else:
				camera_tex = ImageTexture.create_from_image(img)
			camera_rect.texture = camera_tex
			if is_instance_valid(camera_placeholder) and camera_placeholder.visible:
				camera_placeholder.hide()
		)

	PoseInput.connection_changed.connect(func(connected: bool, _details):
		if not connected and is_instance_valid(camera_placeholder):
			camera_placeholder.text = "Mất kết nối camera Python Backend.\n\nHãy khởi động lại python main.py"
			camera_placeholder.show()
	)

	_build_rom_debug_window()
	_update_camera_layout()
	_build_intro()
	var results := preload("res://ui/shared/session_results.gd").new()
	level.add_child.call_deferred(results)
	# Ensure overlays stay above newly added HUD controls.
	for name in ["InstructionPanel","ResultPanel","CountdownLabel","RestLabel"]:
		ui.move_child(ui.get_node(name),-1)
	session.hold_progress_changed.connect(_hold)
	session.hold_interrupted.connect(func(_data): _reset_actor())
	session.state_changed.connect(func(state, _previous):
		if state != ExerciseSession.State.ACTIVE: _reset_actor())
	session.progress_changed.connect(func(_rep,_required,phase,_phases):
		if map_id == 5:
			level.get_node("Player").mk2.mirrored = phase == 2
			level.get_node("Player").mk2.refresh())

func _build_intro() -> void:
	var panel: PanelContainer = level.instruction_panel
	var style := StyleBoxFlat.new()
	style.bg_color = Color("20392f")
	style.border_color = Color("90a080")
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel",style)
	var margin := panel.get_node("MarginContainer")
	for edge in ["left","right"]: margin.add_theme_constant_override("margin_"+edge,18)
	for edge in ["top","bottom"]: margin.add_theme_constant_override("margin_"+edge,16)
	var box := panel.get_node("MarginContainer/VBoxContainer")
	for child in box.get_children():
		if child != level.instruction_start_button: child.hide()
	intro_guide = Guide.new()
	intro_guide.map_id = map_id
	intro_guide.process_mode = Node.PROCESS_MODE_PAUSABLE
	box.add_child(intro_guide)
	box.move_child(intro_guide,0)
	intro_guide.finished.connect(func():
		if panel.visible and not level.instruction_start_button.disabled:
			level.instruction_start_button.pressed.emit())
	place(panel,Rect2(136,20,880,608))
	level.instruction_start_button.text = "SẴN SÀNG · VÀO CHƠI"

func _hold(progress: float, _elapsed: int, _target: int) -> void:
	var actor = level.get_node("Player").mk2
	actor.amount = clampf(progress,0,1)
	actor.refresh()

func _reset_actor() -> void:
	var actor = level.get_node("Player").mk2
	actor.amount = 0
	actor.refresh()

func _joints() -> void:
	var actor = level.get_node("Player").mk2
	actor.joints_visible = not actor.joints_visible
	actor.refresh()

func _review() -> void:
	if is_instance_valid(replay) or level._intro_running or level.instruction_panel.visible or level.result_panel.visible: return
	was_paused = get_tree().paused
	if was_paused: return
	owns_pause = true
	ui.get_node("SettingsButton").disabled = true
	session.set_menu_paused(true)
	get_tree().paused = true
	replay = Control.new()
	# Keep replay controls interactive while the gameplay tree is paused.
	replay.process_mode = Node.PROCESS_MODE_ALWAYS
	replay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.add_child(replay)
	var shade := ColorRect.new()
	shade.size = Vector2(1152,648)
	shade.color = Color(0,0,0,0.8)
	replay.add_child(shade)
	replay_guide = Guide.new()
	replay_guide.map_id = map_id
	replay_guide.position = Vector2(156,28)
	replay_guide.process_mode = Node.PROCESS_MODE_DISABLED
	replay.add_child(replay_guide)
	replay_guide.finished.connect(_resume)
	var close := Button.new()
	close.position = Vector2(400,534)
	close.size = Vector2(350,48)
	close.text = "TIẾP TỤC CHƠI"
	close.pressed.connect(_resume)
	replay.add_child(close)
	close.grab_focus()
	close.focus_next = NodePath(".")
	close.focus_previous = NodePath(".")
	replay_label = label("",Rect2(400,594,350,36),replay)

func _resume() -> void:
	if resuming >= 0: return
	replay_guide.complete = true
	resuming = 3

func _sync_subtitle() -> void:
	var caption: Label = level.feedback_label
	if caption.text == last_subtitle: return
	var raw := caption.text.replace("\n", " ").strip_edges()
	var font := caption.get_theme_font("font")
	var font_size := caption.get_theme_font_size("font_size")
	var width := caption.size.x - 8.0
	last_subtitle = raw
	if font.get_string_size(raw, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		var words := raw.split(" ", false)
		var best_score := INF
		for split in range(2, words.size() - 1):
			var left := " ".join(words.slice(0, split))
			var right := " ".join(words.slice(split))
			var a := font.get_string_size(left, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var b := font.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if a > width or b > width: continue
			var score := absf(a - b)
			if left.ends_with(".") or left.ends_with("!") or left.ends_with("—"): score -= width * 0.3
			if score < best_score:
				best_score = score
				last_subtitle = left + "\n" + right
	caption.text = last_subtitle

func _sync_status() -> void:
	var value: String = level.state_label.text.trim_prefix("TRẠNG THÁI:").strip_edges()
	if get_tree().paused: value = "TẠM DỪNG"
	if value == last_status: return
	last_status = value
	status_display.text = "TRẠNG THÁI: [color=#%s]%s[/color]" % [STATUS_COLORS.get(value,"c7d8ef"),value]

func _process(delta: float) -> void:
	_sync_subtitle()
	_sync_status()
	if not is_instance_valid(replay): return
	if level.get_node("SettingsMenu").overlay.visible: return
	if resuming < 0:
		replay_guide._process(delta)
	else:
		resuming -= delta
		replay_label.text = "Tiếp tục trong %d…" % maxi(1,ceili(resuming))
		if resuming <= 0:
			replay.queue_free()
			replay = null
			resuming = -1
			get_tree().paused = was_paused
			session.set_menu_paused(false)
			owns_pause = false
			ui.get_node("SettingsButton").disabled = false
			ui.get_node("SettingsButton").grab_focus()

func _unhandled_key_input(event: InputEvent) -> void:
	if is_instance_valid(replay) and event.is_action_pressed("ui_cancel") and not event.is_echo():
		_resume()
		get_viewport().set_input_as_handled()
		return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_C and not get_tree().paused:
		_toggle_camera_focus()
		return
	if event.keycode == KEY_F3:
		if is_instance_valid(rom_panel):
			rom_panel.visible = not rom_panel.visible
			_update_camera_layout()
		return
	if get_tree().paused: return
	if event.keycode == KEY_U: _review()
	if event.keycode == KEY_I: _joints()

func _exit_tree() -> void:
	if owns_pause: get_tree().paused = was_paused

func _build_rom_debug_window() -> void:
	rom_panel = PanelContainer.new()
	rom_panel.name = "RomDebugWindow"
	rom_panel.position = Vector2(556, 372)
	rom_panel.size = Vector2(216, 266)
	rom_panel.visible = SHOW_ROM_DEBUG_WINDOW
	ui.add_child(rom_panel)

	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color("0d1e16")
	p_style.border_color = Color("2e7d5a")
	p_style.set_border_width_all(2)
	p_style.set_corner_radius_all(4)
	rom_panel.add_theme_stylebox_override("panel", p_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	rom_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)

	var header_box := HBoxContainer.new()
	vbox.add_child(header_box)

	var title_lbl := Label.new()
	title_lbl.text = "[ DEBUG ROM ]"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_color_override("font_color", Color("00e676"))
	title_lbl.add_theme_font_size_override("font_size", 14)
	header_box.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "×"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 14)
	close_btn.pressed.connect(func():
		rom_panel.visible = false
		_update_camera_layout()
	)
	header_box.add_child(close_btn)

	var rom_state_label := Label.new()
	rom_state_label.text = "Trạng thái: CHUẨN BỊ"
	rom_state_label.add_theme_color_override("font_color", Color("ffd28a"))
	rom_state_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(rom_state_label)

	var rom_value_label := Label.new()
	rom_value_label.text = "Biên độ ROM: 0%"
	rom_value_label.add_theme_color_override("font_color", Color("f3f2de"))
	rom_value_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(rom_value_label)

	var rom_bar := ProgressBar.new()
	rom_bar.custom_minimum_size = Vector2(0, 16)
	rom_bar.max_value = 100.0
	rom_bar.value = 0.0
	rom_bar.show_percentage = true
	vbox.add_child(rom_bar)

	var hold_title_label := Label.new()
	var def_target: float = 30.0 if map_id == 5 else (0.7 if map_id == 1 else 5.0)
	hold_title_label.text = "Giữ thế: 0.0s / %.1fs" % def_target
	hold_title_label.add_theme_color_override("font_color", Color("80caff"))
	hold_title_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(hold_title_label)

	var hold_bar := ProgressBar.new()
	hold_bar.custom_minimum_size = Vector2(0, 14)
	hold_bar.max_value = 100.0
	hold_bar.value = 0.0
	hold_bar.show_percentage = false
	vbox.add_child(hold_bar)

	var rom_fb_label := Label.new()
	rom_fb_label.text = ">> Sẵn sàng bắt đầu"
	rom_fb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rom_fb_label.add_theme_color_override("font_color", Color("b8e2c8"))
	rom_fb_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(rom_fb_label)

	var hint_lbl := Label.new()
	hint_lbl.text = "[F3]: Ẩn/Hiện debug"
	hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.6, 0.7))
	hint_lbl.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint_lbl)

	PoseInput.pose_frame_received.connect(func(data: Dictionary):
		if not is_instance_valid(rom_panel) or not rom_panel.visible:
			return
		var ex: Dictionary = data.get("exercise", {})
		var rom_prog: float = float(ex.get("rom_progress", 0.0))
		var hold_prog: float = float(ex.get("hold_progress", 0.0))
		var movement_state: String = str(ex.get("movement_state", "READY"))
		var fb_code: String = str(ex.get("feedback_code", ""))

		rom_value_label.text = "Biên độ ROM: %d%%" % roundi(rom_prog * 100.0)
		rom_bar.value = rom_prog * 100.0
		rom_state_label.text = "Trạng thái: %s" % movement_state

		var target_sec: float = 30.0 if map_id == 5 else (0.7 if map_id == 1 else 5.0)
		if hold_prog > 0.0:
			var cur_sec: float = hold_prog * target_sec
			hold_title_label.text = "Giữ thế: %.1fs / %.1fs (%d%%)" % [cur_sec, target_sec, roundi(hold_prog * 100.0)]
			hold_bar.value = hold_prog * 100.0
		else:
			hold_title_label.text = "Giữ thế: 0.0s / %.1fs" % target_sec
			hold_bar.value = 0.0

		if not fb_code.is_empty():
			rom_fb_label.text = ">> %s" % _vn_fb(fb_code)
	)

	session.hold_progress_changed.connect(func(prog: float, elapsed: int, target: int):
		if is_instance_valid(rom_panel) and rom_panel.visible:
			hold_bar.value = prog * 100.0
			hold_title_label.text = "Giữ thế: %.1fs / %.1fs (%d%%)" % [float(elapsed)/1000.0, float(target)/1000.0, roundi(prog * 100.0)]
	)


func _update_camera_layout() -> void:
	if not is_instance_valid(camera_bg) or not is_instance_valid(camera_rect):
		return

	if is_camera_focused:
		var cam_rect_pos := Vector2(256, 84)
		var cam_rect_size := Vector2(640, 480)
		camera_bg.position = cam_rect_pos
		camera_bg.size = cam_rect_size
		camera_bg.color = Color(0.08, 0.14, 0.11, 0.96)
		camera_rect.position = cam_rect_pos
		camera_rect.size = cam_rect_size
		camera_title.position = Vector2(cam_rect_pos.x + 12, cam_rect_pos.y + 6)
		camera_title.size = Vector2(cam_rect_size.x - 140, 24)
		camera_title.text = "CAMERA TOÀN CẢNH (640x480) - Nhấn [C] để thu nhỏ"
		camera_toggle_btn.position = Vector2(cam_rect_pos.x + cam_rect_size.x - 120, cam_rect_pos.y + 6)
		camera_toggle_btn.size = Vector2(110, 26)
		camera_toggle_btn.text = "✕ Thu nhỏ [C]"
		camera_placeholder.position = Vector2(cam_rect_pos.x + 120, cam_rect_pos.y + 200)
		camera_placeholder.size = Vector2(400, 80)

		ui.move_child(camera_bg, -1)
		ui.move_child(camera_rect, -1)
		ui.move_child(camera_title, -1)
		ui.move_child(camera_toggle_btn, -1)
		if is_instance_valid(camera_placeholder):
			ui.move_child(camera_placeholder, -1)
	else:
		var show_debug: bool = is_instance_valid(rom_panel) and rom_panel.visible
		var cam_x: float = 780.0 if show_debug else 608.0
		var cam_w: float = 356.0 if show_debug else 480.0
		var cam_pos := Vector2(cam_x, 372)
		var cam_size := Vector2(cam_w, 266)

		camera_bg.position = cam_pos
		camera_bg.size = cam_size
		camera_bg.color = Color("172b24")
		camera_rect.position = cam_pos
		camera_rect.size = cam_size
		camera_title.position = Vector2(cam_pos.x + 12, cam_pos.y + 6)
		camera_title.size = Vector2(cam_size.x - 130, 22)
		camera_title.text = "CAMERA NGƯỜI TẬP [C]"
		camera_toggle_btn.position = Vector2(cam_pos.x + cam_size.x - 116, cam_pos.y + 6)
		camera_toggle_btn.size = Vector2(106, 24)
		camera_toggle_btn.text = "⛶ Toàn cảnh"
		camera_placeholder.position = Vector2(cam_pos.x + 16, cam_pos.y + 92)
		camera_placeholder.size = Vector2(cam_size.x - 32, 90)


func _toggle_camera_focus() -> void:
	is_camera_focused = not is_camera_focused
	_update_camera_layout()

func _vn_fb(code: String) -> String:
	const VN := {
		"POSITION_OK": "Vị trí phù hợp, sẵn sàng",
		"PREP_POSITION": "Vào thế chuẩn bị",
		"PREP_COMPLETED": "Đã chuẩn bị xong, bắt đầu cử động",
		"CLOSE_ELBOWS": "Khép 2 khuỷu tay về trước mặt",
		"OPEN_ARMS": "Dang rộng 2 tay sang 2 bên",
		"REACH_OVERHEAD": "Vươn 2 tay lên cao trên đầu",
		"CONTINUE_MOVEMENT": "Tiếp tục cử động đến ngưỡng đích...",
		"TARGET_REACHED": "Đạt ngưỡng mục tiêu!",
		"HOLD_STARTED": "Đang giữ thế cử động...",
		"KEEP_POSITION": "Duy trì giữ nguyên tư thế",
		"HOLD_COMPLETED": "Hoàn thành thời gian giữ thế!",
		"HOLD_INTERRUPTED": "Tư thế bị gián đoạn! Hãy thử lại",
		"RETURN_TO_PREP": "Đưa tay về tư thế ban đầu",
		"RELEASE_POSITION": "Đưa tay về trước (ROM < 40%) để chuẩn bị",
		"READY_FOR_NEXT_REP": "Sẵn sàng! Hãy ép hai bả vai ra sau",
		"REP_VALID": "Động tác hợp lệ! Rất tốt",
		"LIFT_SUCCESS": "Đã đẩy tảng đá thành công!",
		"PUSH_SUCCESS": "Đã đẩy lùi 2 bức tường!",
		"JUMP_SUCCESS": "Đã nhảy lên bậc tiếp theo!",
		"TRACKING_LOST": "Mất nhận diện camera",
	}
	return VN.get(code, code)
