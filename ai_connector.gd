extends Node

var socket := WebSocketPeer.new()
var url := "ws://127.0.0.1:8765"
var is_connected_to_server := false

func _ready():
	print("Đang kết nối tới server AI Python...")
	socket.connect_to_url(url)

func _process(_delta):
	# Cập nhật trạng thái WebSocket liên tục
	socket.poll()
	var state = socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected_to_server:
			is_connected_to_server = true
			print("Đã kết nối WebSocket thành công!")
			
			# Gửi tín hiệu chào hỏi đầu tiên theo JSON Contract
			send_client_hello()
			
			# Tạm thời giả lập việc Game yêu cầu bắt đầu Map 1 (Ép vai) sau 2 giây
			await get_tree().create_timer(2.0).timeout
			send_start_exercise()

		# Đọc dữ liệu Python gửi sang
		while socket.get_available_packet_count() > 0:
			var packet = socket.get_packet().get_string_from_utf8()
			handle_message(packet)

	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected_to_server:
			is_connected_to_server = false
			print("Kết nối đã đóng. Code lỗi: ", socket.get_close_code())

func send_client_hello():
	var message = {
		"contract_version": "1.0.0",
		"type": "client_hello",
		"message_id": "msg-frontend-001",
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
	socket.send_text(JSON.stringify(message))

func send_start_exercise():
	var message = {
		"contract_version": "1.0.0",
		"type": "start_exercise",
		"message_id": "msg-frontend-002",
		"session_id": "session-test-001",
		"timestamp_ms": Time.get_unix_time_from_system() * 1000,
		"source": "frontend",
		"payload": {
			"exercise_id": "scapular_retraction" # Mở khoá AI cho Map 1
		}
	}
	socket.send_text(JSON.stringify(message))
	print("Godot: Đã gửi yêu cầu start_exercise (Map 1)")

func handle_message(json_str: String):
	var json = JSON.new()
	var error = json.parse(json_str)
	
	if error == OK:
		var data = json.data
		var msg_type = data.get("type", "unknown")
		
		# Xử lý các loại tin nhắn nhận được
		if msg_type == "server_hello":
			print("Godot nhận: server_hello - Python đã sẵn sàng!")
		elif msg_type == "pose_frame":
			# Trích xuất dữ liệu khung hình (Frame) gửi từ Python
			var frame_id = data["payload"]["frame_id"]
			var angles = data["payload"]["angles"]
			print("Godot nhận pose_frame [", frame_id, "] - Dữ liệu góc: ", angles)
	else:
		print("Lỗi parse JSON từ Python: ", json_str)
