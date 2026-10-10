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
const STATUS_COLORS := {
	"ĐANG TẬP": "75e889", "TẠM DỪNG": "ffdc69",
	"ĐANG NGHỈ": "80caff", "CHUẨN BỊ": "ffd28a",
	"MẤT NHẬN DIỆN": "ff8585", "HOÀN THÀNH": "75e8cb",
	"HƯỚNG DẪN": "c7d8ef", "CHỜ": "c7d8ef"
}

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
	ui = level.get_node("UI")
	if map_id == 4: level.get_node("Player/FollowCamera").position.y = -20
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
	level.feedback_label.add_theme_font_size_override("font_size",20)
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
	button("Xem hướng dẫn [U]",Rect2(24,596,246,44),_review)
	button("Ẩn/hiện khớp [I]",Rect2(288,596,252,44),_joints)
	var camera := ColorRect.new()
	camera.position = Vector2(608,368)
	camera.size = Vector2(480,270)
	camera.color = Color("172b24")
	camera.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(camera)
	label("CAMERA NGƯỜI TẬP",Rect2(654,397,390,28),ui)
	label("Chưa kết nối camera\n\nKhung 16:9 dành cho hình ảnh\nsau khi tích hợp backend.",Rect2(650,456,420,148),ui)
	_build_intro()
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
	actor.amount = clampf(progress*4,0,1)
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
	replay_label = label("",Rect2(400,594,350,36),replay)

func _resume() -> void:
	if resuming >= 0: return
	replay_guide.complete = true
	resuming = 3

func _sync_status() -> void:
	var value: String = level.state_label.text.trim_prefix("TRẠNG THÁI:").strip_edges()
	if get_tree().paused: value = "TẠM DỪNG"
	if value == last_status: return
	last_status = value
	status_display.text = "TRẠNG THÁI: [color=#%s]%s[/color]" % [STATUS_COLORS.get(value,"c7d8ef"),value]

func _process(delta: float) -> void:
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

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or get_tree().paused: return
	if event.keycode == KEY_U: _review()
	if event.keycode == KEY_I: _joints()

func _exit_tree() -> void:
	if owns_pause: get_tree().paused = was_paused
