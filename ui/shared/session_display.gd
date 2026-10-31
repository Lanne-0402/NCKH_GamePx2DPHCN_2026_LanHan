extends RefCounted
static func compact_details(data: Dictionary) -> String:
	var lines := PackedStringArray()
	if data.get("profile_id") != null: lines.append(profile(data))
	if data.has("target_reps") or data.has("target_sets"): lines.append(goals(data))
	for item in [["active_seconds", "Tập thực tế"], ["rest_seconds", "Nghỉ giữa hiệp"], ["paused_seconds", "Tạm dừng"], ["tracking_lost_seconds", "Mất nhận diện"]]:
		if number(data, item[0]) != "—": lines.append(item[1] + ": " + duration(data, item[0]))
	if lines.is_empty(): return "Thông tin bổ sung chưa khả dụng cho buổi tập này."
	return "\n".join(lines)

## Proposed optional BE fields. Missing/null values must never become measured zero.
static func number(data: Dictionary, key: String) -> String:
	var value: Variant = data.get(key)
	if (value is int or value is float) and is_finite(float(value)) and float(value) >= 0:
		return str(int(value))
	return "—"

static func duration(data: Dictionary, key: String) -> String:
	var value := number(data, key)
	if value == "—": return "Chưa có dữ liệu"
	var seconds := int(value)
	return "%02d:%02d:%02d" % [seconds / 3600, (seconds % 3600) / 60, seconds % 60]

static func profile(data: Dictionary) -> String:
	var value: Variant = data.get("profile_id")
	if value == null or str(value).strip_edges().is_empty(): return "Hồ sơ: Chưa xác định"
	return "Hồ sơ: " + str(value)

static func status(data: Dictionary) -> String:
	match str(data.get("status", "")):
		"completed": return "Hoàn thành"
		"stopped_early": return "Dừng sớm"
		"interrupted": return "Gián đoạn"
		_: return "Chưa có trạng thái"

static func goals(data: Dictionary) -> String:
	return "Số lần hoàn thành / mục tiêu: %s / %s   •   Số hiệp: %s / %s" % [number(data, "completed_reps"), number(data, "target_reps"), number(data, "completed_sets"), number(data, "target_sets")]

static func details(data: Dictionary) -> String:
	return "Tập thực tế: %s\nNghỉ giữa hiệp: %s\nTạm dừng: %s\nMất nhận diện: %s" % [duration(data, "active_seconds"), duration(data, "rest_seconds"), duration(data, "paused_seconds"), duration(data, "tracking_lost_seconds")]
