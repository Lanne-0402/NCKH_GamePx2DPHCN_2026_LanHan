extends Node

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


func get_selected_map_scene() -> String:
	return str(MAP_SCENES.get(selected_action, ""))


func is_map_implemented(action_id: int) -> bool:
	return MAP_SCENES.has(action_id)
