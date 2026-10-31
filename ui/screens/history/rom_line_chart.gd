class_name RomLineChart
extends Control

var _points: Array = []


func set_rom_points(points: Array) -> void:
	_points.clear()
	for item in points:
		if item is Dictionary and item.has("date") and item.has("rom_angle"):
			_points.append({
				"date": str(item["date"]),
				"rom_angle": clampf(float(item["rom_angle"]), 0.0, 120.0),
			})
	_points.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["date"]) < str(b["date"])
	)
	if _points.size() > 10:
		_points = _points.slice(_points.size() - 10, _points.size())
	queue_redraw()


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	# Background panel
	draw_rect(rect, Color(0.98, 0.97, 0.93, 1.0), true)
	draw_rect(rect, Color(0.72, 0.66, 0.52, 1.0), false, 2.0)

	var font: Font = ThemeDB.fallback_font
	var title_text: String = "BIỂU ĐỒ ĐƯỜNG TIẾN TRIỂN BIÊN ĐỘ VAI (ROM °) QUA CÁC NGÀY TẬP"
	draw_string(
		font,
		Vector2(18.0, 26.0),
		title_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		15,
		Color(0.18, 0.24, 0.18, 1.0)
	)

	if _points.is_empty():
		var empty_msg: String = "Chưa có dữ liệu ROM theo ngày. Hãy thực hiện Hiệu chuẩn (Calibration) hoặc luyện tập các Map để ghi nhận dữ liệu thật."
		draw_string(
			font,
			Vector2(24.0, size.y * 0.55),
			empty_msg,
			HORIZONTAL_ALIGNMENT_LEFT,
			size.x - 48.0,
			15,
			Color(0.42, 0.40, 0.35, 1.0)
		)
		return

	# Trend badge in top-right
	var first_rom: float = float(_points[0]["rom_angle"])
	var last_rom: float = float(_points[_points.size() - 1]["rom_angle"])
	var delta_rom: float = last_rom - first_rom
	var sign_str: String = "+" if delta_rom >= 0.0 else ""
	var badge_text: String = "Hiện tại: %.1f° (%s%.1f° sau %d ngày)" % [last_rom, sign_str, delta_rom, _points.size()]
	var badge_color: Color = Color(0.10, 0.55, 0.22, 1.0) if delta_rom >= 0.0 else Color(0.75, 0.25, 0.15, 1.0)
	draw_string(
		font,
		Vector2(maxf(size.x - 330.0, 420.0), 26.0),
		badge_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		15,
		badge_color
	)

	var pad_left: float = 58.0
	var pad_right: float = 32.0
	var pad_top: float = 46.0
	var pad_bottom: float = 36.0
	var plot_w: float = maxf(size.x - pad_left - pad_right, 100.0)
	var plot_h: float = maxf(size.y - pad_top - pad_bottom, 60.0)
	var max_y_deg: float = 100.0

	# Draw horizontal grid lines (0, 30, 60, 90 degrees)
	var grid_levels: Array[float] = [0.0, 30.0, 60.0, 90.0]
	for deg: float in grid_levels:
		var ratio: float = deg / max_y_deg
		var y: float = pad_top + plot_h * (1.0 - ratio)
		var is_target: bool = is_equal_approx(deg, 90.0)
		var line_col: Color = Color(0.15, 0.62, 0.28, 0.65) if is_target else Color(0.78, 0.74, 0.64, 0.65)
		var line_w: float = 2.0 if is_target else 1.0
		draw_line(Vector2(pad_left, y), Vector2(pad_left + plot_w, y), line_col, line_w)

		var label_str: String = "%d°" % int(deg)
		if is_target:
			label_str = "90° (Chuẩn)"
		draw_string(
			font,
			Vector2(6.0, y + 5.0),
			label_str,
			HORIZONTAL_ALIGNMENT_LEFT,
			pad_left - 8.0,
			12,
			Color(0.12, 0.50, 0.22, 1.0) if is_target else Color(0.35, 0.33, 0.28, 1.0)
		)

	# Calculate screen coordinates for each point
	var coords: Array[Vector2] = []
	var count: int = _points.size()
	for i in range(count):
		var x_ratio: float = 0.5 if count == 1 else float(i) / float(count - 1)
		var x: float = pad_left + x_ratio * plot_w
		var rom_val: float = clampf(float(_points[i]["rom_angle"]), 0.0, max_y_deg)
		var y: float = pad_top + plot_h * (1.0 - (rom_val / max_y_deg))
		coords.append(Vector2(x, y))

	# Draw shaded area under the curve when at least 2 points exist
	var baseline_y: float = pad_top + plot_h
	if coords.size() >= 2:
		var poly: PackedVector2Array = PackedVector2Array()
		poly.append(Vector2(coords[0].x, baseline_y))
		for pt in coords:
			poly.append(pt)
		poly.append(Vector2(coords[coords.size() - 1].x, baseline_y))
		draw_colored_polygon(poly, Color(0.16, 0.58, 0.32, 0.18))

		# Draw connecting polyline
		var line_pts: PackedVector2Array = PackedVector2Array(coords)
		draw_polyline(line_pts, Color(0.12, 0.52, 0.26, 1.0), 3.2, true)

	# Draw data points, value labels, and X-axis date labels
	for i in range(count):
		var pt: Vector2 = coords[i]
		var rom_val: float = float(_points[i]["rom_angle"])
		var date_str: String = _format_short_date(str(_points[i]["date"]))

		# Vertical subtle guide
		draw_line(Vector2(pt.x, pt.y), Vector2(pt.x, baseline_y), Color(0.55, 0.52, 0.45, 0.35), 1.0)

		# Outer & inner circle marker
		draw_circle(pt, 6.5, Color(0.10, 0.45, 0.22, 1.0))
		draw_circle(pt, 3.5, Color(0.98, 0.97, 0.92, 1.0))

		# ROM degree value above point
		var val_label: String = "%.1f°" % rom_val
		draw_string(
			font,
			Vector2(pt.x - 18.0, maxf(pt.y - 10.0, pad_top + 12.0)),
			val_label,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			13,
			Color(0.08, 0.35, 0.16, 1.0)
		)

		# Date label on X-axis
		draw_string(
			font,
			Vector2(pt.x - 18.0, baseline_y + 20.0),
			date_str,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			13,
			Color(0.25, 0.24, 0.20, 1.0)
		)


func _format_short_date(iso_date: String) -> String:
	var parts: PackedStringArray = iso_date.split("-")
	if parts.size() >= 3:
		return "%s/%s" % [parts[2], parts[1]]
	return iso_date
