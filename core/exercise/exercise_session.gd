class_name ExerciseSession
extends Node

signal state_changed(current_state: State, previous_state: State)
signal progress_changed(rep_in_phase: int, reps_per_phase: int, phase: int, phase_count: int)
signal feedback_changed(code: String)
signal repetition_accepted(data: Dictionary)
signal repetition_rejected(data: Dictionary)
signal hold_started(data: Dictionary)
signal hold_progress_changed(progress: float, elapsed_ms: int, target_ms: int)
signal hold_interrupted(data: Dictionary)
signal rest_time_changed(seconds_remaining: float)
signal session_completed(summary: Dictionary)

enum State { IDLE, READY, ACTIVE, RESTING, PAUSED, TRACKING_LOST, COMPLETED }

var state: State = State.IDLE
var config: Dictionary = {}
var session_id := ""
var exercise_id := ""
var rep_in_phase := 0
var total_valid_reps := 0
var total_rejected_reps := 0
var current_phase := 1
var rest_seconds_remaining := 0.0
var repetition_input_enabled := true

var _session_started := false
var _state_before_tracking_loss: State = State.IDLE
var _accepted_candidate_ids: Dictionary = {}
var _pose_input: Node


func _ready() -> void:
	_pose_input = get_node("/root/PoseInput")
	_pose_input.connection_changed.connect(_on_connection_changed)
	_pose_input.tracking_status_changed.connect(_on_tracking_status_changed)
	_pose_input.exercise_event_received.connect(_on_exercise_event_received)
	_pose_input.provider_error_received.connect(_on_provider_error_received)


func _process(delta: float) -> void:
	if state != State.RESTING:
		return
	rest_seconds_remaining = maxf(rest_seconds_remaining - delta, 0.0)
	rest_time_changed.emit(rest_seconds_remaining)
	if rest_seconds_remaining <= 0.0:
		_finish_rest()


func start_session(session_config: Dictionary) -> bool:
	if not _validate_config(session_config):
		return false
	config = session_config.duplicate(true)
	session_id = str(config.get("session_id", "exercise-%d" % Time.get_ticks_msec()))
	exercise_id = str(config["exercise_id"])
	rep_in_phase = 0
	total_valid_reps = 0
	total_rejected_reps = 0
	current_phase = 1
	rest_seconds_remaining = 0.0
	repetition_input_enabled = true
	_accepted_candidate_ids.clear()
	_session_started = true
	_change_state(State.READY)
	_emit_progress()
	# Only recognition settings go to the provider. Godot owns rep targets,
	# phases and rest timing in config for the entire session.
	_pose_input.start_exercise({
		"session_id": session_id,
		"exercise_id": exercise_id,
		"difficulty": str(config.get("difficulty", "standard")),
		"target_side": str(config.get("target_side", "both")),
		"target_rom_ratio": float(config.get("target_rom_ratio", 0.85)),
		"calibrated_max_rom": float(config.get("calibrated_max_rom", 0.0)),
		"target_rom_value": float(config.get("target_rom_value", 0.0)),
		"minimum_movement_duration_ms": int(config.get("minimum_movement_duration_ms", 2000)),
		"maximum_movement_duration_ms": int(config.get("maximum_movement_duration_ms", 5000)),
		"hold_duration_ms": int(config.get("hold_duration_ms", 0)),
	})
	var tracking_ok := bool(_pose_input.last_tracking_status.get("person_detected", false)) \
			and bool(_pose_input.last_tracking_status.get("required_body_visible", false))
	if _pose_input.provider_connected and tracking_ok:
		_change_state(State.ACTIVE)
		feedback_changed.emit("SESSION_READY")
	else:
		_state_before_tracking_loss = State.ACTIVE
		_change_state(State.TRACKING_LOST)
		feedback_changed.emit("TRACKING_LOST")
	return true


func stop_session(reason := "user_cancelled") -> void:
	if not _session_started:
		return
	_session_started = false
	_pose_input.stop_exercise(reason)
	_change_state(State.IDLE)


func pause_session(reason := "user_paused") -> void:
	if not _session_started or state != State.ACTIVE:
		return
	_pose_input.pause_exercise(reason)
	_change_state(State.PAUSED)
	feedback_changed.emit("SESSION_PAUSED")


func resume_session() -> void:
	if not _session_started or state != State.PAUSED:
		return
	var tracking_ok := bool(_pose_input.last_tracking_status.get("person_detected", false)) \
			and bool(_pose_input.last_tracking_status.get("required_body_visible", false))
	if not _pose_input.provider_connected or not tracking_ok:
		_state_before_tracking_loss = State.PAUSED
		_change_state(State.TRACKING_LOST)
		feedback_changed.emit("TRACKING_LOST")
		return
	if repetition_input_enabled:
		_pose_input.resume_exercise()
	else:
		_pose_input.pause_exercise("waiting_for_action_zone")
	_change_state(State.ACTIVE)
	feedback_changed.emit("SESSION_RESUMED")


func set_repetition_input_enabled(enabled: bool, reason := "waiting_for_action_zone") -> void:
	var changed := repetition_input_enabled != enabled
	repetition_input_enabled = enabled
	if not _session_started or state != State.ACTIVE:
		return
	if enabled:
		_pose_input.resume_exercise()
		if changed:
			feedback_changed.emit("ACTION_ZONE_READY")
	else:
		_pose_input.pause_exercise(reason)
		if changed:
			feedback_changed.emit("ROCK_APPROACHING")


func debug_skip_rest() -> void:
	if state == State.RESTING:
		rest_seconds_remaining = 0.0
		_finish_rest()


func _on_exercise_event_received(data: Dictionary) -> void:
	if not _session_started or state != State.ACTIVE:
		return
	if not repetition_input_enabled:
		return
	if str(data.get("exercise_id", "")) != exercise_id:
		return
	match str(data.get("event", "")):
		"movement_started": feedback_changed.emit("MOVEMENT_STARTED")
		"target_reached": feedback_changed.emit("TARGET_REACHED")
		"hold_started":
			hold_started.emit(data)
			hold_progress_changed.emit(0.0, 0, int(config.get("hold_duration_ms", 0)))
			feedback_changed.emit("HOLD_STARTED")
		"hold_progress":
			var target_ms := int(data.get("hold_target_ms", config.get("hold_duration_ms", 0)))
			var elapsed_ms := int(data.get("hold_elapsed_ms", 0))
			var progress := float(data.get("hold_progress", 0.0))
			if target_ms > 0 and not data.has("hold_progress"):
				progress = float(elapsed_ms) / float(target_ms)
			hold_progress_changed.emit(clampf(progress, 0.0, 1.0), elapsed_ms, target_ms)
			feedback_changed.emit("HOLD_PROGRESS")
		"hold_completed":
			var target_ms := int(data.get("hold_target_ms", config.get("hold_duration_ms", 0)))
			hold_progress_changed.emit(1.0, target_ms, target_ms)
			feedback_changed.emit("HOLD_COMPLETED")
		"hold_interrupted":
			hold_interrupted.emit(data)
			hold_progress_changed.emit(0.0, 0, int(config.get("hold_duration_ms", 0)))
			feedback_changed.emit(str(data.get("feedback_code", "HOLD_INTERRUPTED")))
		"rep_completed": _accept_repetition(data)
		"rep_rejected":
			total_rejected_reps += 1
			repetition_rejected.emit(data)
			feedback_changed.emit(str(data.get("feedback_code", "REP_REJECTED")))


func _accept_repetition(data: Dictionary) -> void:
	var candidate_id := str(data.get("rep_candidate_id", ""))
	if candidate_id.is_empty() or _accepted_candidate_ids.has(candidate_id):
		return
	_accepted_candidate_ids[candidate_id] = true
	rep_in_phase += 1
	total_valid_reps += 1
	repetition_accepted.emit(data)
	feedback_changed.emit(str(data.get("feedback_code", "REP_VALID")))
	_emit_progress()
	if rep_in_phase < int(config["repetitions_per_phase"]):
		return
	if current_phase >= int(config["phase_count"]):
		_complete_session()
	else:
		_start_rest()


func _start_rest() -> void:
	rest_seconds_remaining = float(config.get("rest_duration_seconds", 30.0))
	_change_state(State.RESTING)
	_pose_input.pause_exercise("phase_rest")
	rest_time_changed.emit(rest_seconds_remaining)
	feedback_changed.emit("PHASE_REST")


func _finish_rest() -> void:
	if state != State.RESTING:
		return
	current_phase += 1
	rep_in_phase = 0
	_pose_input.resume_exercise()
	_change_state(State.ACTIVE)
	_emit_progress()
	feedback_changed.emit("NEXT_PHASE")


func _complete_session() -> void:
	_session_started = false
	_pose_input.stop_exercise("session_completed")
	_change_state(State.COMPLETED)
	session_completed.emit({
		"session_id": session_id,
		"exercise_id": exercise_id,
		"valid_reps": total_valid_reps,
		"rejected_reps": total_rejected_reps,
		"phase_count": int(config["phase_count"]),
	})
	feedback_changed.emit("SESSION_COMPLETED")


func _on_tracking_status_changed(data: Dictionary) -> void:
	if not _session_started:
		return
	var tracking_ok := bool(data.get("person_detected", false)) \
			and bool(data.get("required_body_visible", false))
	if not tracking_ok and state not in [State.TRACKING_LOST, State.COMPLETED, State.IDLE]:
		_state_before_tracking_loss = state
		_pose_input.pause_exercise("tracking_lost")
		_change_state(State.TRACKING_LOST)
		feedback_changed.emit("TRACKING_LOST")
	elif tracking_ok and state == State.TRACKING_LOST:
		if _state_before_tracking_loss == State.RESTING:
			_change_state(State.RESTING)
		elif _state_before_tracking_loss == State.PAUSED:
			_change_state(State.PAUSED)
		else:
			if repetition_input_enabled:
				_pose_input.resume_exercise()
			else:
				_pose_input.pause_exercise("waiting_for_action_zone")
			_change_state(State.ACTIVE)
		feedback_changed.emit("TRACKING_RESTORED")


func _on_connection_changed(connected: bool, _details: Dictionary) -> void:
	if _session_started and not connected and state != State.TRACKING_LOST:
		_state_before_tracking_loss = state
		_change_state(State.TRACKING_LOST)
		feedback_changed.emit("BACKEND_DISCONNECTED")


func _on_provider_error_received(data: Dictionary) -> void:
	if not _session_started:
		return
	feedback_changed.emit(str(data.get("code", "INTERNAL_ERROR")))
	if str(data.get("severity", "warning")) == "fatal":
		_state_before_tracking_loss = state
		_change_state(State.TRACKING_LOST)


func _change_state(next_state: State) -> void:
	if state == next_state:
		return
	var previous := state
	state = next_state
	state_changed.emit(state, previous)


func _emit_progress() -> void:
	progress_changed.emit(rep_in_phase, int(config["repetitions_per_phase"]), current_phase, int(config["phase_count"]))


func _validate_config(session_config: Dictionary) -> bool:
	for field in ["exercise_id", "repetitions_per_phase", "phase_count"]:
		if not session_config.has(field):
			push_error("ExerciseSession config is missing field: %s" % field)
			return false
	if int(session_config["repetitions_per_phase"]) <= 0 or int(session_config["phase_count"]) <= 0:
		push_error("ExerciseSession repetitions and phases must be greater than zero.")
		return false
	return true
