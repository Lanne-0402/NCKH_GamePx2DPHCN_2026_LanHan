extends Node2D

@export var segment_width := 1152.0
@export var far_scroll_speed := 32.0
@export var near_scroll_speed := 85.0
@export var scroll_fade_speed := 4.0

var scrolling_enabled := true
var _scroll_blend := 0.0

@onready var far_layer: Node2D = $FarLayer
@onready var near_layer: Node2D = $NearLayer


func _process(delta: float) -> void:
	var target_blend := 1.0 if scrolling_enabled else 0.0
	_scroll_blend = move_toward(_scroll_blend, target_blend, scroll_fade_speed * delta)
	if _scroll_blend <= 0.001:
		return
	_scroll_layer(far_layer, far_scroll_speed * Global.speed_multiplier * _scroll_blend, delta)
	_scroll_layer(near_layer, near_scroll_speed * Global.speed_multiplier * _scroll_blend, delta)


func set_scrolling(enabled: bool) -> void:
	scrolling_enabled = enabled


func _scroll_layer(layer: Node2D, speed: float, delta: float) -> void:
	layer.position.x -= speed * delta
	if layer.position.x <= -segment_width:
		layer.position.x += segment_width
