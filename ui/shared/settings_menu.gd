extends CanvasLayer

const HOME_SCENE := "res://ui/screens/start/start_screen.tscn"
const CAMERA_SCENE := "res://ui/screens/calibration/calibration_screen.tscn"
const MAP_SELECTION_SCENE := "res://ui/screens/map_selection/level_selection.tscn"

var _previous_pause := false
var _pending_scene := ""
var _trigger: Button

@onready var overlay: Control = $Overlay
@onready var volume: HSlider = $Overlay/Center/Panel/Margin/Contents/Volume
@onready var volume_label: Label = $Overlay/Center/Panel/Margin/Contents/VolumeLabel
@onready var mute: CheckButton = $Overlay/Center/Panel/Margin/Contents/Mute
@onready var resume: Button = $Overlay/Center/Panel/Margin/Contents/Resume
@onready var confirm: ConfirmationDialog = $Confirm


func _ready() -> void:
	_trigger = get_parent().get_node("UI/SettingsButton") as Button
	_trigger.pressed.connect(open_menu)
	volume.value_changed.connect(_on_volume_changed)
	mute.toggled.connect(_on_mute_toggled)
	resume.pressed.connect(close_menu)
	$Overlay/Center/Panel/Margin/Contents/Home.pressed.connect(_request_navigation.bind(HOME_SCENE))
	$Overlay/Center/Panel/Margin/Contents/MapSelection.pressed.connect(_request_navigation.bind(MAP_SELECTION_SCENE))
	$Overlay/Center/Panel/Margin/Contents/Camera.pressed.connect(_request_navigation.bind(CAMERA_SCENE))
	confirm.confirmed.connect(_navigate)
	confirm.canceled.connect(resume.grab_focus)
	overlay.hide()


func open_menu() -> void:
	if overlay.visible:
		return
	_previous_pause = get_tree().paused
	get_tree().paused = true
	volume.set_value_no_signal(db_to_linear(AudioServer.get_bus_volume_db(0)) * 100.0)
	mute.set_pressed_no_signal(AudioServer.is_bus_mute(0))
	_update_volume_label(volume.value)
	overlay.show()
	resume.grab_focus()


func close_menu() -> void:
	confirm.hide()
	overlay.hide()
	get_tree().paused = _previous_pause
	_trigger.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	if overlay.visible and event.is_action_pressed("ui_cancel"):
		if confirm.visible:
			confirm.hide()
			resume.grab_focus()
		else:
			close_menu()
		get_viewport().set_input_as_handled()


func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value / 100.0, 0.0001)))
	_update_volume_label(value)


func _on_mute_toggled(enabled: bool) -> void:
	AudioServer.set_bus_mute(0, enabled)


func _update_volume_label(value: float) -> void:
	volume_label.text = "Âm lượng tổng: %d%%" % roundi(value)


func _request_navigation(scene_path: String) -> void:
	_pending_scene = scene_path
	confirm.dialog_text = "Rời màn chơi sẽ kết thúc lượt tập hiện tại.\nBạn có muốn tiếp tục?"
	confirm.popup_centered()


func _navigate() -> void:
	# Map _exit_tree() stops its exercise session during the scene change.
	# Cache the tree: a successful scene change detaches this menu immediately.
	var tree := get_tree()
	var error := tree.change_scene_to_file(_pending_scene)
	if error != OK:
		confirm.dialog_text = "Không mở được trang. Hãy đóng bảng và thử lại."
		confirm.popup_centered()
		return
	tree.paused = _previous_pause


func _exit_tree() -> void:
	if is_instance_valid(overlay) and overlay.visible:
		get_tree().paused = _previous_pause
