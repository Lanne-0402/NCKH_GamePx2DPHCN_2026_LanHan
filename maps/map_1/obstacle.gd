extends Area2D

signal collided_with_player(player: Node)
signal reached_action_zone

const SPEED = 250.0

var _exercise_mode := false
var _movement_enabled := true
var _destroying := false
var _waiting_at_action_zone := false
var _action_zone_x := 0.0
var _exercise_approach_speed := 170.0

func _process(delta: float) -> void:
	if _destroying or not _movement_enabled:
		return
	var movement_speed: float = _exercise_approach_speed
	if not _exercise_mode:
		movement_speed = SPEED * float(Global.speed_multiplier)
	position.x -= movement_speed * delta
	if _exercise_mode and position.x <= _action_zone_x:
		position.x = _action_zone_x
		_waiting_at_action_zone = true
		_movement_enabled = false
		reached_action_zone.emit()
		return
	if position.x < -100:
		queue_free()


func configure_exercise_rock(action_zone_x: float, approach_speed: float) -> void:
	_exercise_mode = true
	_action_zone_x = action_zone_x
	_exercise_approach_speed = approach_speed


func set_movement_enabled(enabled: bool) -> void:
	_movement_enabled = enabled and not _waiting_at_action_zone


func destroy_by_exercise() -> void:
	if _destroying:
		return
	_destroying = true
	monitoring = false
	$CollisionShape2D.set_deferred("disabled", true)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.5, 0.35), 0.25).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	await tween.finished
	queue_free()

# Đây là hàm Godot vừa tự tạo cho bạn
func _on_body_entered(body):
	if body.name != "Player" or _destroying:
		return
	if _exercise_mode:
		_destroying = true
		_movement_enabled = false
		set_deferred("monitoring", false)
		$CollisionShape2D.set_deferred("disabled", true)
		collided_with_player.emit(body)
		queue_free()
		return
	body.take_damage()
	queue_free()
