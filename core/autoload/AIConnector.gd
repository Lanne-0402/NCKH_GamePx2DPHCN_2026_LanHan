# AIConnector.gd (Cài đặt làm Autoload trong Project Settings)
extends Node

signal connection_established
signal pose_frame_updated(rom_prog: float, hold_prog: float, feedback_code: String)
signal rep_completed(exercise_id: String, rep_id: String)
signal rep_rejected(feedback_code: String)
signal hold_started
signal hold_broken

var socket := WebSocketPeer.new()
var url := "ws://127.0.0.1:8765"
var is_connected := false
var last_processed_rep_id := ""

# Từ điển ánh xạ feedback_code sang thông báo tiếng Việt theo JSON Contract
const FEEDBACK_DICT := {
	"POSITION_OK": "Tư thế chuẩn xác!",
	"CONTINUE_MOVEMENT": "Cử động chậm rãi, đều nhịp...",
	"KEEP_POSITION": "Giữ nguyên tư thế!",
	"MOVEMENT_TOO_FAST": "Cử động quá nhanh! Hãy làm chậm lại.",
	"TARGET_NOT_REACHED": "Chưa đạt biên độ yêu cầu!",
	"REP_VALID": "Đạt chuẩn! Rất tốt!",
	"TRACKING_LOST": "Mất dấu người chơi! Vui lòng đứng trước camera."
}

func _ready() -> void:
	socket.connect_to_url(url)

func _process(_delta: float) -> void:
	socket.poll()
	var state = socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			is_connected = true
			send_client_hello()
			connection_established.emit()

		while socket.get_available_packet_count() > 0:
			var packet_str = socket.get_packet().get_string_from_utf8()
			_parse_packet(packet_str)

	elif state == WebSocketPeer.STATE_CLOSED:
		is_connected = false

func send_client_hello() -> void:
	var msg = {
		"contract_version": "1.0.0",
		"type": "client_hello",
		"message_id": "msg-front-init",
		"session_id": null,
		"timestamp_ms": Time.get_unix_time_from_system() * 1000,
		"source": "frontend",
		"payload": {
			"application": "shoulder-rehabilitation-game",
			"frontend": "godot",
			"frontend_version": "0.1.0",
			"platform": "windows",
			"requested_pose_fps": 15
		}
	}
	socket.send_text(JSON.stringify(msg))

func request_start_exercise(exercise_id: String, session_id: String = "session-001") -> void:
	var msg = {
		"contract_version": "1.0.0",
		"type": "start_exercise",
		"message_id": "msg-front-start",
		"session_id": session_id,
		"timestamp_ms": Time.get_unix_time_from_system() * 1000,
		"source": "frontend",
		"payload": {
			"exercise_id": exercise_id,
			"difficulty": "standard"
		}
	}
	socket.send_text(JSON.stringify(msg))

func request_stop_exercise(reason: String = "session_completed") -> void:
	var msg = {
		"contract_version": "1.0.0",
		"type": "stop_exercise",
		"message_id": "msg-front-stop",
		"session_id": "session-001",
		"timestamp_ms": Time.get_unix_time_from_system() * 1000,
		"source": "frontend",
		"payload": {"reason": reason}
	}
	socket.send_text(JSON.stringify(msg))

func _parse_packet(json_str: String) -> void:
	var json = JSON.new()
	if json.parse(json_str) != OK:
		return

	var data = json.data
	var msg_type = data.get("type", "")
	var payload = data.get("payload", {})

	if msg_type == "pose_frame":
		var ex = payload.get("exercise", {})
		var rom = ex.get("rom_progress", 0.0)
		var hold = ex.get("hold_progress", 0.0)
		var code = ex.get("feedback_code", "POSITION_OK")
		pose_frame_updated.emit(rom, hold, code)

	elif msg_type == "exercise_event":
		var event = payload.get("event", "")
		var ex_id = payload.get("exercise_id", "")
		var rep_id = payload.get("rep_candidate_id", "")
		var feedback = payload.get("feedback_code", "")

		match event:
			"hold_started":
				hold_started.emit()
			"hold_broken":
				hold_broken.emit()
			"rep_completed":
				# Chống cộng trùng rep
				if rep_id != last_processed_rep_id:
					last_processed_rep_id = rep_id
					rep_completed.emit(ex_id, rep_id)
			"rep_rejected":
				rep_rejected.emit(feedback)
