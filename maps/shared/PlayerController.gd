# PlayerController.gd
extends CharacterBody2D

@onready var anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var vfx_wave: Area2D = $EnergyWaveArea  # Dành cho Map 3

var current_map_index := 1
var is_holding := false

func _ready() -> void:
	AIConnector.rep_completed.connect(_on_ai_rep_completed)
	AIConnector.rep_rejected.connect(_on_ai_rep_rejected)
	AIConnector.hold_started.connect(_on_ai_hold_started)
	AIConnector.hold_broken.connect(_on_ai_hold_broken)

# --- MAP 1: PHÁ ĐÁ MỞ ĐƯỜNG ---
func execute_map1_break_rock() -> void:
	# Nhân vật chúi đầu gồng lực phá vỡ chướng ngại vật mà không dừng chạy
	anim.play("headbutt_smash")
	# Gọi đối tượng đá gần nhất để kích hoạt vỡ vụn
	var current_rock = get_tree().get_first_node_in_group("active_rock")
	if current_rock:
		current_rock.shatter()

# --- MAP 2: NÂNG TẢNG ĐÁ ---
func execute_map2_lift_boulder() -> void:
	anim.play("lift_push_up")
	var current_boulder = get_tree().get_first_node_in_group("active_boulder")
	if current_boulder:
		current_boulder.push_back_up()

# --- MAP 3: ĐẨY LÙI TƯỜNG GAI ---
func execute_map3_energy_wave() -> void:
	anim.play("release_energy")
	if vfx_wave:
		vfx_wave.emit_shockwave() # Đẩy lùi tường gai về vị trí cũ

# --- MAP 4: LEO VÁCH ĐÁ CAO ---
func execute_map4_leap() -> void:
	anim.play("leap_across")
	# Nhảy sang bậc đá tiếp theo
	var tween = create_tween()
	tween.tween_property(self, "position:x", position.x + 220.0, 0.8)
	tween.parallel().tween_property(self, "position:y", position.y - 60.0, 0.4)
	tween.chain().tween_property(self, "position:y", position.y, 0.4)

# --- MAP 5: THIỀN ĐỊNH SUỐI NƯỚC NÓNG ---
func set_meditation_mode(active: bool) -> void:
	if active:
		anim.play("meditate_hotspring")
	else:
		anim.play("relax")

# --- LẮNG NGHE TÍN HIỆU TỪ AICONNECTOR ---
func _on_ai_rep_completed(_ex_id: String, _rep_id: String) -> void:
	match current_map_index:
		1: execute_map1_break_rock()
		2: execute_map2_lift_boulder()
		3: execute_map3_energy_wave()
		4: execute_map4_leap()
		5: 
			# Map 5: Hoàn thành đợt kéo giãn cơ
			anim.play("power_up")

func _on_ai_rep_rejected(feedback: String) -> void:
	# Cảnh báo giật tay quá nhanh bằng hiệu ứng chớp đỏ
	modulate = Color.RED
	var tween = create_tween()
	tween.tween_property(self, "modulate", Color.WHITE, 0.3)

func _on_ai_hold_started() -> void:
	is_holding = true
	if current_map_index == 2:
		anim.play("holding_heavy_load")
	elif current_map_index == 4:
		anim.play("hands_on_head_run")

func _on_ai_hold_broken() -> void:
	is_holding = false
	if current_map_index == 2:
		anim.play("struggling")
