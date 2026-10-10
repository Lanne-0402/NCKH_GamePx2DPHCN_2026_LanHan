extends Node

const SAVE_VERSION := 1
var save_path := "user://player_progress.json"
var persistence_enabled := true
var volume_percent := 100.0
var audio_muted := false
var session_history: Array = []
var last_save_error := ""


func _ready() -> void:
	# Smoke tests never touch the player's real profile.
	for argument in OS.get_cmdline_user_args():
		if argument == "--no-save":
			persistence_enabled = false
		elif argument.begins_with("--save-path="):
			save_path = argument.trim_prefix("--save-path=")
	if persistence_enabled:
		load_progress()
	apply_audio()


func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume_percent / 100.0, 0.0001)))
	AudioServer.set_bus_mute(0, audio_muted)


func set_audio_settings(volume: float, muted: bool) -> void:
	volume_percent = clampf(volume, 0.0, 100.0)
	audio_muted = muted
	apply_audio()
	save_progress()


func _valid_save(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != SAVE_VERSION:
		return false
	if not value.get("levels") is Dictionary or not value.get("audio") is Dictionary or not value.get("sessions") is Array:
		return false
	var audio: Dictionary = value.audio
	if not (audio.get("volume") is float or audio.get("volume") is int) or not audio.get("muted") is bool:
		return false
	if not is_finite(float(audio.volume)) or float(audio.volume) < 0 or float(audio.volume) > 100:
		return false
	for action in range(1, 6):
		var level: Variant = value.levels.get(str(action))
		if not (level is float or level is int) or level < 1 or level > 3 or float(level) != floorf(float(level)):
			return false
	for entry in value.sessions:
		if not entry is Dictionary or not entry.get("session_id") is String:
			return false
	return true


func _read_save(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return null
	var value: Variant = parser.data
	return value if _valid_save(value) else null


func load_progress() -> bool:
	var value: Variant = _read_save(save_path)
	if value == null:
		value = _read_save(save_path + ".bak")
	if value == null:
		return false
	for action in range(1, 6):
		unlocked_levels_by_action[action] = int(value.levels[str(action)])
	highest_unlocked_level = get_highest_unlocked_level(selected_action)
	volume_percent = float(value.audio.volume)
	audio_muted = bool(value.audio.muted)
	session_history = value.sessions.duplicate(true)
	apply_audio()
	return true


func save_progress() -> bool:
	if not persistence_enabled:
		return true
	var levels := {}
	for action in range(1, 6):
		levels[str(action)] = get_highest_unlocked_level(action)
	var value := {"version": SAVE_VERSION, "levels": levels,
		"audio": {"volume": volume_percent, "muted": audio_muted}, "sessions": session_history}
	var temporary := save_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return _save_failed("Không thể ghi dữ liệu tiến độ.")
	file.store_string(JSON.stringify(value, "\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or _read_save(temporary) == null:
		return _save_failed("Không thể hoàn tất ghi dữ liệu tiến độ.")
	# Preserve the last valid file, never replace a good backup with corrupt data.
	if _read_save(save_path) != null:
		if DirAccess.copy_absolute(save_path, save_path + ".bak") != OK:
			return _save_failed("Không thể tạo bản sao lưu tiến độ.")
	if DirAccess.rename_absolute(temporary, save_path) != OK:
		return _save_failed("Không thể cập nhật file tiến độ.")
	last_save_error = ""
	return true


func _save_failed(message: String) -> bool:
	last_save_error = message
	push_warning(message)
	return false


func record_session(summary: Dictionary) -> void:
	for entry in session_history:
		if entry.session_id == summary.session_id:
			return
	session_history.append(summary.duplicate(true))
	save_progress()

var speed_multiplier = 1.0
var highest_unlocked_level = 1
var unlocked_levels_by_action := {
	1: 1,
	2: 1,
	3: 1,
	4: 1,
	5: 1,
}

var selected_action = 1

const MAP_SCENES := {
	1: "res://maps/map_1/main_level.tscn",
	2: "res://maps/map_2/main_level.tscn",
	3: "res://maps/map_3/main_level.tscn",
	4: "res://maps/map_4/main_level.tscn",
	5: "res://maps/map_5/main_level.tscn",
}

# --- MỚI: Biến lưu biên độ tối đa (Max Range of Motion) ---
# Ví dụ: 100 là giơ tay thẳng đứng. Khởi tạo bằng 0.
var max_rom_angle = 0.0


func get_highest_unlocked_level(action_id: int) -> int:
	return int(unlocked_levels_by_action.get(action_id, 1))


func unlock_level_for_action(action_id: int, level: int) -> void:
	var next_level := clampi(level, 1, 3)
	unlocked_levels_by_action[action_id] = maxi(get_highest_unlocked_level(action_id), next_level)
	# Keep the old field synchronized for older UI/code that may still read it.
	highest_unlocked_level = get_highest_unlocked_level(action_id)
	save_progress()


func get_selected_map_scene() -> String:
	return str(MAP_SCENES.get(selected_action, ""))


func is_map_implemented(action_id: int) -> bool:
	return MAP_SCENES.has(action_id)
